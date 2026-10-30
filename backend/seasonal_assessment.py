"""Saved retrospective monthly context, independent of model/range scoring.

NASA POWER monthly meteorological values retain their response units. Monthly
PRECTOTCORR is a mean daily rate; convert each year's rate by that month's
actual number of days before averaging totals (including leap Februaries).
No local planting calendar has a reviewed source yet, so no in-season claim
or score adjustment is made. Existing legacy cache rows lack unit/count
metadata and are deliberately not admitted to this versioned snapshot.
"""
from calendar import month_name, monthrange
from collections import OrderedDict
from copy import deepcopy
from datetime import datetime, timezone
from math import isfinite
from threading import Lock
from time import monotonic

import requests

VERSION = 'seasonal-context-v1'
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
        'retrieved_at': utc_now(), 'metrics': {},
        'limitations': ['Historical monthly context is not a forecast or a crop planting calendar.'],
    }


def parse_baseline(payload, lat, lon, month):
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
    return result


def fetch_baseline(lat, lon, month):
    # Exact requested point avoids attributing another farm's point query to
    # this parcel. Bounds limit memory and failure caching prevents retry storms.
    key = (float(lat), float(lon), month, VERSION)
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
            'parameters': 'T2M,PRECTOTCORR,RH2M', 'community': 'AG',
            'longitude': lon, 'latitude': lat, 'start': START_YEAR,
            'end': END_YEAR, 'format': 'JSON',
        }, timeout=(3, 8))
        response.raise_for_status()
        result = parse_baseline(response.json(), lat, lon, month)
    except Exception:
        # Exception details can contain transport settings; store only a bounded
        # user-facing failure state, never a substituted climate measurement.
        result['limitations'].append('Monthly climate provider unavailable or returned an invalid response. Retry a new analysis later.')
    result['cache_hit'] = False
    ttl = 86400 if result['status'] == 'available' else 300
    with _LOCK:
        _CACHE[key] = (monotonic() + ttl, deepcopy(result))
        _CACHE.move_to_end(key)
        while len(_CACHE) > CACHE_LIMIT:
            _CACHE.popitem(last=False)
    return result


def attach_seasonal_assessment(result, baseline, month):
    """Attach new evidence; do not mutate ranks, annual grades or model inputs."""
    name = month_name[month]
    monthly = deepcopy(baseline)
    # Old provider/cache shapes cannot establish this version's units/counts.
    valid = monthly.get('version') == VERSION and monthly.get('selected_month') == month
    if not valid:
        monthly = empty_baseline(result.get('lat'), result.get('lon'), month)
        monthly['limitations'].append('Monthly response lacks the required version, units or selected-month metadata.')
    status = monthly['status']
    summary = (f'{name} historical climate context ({START_YEAR}-{END_YEAR}) is '
               + {'available': 'available.', 'partial': 'partially available; check valid-year counts.',
                  'unavailable': 'unavailable; no seasonal suitability conclusion is made.'}[status])
    summary += ' This is retrospective context, not a forecast. Model scores and crop order are unchanged.'
    separate = []
    for field in ('rainfall_annual_mean_5y_mm', 'temperature_mean_5y_c', 'rainfall_30d_mm', 'humidity_current_pct'):
        metadata = deepcopy((result.get('climate_field_metadata') or {}).get(field) or {})
        separate.append({'field': field, 'value': result.get(field), **metadata})
    result['intended_planting_month'] = month
    result['intended_planting_month_name'] = name
    result['seasonal_assessment'] = {
        'version': VERSION, 'status': status, 'selected_month': month, 'selected_month_name': name,
        'captured_at': utc_now(), 'year_interpretation': 'Calendar month only; no planting year or forecast selected',
        'monthly_climate': monthly, 'separate_current_and_annual_observations': separate,
        'calendar': {'status': 'unavailable', 'source': None,
                     'reason': 'No reviewed local crop planting calendar with traceable source and validity scope is configured; no In season label is assigned.'},
        'summary': summary,
        'limitations': [*monthly.get('limitations', []),
                        'Annual climate references, selected-month climate, completed 30-day rainfall and current humidity describe different periods; they are not blended or compared as equivalent totals.',
                        'Historical grid conditions do not establish irrigation, soil moisture, planting safety or future weather. Verify local conditions before planting.'],
        'ranking_effect': 'none',
    }
    return result
