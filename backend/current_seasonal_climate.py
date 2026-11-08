"""Current-year monthly evidence, kept separate from model and climate normals.

Never fill a missing current/future month, annualize an incomplete year, or
turn a station probability forecast into parcel rainfall or a crop score.
"""
from calendar import month_name, monthrange
from datetime import date, datetime, timezone
import hashlib
import json
from math import isfinite
from pathlib import Path

from city_boundary import contains_point
from seasonal_planting import eto_month

VERSION = 'current-year-climate-v1'
FORECAST_PATH = Path(__file__).parent / 'data' / 'pagasa_monthly_outlooks.json'


def finite(value):
    return float(value) if not isinstance(value, bool) and isinstance(value, (int, float)) and isfinite(value) else None


def parse_current_year(payload, lat, lon, month, as_of=None):
    if isinstance(month, bool) or month not in range(1, 13):
        raise ValueError('Planting month must be 1 through 12.')
    as_of = as_of or datetime.now(timezone.utc).date()
    if isinstance(as_of, datetime):
        as_of = as_of.date()
    year = as_of.year
    parameters = (payload.get('properties') or {}).get('parameter') or {}
    metadata = payload.get('parameters') or {}
    fill = finite((payload.get('header') or {}).get('fill_value'))

    def reading(parameter, selected, unit, low, high):
        if (metadata.get(parameter) or {}).get('units') != unit:
            return None
        series = parameters.get(parameter)
        value = finite(series.get(f'{year}{selected:02d}')) if isinstance(series, dict) else None
        return value if value is not None and value != fill and low <= value <= high else None

    rows = []
    for selected in range(1, 13):
        closed = date(year, selected, monthrange(year, selected)[1]) < as_of
        temp = reading('T2M', selected, 'C', -90, 65) if closed else None
        humidity = reading('RH2M', selected, '%', 0, 100) if closed else None
        rate = reading('PRECTOTCORR', selected, 'mm/day', 0, 10000) if closed else None
        rain = rate * monthrange(year, selected)[1] if rate is not None else None
        low = reading('T2M_MIN_AVG', selected, 'C', -90, 65) if closed else None
        high = reading('T2M_MAX_AVG', selected, 'C', -90, 65) if closed else None
        eto = eto_month(lat, year, selected, temp, low, high) if closed else None
        ratio = rain / eto if rain is not None and eto is not None else None
        count = sum(value is not None for value in (temp, humidity, rain))
        rows.append({
            'year': year, 'month': selected, 'month_name': month_name[selected],
            'period_start': date(year, selected, 1).isoformat(),
            'period_end': date(year, selected, monthrange(year, selected)[1]).isoformat(),
            'status': 'available' if count == 3 else 'partial' if count else 'unavailable',
            'reason': None if count == 3 else 'Month not complete' if not closed else 'Provider values missing or incompatible',
            'temperature_c': temp, 'humidity_pct': humidity, 'rainfall_mm': rain,
            'reference_eto_mm': eto, 'rainfall_eto_ratio': ratio,
            'moisture_status': 'unavailable' if ratio is None else 'dry' if ratio < .5 else 'intermediate' if ratio < 1 else 'humid',
        })
    complete = [row for row in rows if row['status'] == 'available']
    return {
        'version': VERSION, 'year': year, 'as_of': as_of.isoformat(),
        'status': 'available' if complete else 'unavailable',
        'source_name': 'NASA POWER',
        'source_url': 'https://power.larc.nasa.gov/api/temporal/monthly/point',
        'documentation_url': 'https://power.larc.nasa.gov/docs/services/api/temporal/monthly/',
        'source_payload_sha256': hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest(),
        'requested_location': {'latitude': lat, 'longitude': lon},
        'quality': 'modelled', 'period': 'current_year_completed_calendar_months',
        'units': {'temperature': 'C', 'humidity': '%', 'rainfall': 'mm/month'},
        'selected_month': month, 'selected': rows[month - 1],
        'latest_complete_month': complete[-1] if complete else None,
        'complete_month_count': len(complete), 'months': rows,
        'annual_rainfall_mm': None, 'used_for_model_ranking': False,
        'limitation': 'Gridded monthly estimates, not field measurements or a forecast. Incomplete months are omitted. No complete-year total is assigned.',
    }


def published_outlook(lat, lon, month, as_of=None):
    as_of = as_of or datetime.now(timezone.utc).date()
    if isinstance(as_of, datetime):
        as_of = as_of.date()
    result = {'status': 'unavailable', 'year': as_of.year, 'month': month,
              'used_for_model_ranking': False,
              'source_url': 'https://www.pagasa.dost.gov.ph/climate/climate-prediction/seasonal-forecast'}
    if finite(lat) is None or finite(lon) is None or not contains_point(lat, lon):
        return {**result, 'reason': 'The configured station outlook is a regional reference for the Panabo project area only.'}
    try:
        records = json.loads(FORECAST_PATH.read_text(encoding='utf-8'))['records']
        for row in records:
            if (row['year'], row['month']) != (as_of.year, month):
                continue
            if not date.fromisoformat(row['issued_on']) <= as_of <= date.fromisoformat(row['valid_until']):
                continue
            values = [finite(row['probabilities_pct'].get(key)) for key in ('below_normal', 'near_normal', 'above_normal')]
            if any(value is None or not 0 <= value <= 100 for value in values) or abs(sum(values) - 100) > 1:
                continue
            return {**result, **row, 'status': 'available',
                    'scope': 'Tagum station outlook; regional reference near Panabo, not a forecast for the analyzed parcel.',
                    'interpretation': 'Probabilities relative to the station rainfall normal. Below normal does not mean a dry season or establish field water supply.',
                    'forecast': True, 'used_for_model_ranking': False}
    except (OSError, ValueError, KeyError, TypeError):
        pass
    return {**result, 'reason': 'No reviewed, currently valid station forecast is configured for this selected month and year.'}
