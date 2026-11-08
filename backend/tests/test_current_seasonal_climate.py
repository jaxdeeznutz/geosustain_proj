"""Current-year estimates and dated regional forecasts never become model inputs."""
from copy import deepcopy
from datetime import date
import json

import pytest

import current_seasonal_climate as current
import seasonal_assessment as seasonal


def payload():
    specs = {'T2M': ('C', 27), 'T2M_MIN_AVG': ('C', 22),
             'T2M_MAX_AVG': ('C', 32), 'RH2M': ('%', 85), 'PRECTOTCORR': ('mm/day', 2)}
    return {
        'header': {'fill_value': -999},
        'parameters': {key: {'units': unit} for key, (unit, _) in specs.items()},
        'properties': {'parameter': {
            key: {f'2026{month:02d}': value for month in range(1, 13)}
            for key, (_, value) in specs.items()}},
    }


def test_incomplete_year_and_future_months_are_never_full_year_or_forecasts():
    raw = payload()
    raw['properties']['parameter']['T2M']['202610'] = -999
    result = current.parse_current_year(raw, 7.2915, 125.6255, 11, date(2026, 11, 8))
    assert result['selected']['status'] == 'unavailable'
    assert result['selected']['rainfall_mm'] is None
    assert result['months'][11]['temperature_c'] is None
    assert result['latest_complete_month']['month'] == 9
    assert result['complete_month_count'] == 9
    assert result['annual_rainfall_mm'] is None
    assert result['used_for_model_ranking'] is False
    assert result['months'][1]['rainfall_mm'] == 56
    assert result['months'][0]['rainfall_mm'] == 62
    assert result['months'][9]['status'] == 'partial'


def test_current_year_unit_fill_and_zero_checks_do_not_substitute_normal_values():
    raw = payload()
    raw['parameters']['RH2M']['units'] = 'fraction'
    raw['properties']['parameter']['T2M']['202601'] = True
    raw['properties']['parameter']['PRECTOTCORR']['202602'] = 0
    result = current.parse_current_year(raw, 7.3, 125.62, 2, date(2026, 11, 8))
    assert result['selected']['rainfall_mm'] == 0
    assert result['selected']['humidity_pct'] is None
    assert result['selected']['moisture_status'] == 'dry'
    assert result['months'][0]['temperature_c'] is None
    assert result['status'] == 'unavailable'  # no complete three-variable month
    assert result['annual_rainfall_mm'] is None
    assert result['units']['rainfall'] == 'mm/month'


@pytest.mark.parametrize('month', [0, 13, True])
def test_invalid_month_is_rejected(month):
    with pytest.raises(ValueError):
        current.parse_current_year({}, 7.3, 125.62, month, date(2026, 11, 8))


def test_dated_pagasa_station_forecast_has_scope_and_expiry():
    result = current.published_outlook(7.2915, 125.6255, 11, date(2026, 11, 8))
    assert result['status'] == 'available'
    assert result['station'] == 'Tagum'
    assert result['probabilities_pct'] == {'below_normal': 38, 'near_normal': 30, 'above_normal': 32}
    assert result['issued_on'] == '2026-10-21'
    december = current.published_outlook(7.2915, 125.6255, 12, date(2026, 11, 8))
    assert december['status'] == 'available'
    assert december['probabilities_pct'] == {'below_normal': 67, 'near_normal': 20, 'above_normal': 13}
    assert 'not a forecast for the analyzed parcel' in result['scope']
    assert result['used_for_model_ranking'] is False
    for lat, lon, month, day in [
        (7.2915, 125.6255, 11, date(2026, 10, 20)),
        (7.2915, 125.6255, 11, date(2026, 12, 1)),
        (7.2915, 125.6255, 10, date(2026, 11, 8)),
        (7.2915, 125.6255, 11, date(2027, 11, 8)),
        (0, 0, 11, date(2026, 11, 8)),
    ]:
        assert current.published_outlook(lat, lon, month, day)['status'] == 'unavailable'


def test_invalid_probability_record_never_becomes_forecast(tmp_path, monkeypatch):
    records = json.loads(current.FORECAST_PATH.read_text())
    records['records'][0]['probabilities_pct']['below_normal'] = 100
    path = tmp_path / 'outlooks.json'
    path.write_text(json.dumps(records))
    monkeypatch.setattr(current, 'FORECAST_PATH', path)
    assert current.published_outlook(7.2915, 125.6255, 11, date(2026, 11, 8))['status'] == 'unavailable'


def test_adding_current_year_evidence_keeps_annual_inputs_and_all_model_fields():
    original = {'lat': 7.2915, 'lon': 125.6255, 'temperature_mean_5y_c': 26,
                'rainfall_annual_mean_5y_mm': 2600, 'humidity_current_pct': 80,
                'model_explanation': {'immutable': [1, 2]},
                'top_crop_recommendations': [{'crop': 'Rice', 'compatibility_pct': 40.2}]}
    record = deepcopy(original)
    baseline = seasonal.parse_baseline(payload(), 7.2915, 125.6255, 11, date(2026, 11, 8))
    seasonal.attach_seasonal_assessment(record, baseline, 11)
    assert {key: record[key] for key in original} == original
    saved = record['seasonal_assessment']['current_year_climate']
    assert saved['year'] == 2026 and saved['latest_complete_month']['month'] == 10
    baseline['current_year_climate']['year'] = 1000
    assert saved['year'] == 2026


def test_provider_requests_current_year_without_adding_a_second_network_call(monkeypatch):
    from unittest.mock import Mock
    get = Mock(return_value=Mock(json=payload))
    monkeypatch.setattr(seasonal.requests, 'get', get)
    seasonal._CACHE.clear()
    result = seasonal.fetch_baseline(7.2915, 125.6255, 11)
    assert get.call_count == 1
    assert get.call_args.kwargs['params']['end'] == date.today().year
    assert result['current_year_climate']['version'] == current.VERSION
