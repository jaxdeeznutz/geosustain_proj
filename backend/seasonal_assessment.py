"""Saved monthly climate and reference-based seasonal planting assessment.

NASA POWER monthly meteorological values retain their response units. Monthly
PRECTOTCORR is a mean daily rate; convert each year's rate by that month's
actual number of days before averaging totals (including leap Februaries).
Seasonal advice is a separate reference screen, not a trained seasonal model
or a reviewed local planting calendar. Existing legacy cache rows lack unit/count
metadata and are deliberately not admitted to this versioned snapshot.
"""
from calendar import month_name, monthrange
from collections import OrderedDict
from copy import deepcopy
from datetime import datetime, timezone
from zoneinfo import ZoneInfo
from math import isfinite
from threading import Lock
from time import monotonic

import requests
from seasonal_planting import eto_month, planting_assessment
from current_seasonal_climate import parse_current_year, published_outlook

VERSION = 'seasonal-context-v3'
PAGASA_SEASON_SOURCE = 'https://www.pagasa.dost.gov.ph/information/climate-philippines'


def calendar_season(month):
    if isinstance(month, bool) or month not in range(1, 13):
        raise ValueError('Season month must be 1 through 12.')
    return 'Rainy season' if 6 <= month <= 11 else 'Dry season'
START_YEAR, END_YEAR = 2005, 2024
URL = 'https://power.larc.nasa.gov/api/temporal/monthly/point'
DOCS = 'https://power.larc.nasa.gov/docs/services/api/temporal/monthly/'
YEARS = list(range(START_YEAR, END_YEAR + 1))
_CACHE = OrderedDict()
_LOCK = Lock()
CACHE_LIMIT = 128


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def number(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return float(value) if isfinite(value) else None


def empty_baseline(lat, lon, month):
    if isinstance(month, bool) or month not in range(1, 13):
        raise ValueError('Planting month must be 1 through 12.')
    return {
        'version': VERSION, 'status': 'unavailable', 'selected_month': month,
        'baseline_start_year': START_YEAR, 'baseline_end_year': END_YEAR,
        'source_name': 'NASA POWER', 'source_url': URL, 'documentation_url': DOCS,
        'requested_location': {'latitude': lat, 'longitude': lon},
        'spatial_method': 'Meteorological grid queried at the analysis representative point; not a parcel average or field measurement',
        'spatial_resolution': 'Native meteorological grid; numeric resolution is not supplied in this response contract',
        'retrieved_at': utc_now(), 'metrics': {}, 'monthly_cycle': [],
        'limitations': ['Historical monthly climate is not a forecast or an official local crop planting calendar.'],
    }


def parse_baseline(payload, lat, lon, month, as_of=None):
    result = empty_baseline(lat, lon, month)
    parameters = (payload.get('properties') or {}).get('parameter') or {}
    metadata = payload.get('parameters') or {}
    fill = number((payload.get('header') or {}).get('fill_value'))
    specs = [
        ('temperature', 'T2M', 'C', 'C', 'mean_temperature_c', -90, 65),
        ('rainfall', 'PRECTOTCORR', 'mm/day', 'mm/month', 'mean_monthly_rainfall_mm', 0, None),
        ('humidity', 'RH2M', '%', '%', 'mean_humidity_pct', 0, 100),
    ]
    for name, parameter, expected_unit, unit, alias, low, high in specs:
        source_unit = (metadata.get(parameter) or {}).get('units')
        series = parameters.get(parameter) or {}
        values, years = [], []
        if source_unit == expected_unit and isinstance(series, dict):
            for year in YEARS:
                value = number(series.get(f'{year}{month:02d}'))
                if value is None or value == fill or value < low or (high is not None and value > high):
                    continue
                values.append(value * monthrange(year, month)[1] if name == 'rainfall' else value)
                years.append(year)
        count = len(values)
        status = 'available' if count == len(YEARS) else 'partial' if count else 'unavailable'
        mean = sum(values) / count if count else None
        metric = {
            'value': mean, 'unit': unit, 'source_parameter': parameter,
            'source_unit': source_unit, 'quality': 'modelled' if count else 'unavailable',
            'status': status, 'valid_observations': count, 'expected_observations': len(YEARS),
            'valid_years': years, 'period': 'selected_calendar_month_across_baseline_years',
            'method': ('Mean of each year\'s daily precipitation rate multiplied by its calendar-month length'
                       if name == 'rainfall' else 'Arithmetic mean of valid selected-month values across baseline years'),
        }
        if source_unit != expected_unit:
            metric['unavailable_reason'] = 'Missing or incompatible provider unit'
        result['metrics'][name] = metric
        result[alias] = mean
        if status != 'available':
            result['limitations'].append(f'{name.title()}: {count}/{len(YEARS)} valid selected-month observations; no missing years were filled.')
    statuses = [metric['status'] for metric in result['metrics'].values()]
    result['status'] = ('available' if all(s == 'available' for s in statuses)
                        else 'unavailable' if all(s == 'unavailable' for s in statuses) else 'partial')
    # The provider response already contains every month. Keep the whole cycle
    # and paired-year evidence; never obtain monthly rain by dividing annual rain.
    def observation(parameter, year, selected, expected, low, high=None):
        if (metadata.get(parameter) or {}).get('units') != expected:
            return None
        series = parameters.get(parameter)
        value = number(series.get(f'{year}{selected:02d}')) if isinstance(series, dict) else None
        if value is None or value == fill or value < low or (high is not None and value > high):
            return None
        return value

    for selected in range(1, 13):
        rain_values, paired_rain, eto_values, valid_years = [], [], [], []
        for year in YEARS:
            rate = observation('PRECTOTCORR', year, selected, 'mm/day', 0)
            rain = rate * monthrange(year, selected)[1] if rate is not None else None
            if rain is not None:
                rain_values.append(rain)
            temps = [observation(p, year, selected, 'C', -90, 65) for p in ('T2M', 'T2M_MIN_AVG', 'T2M_MAX_AVG')]
            eto = eto_month(lat, year, selected, *temps)
            if rain is not None and eto is not None:
                paired_rain.append(rain)
                eto_values.append(eto)
                valid_years.append(year)
        complete = len(valid_years) == len(YEARS)
        paired_mean = sum(paired_rain) / len(paired_rain) if paired_rain else None
        eto_mean = sum(eto_values) / len(eto_values) if eto_values else None
        ratio = paired_mean / eto_mean if complete else None
        result['monthly_cycle'].append({
            'month': selected, 'month_name': month_name[selected],
            'rainfall_mm': sum(rain_values) / len(rain_values) if rain_values else None,
            'rainfall_unit': 'mm/month',
            'rainfall_status': 'available' if len(rain_values) == len(YEARS) else 'partial' if rain_values else 'unavailable',
            'rainfall_valid_years': len(rain_values),
            'reference_eto_mm': eto_mean, 'eto_unit': 'mm/month',
            'paired_rainfall_mm': paired_mean, 'rainfall_eto_ratio': ratio,
            'paired_valid_years': valid_years, 'expected_years': len(YEARS),
            'moisture_status': 'unavailable' if ratio is None else 'dry' if ratio < .5 else 'intermediate' if ratio < 1 else 'humid',
            'eto_method': 'FAO-56 eq.52 Hargreaves estimate from monthly means of daily T2M/T2M_MIN_AVG/T2M_MAX_AVG, with daily astronomical Ra; uncalibrated',
        })
    result['current_year_climate'] = parse_current_year(payload, lat, lon, month, as_of)
    return result


def fetch_baseline(lat, lon, month):
    # Exact requested point avoids attributing another farm's point query to
    # this parcel. Bounds limit memory and failure caching prevents retry storms.
    today = datetime.now(timezone.utc).date()
    key = (float(lat), float(lon), month, VERSION, today.isoformat())
    now = monotonic()
    with _LOCK:
        prior = _CACHE.get(key)
        if prior and now < prior[0]:
            _CACHE.move_to_end(key)
            value = deepcopy(prior[1])
            value['cache_hit'] = True
            return value
    result = empty_baseline(lat, lon, month)
    try:
        response = requests.get(URL, params={
            'parameters': 'T2M,T2M_MIN_AVG,T2M_MAX_AVG,PRECTOTCORR,RH2M', 'community': 'AG',
            'longitude': lon, 'latitude': lat, 'start': START_YEAR,
            'end': today.year, 'format': 'JSON',
        }, timeout=(3, 8))
        response.raise_for_status()
        result = parse_baseline(response.json(), lat, lon, month, today)
    except Exception:
        # Exception details can contain transport settings; store only a bounded
        # user-facing failure state, never a substituted climate measurement.
        result['limitations'].append('Monthly climate provider unavailable or returned an invalid response. Retry a new analysis later.')
    result['cache_hit'] = False
    result.setdefault('current_year_climate', parse_current_year({}, lat, lon, month, today))
    ttl = 21600 if result['status'] == 'available' else 300
    with _LOCK:
        _CACHE[key] = (monotonic() + ttl, deepcopy(result))
        _CACHE.move_to_end(key)
        while len(_CACHE) > CACHE_LIMIT:
            _CACHE.popitem(last=False)
    return result


def attach_seasonal_assessment(result, baseline, month, enabled_crops=None):
    """Attach new evidence; do not mutate ranks, annual grades or model inputs."""
    name = month_name[month]
    local_today = datetime.now(ZoneInfo('Asia/Manila')).date()
    monthly = deepcopy(baseline)
    # Old provider/cache shapes cannot establish this version's units/counts.
    valid = monthly.get('version') == VERSION and monthly.get('selected_month') == month
    if not valid:
        monthly = empty_baseline(result.get('lat'), result.get('lon'), month)
        monthly['limitations'].append('Monthly response lacks the required version, units or selected-month metadata.')
    status = monthly['status']
    planting = planting_assessment(monthly, month, enabled_crops)
    cover = result.get('land_cover') or {}
    if cover.get('allow_crops') is False:
        planting['status'] = 'unavailable'
        planting['land_cover_notice'] = 'The land assessment does not allow crop recommendations. Seasonal climate alone cannot override that decision.'
        for crop in planting['crops']:
            crop.update(status='unavailable', label='Seasonal planting blocked by land assessment', moisture_supported_months=[])
            crop['reasons'].insert(0, planting['land_cover_notice'])
    summary = (f'{name} historical climate context ({START_YEAR}-{END_YEAR}) is '
               + {'available': 'available.', 'partial': 'partially available; check valid-year counts.',
                  'unavailable': 'unavailable; no seasonal suitability conclusion is made.'}[status])
    summary += ' Current-year estimates and dated station outlooks are saved separately when available. Planting guidance uses historical monthly moisture. Model scores and crop order are unchanged.'
    separate = []
    for field in ('rainfall_annual_mean_5y_mm', 'temperature_mean_5y_c', 'humidity_current_pct'):
        metadata = deepcopy((result.get('climate_field_metadata') or {}).get(field) or {})
        separate.append({'field': field, 'value': result.get(field), **metadata})
    result['intended_planting_month'] = month
    result['intended_planting_month_name'] = name
    result['seasonal_assessment'] = {
        'version': VERSION, 'status': status, 'selected_month': month, 'selected_month_name': name,
        'calendar_season': {
            'selected_month_label': calendar_season(month),
            'current_label': calendar_season(local_today.month),
            'current_date': local_today.isoformat(),
            'scope': 'PAGASA Philippine calendar seasons; not a parcel rainfall observation or planting-readiness judgment',
            'source_url': PAGASA_SEASON_SOURCE,
            'used_for_model_ranking': False,
        },
        'captured_at': utc_now(), 'year_interpretation': 'Calendar month selected; current-year estimates are retrospective and dated station outlooks are separate forecasts',
        'monthly_climate': monthly, 'separate_current_and_annual_observations': separate,
        'current_year_climate': deepcopy(monthly.get('current_year_climate') or {}),
        'current_year_outlook': published_outlook(
            (monthly.get('requested_location') or {}).get('latitude'),
            (monthly.get('requested_location') or {}).get('longitude'), month),
        'planting_assessment': planting,
        'calendar': {'status': 'unavailable', 'source': None,
                     'reason': 'No reviewed local crop planting calendar with traceable source and validity scope is configured; no In season label is assigned.'},
        'summary': summary,
        'limitations': [*monthly.get('limitations', []),
                        'Five-year annual climate references, selected-month climate and current humidity describe different periods; they are not blended or compared as equivalent totals.',
                        'Historical grid conditions do not establish irrigation, soil moisture, planting safety or future weather. Verify local conditions before planting.'],
        'ranking_effect': 'none',
    }
    return result
