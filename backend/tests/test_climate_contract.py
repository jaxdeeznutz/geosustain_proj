from copy import deepcopy

import pytest

from climate_contract import attach_climate_fields, model_climate_inputs, same_period
from model_ranking import ModelRankingUnavailable
from suitability import assess
from training.climate_training_contract import validate_training_periods


def observations():
    return {
        'rainfall_recent': {'value': 100, 'unit': 'mm', 'period': 'rolling_30_days', 'quality': 'modelled'},
        'rainfall': {'value': 2100, 'unit': 'mm/year', 'period': 'annual_mean_total', 'quality': 'modelled'},
        'temperature': {'value': 27, 'unit': 'C', 'period': 'annual_mean', 'quality': 'modelled'},
        'humidity_current': {'value': 80, 'unit': '%', 'period': 'current', 'quality': 'modelled'},
    }


@pytest.mark.parametrize('key,field,value', [
    ('rainfall_recent', 'period', 'annual_mean_total'),
    ('rainfall_recent', 'unit', 'mm/year'),
    ('temperature', 'period', 'current'),
    ('humidity_current', 'period', 'annual_mean'),
    ('rainfall_recent', 'value', None),
    ('temperature', 'quality', 'fallback_default'),
])
def test_inference_rejects_wrong_period_unit_or_missing_data(key, field, value):
    data = observations()
    data[key][field] = value
    with pytest.raises(ModelRankingUnavailable):
        model_climate_inputs(data)


def test_inference_and_api_keep_recent_and_annual_separate():
    data = observations()
    values, records = model_climate_inputs(data)
    assert values == {'rainfall': 100, 'temperature': 27, 'humidity': 80}
    assert records['humidity']['period'] == 'current'
    result = attach_climate_fields({}, data)
    assert result['rainfall_30d_mm'] == result['rainfall_mm'] == 100
    assert result['rainfall_annual_mean_5y_mm'] == result['annual_rainfall_mm'] == 2100
    assert result['temperature_mean_5y_c'] == result['temperature_c'] == 27
    assert result['climate_training_compatibility'] == 'unverified'
    assert result['climate_field_metadata']['humidity_current_pct']['screening_factor'] is None


@pytest.mark.parametrize('factor,replacement', [('rainfall', 'rainfall_recent'), ('temperature', 'humidity_current'), ('humidity', 'humidity_current')])
def test_reference_screening_excludes_wrong_period(factor, replacement):
    data = observations()
    data[factor] = deepcopy(data[replacement])
    for crop in assess(data):
        item = next(f for f in crop['factors'] if f['factor'] == factor)
        assert item['score'] is None


@pytest.mark.parametrize('field,value', [('period', 'current'), ('unit', 'mm'), ('start', '2020-01-01')])
def test_polygon_does_not_average_mismatched_periods_or_windows(field, value):
    first = observations()['temperature']
    other = {**first, field: value}
    assert same_period([first, first])
    assert not same_period([first, other])


def test_current_training_cannot_overwrite_model_with_unverified_periods():
    with pytest.raises(ValueError, match='unresolved'):
        validate_training_periods()
    with pytest.raises(ValueError, match='unresolved'):
        validate_training_periods({'test-only': {'rainfall': 'annual_mean_total', 'temperature': 'annual_mean', 'humidity': 'current'}})


def test_polygon_humidity_alias_is_mean_not_first_sample(monkeypatch):
    import environmental_pipeline as pipeline
    monkeypatch.setattr(pipeline, 'attach_model_ranking', lambda result, *_: result)
    a, b = observations(), observations()
    b['humidity_current']['value'] = 60
    result = pipeline.merge_results([{'environmental_measurements': a}, {'environmental_measurements': b}])
    assert result['humidity_current_pct'] == result['live_humidity'] == 70
    b['temperature']['period'] = 'current'
    result = pipeline.merge_results([{'environmental_measurements': a}, {'environmental_measurements': b}])
    assert result['temperature_mean_5y_c'] is None


def test_legacy_api_retains_historical_temperature_without_cross_period_blend(monkeypatch):
    import fastapi_app as api
    monkeypatch.setattr(api, 'get_active_crop_keys', lambda: None)
    monkeypatch.setattr(api, 'analyze_location', lambda *_: {'temperature_c': 27})
    monkeypatch.setattr(api, 'apply_local_seasonality', lambda result, *_: result)
    monkeypatch.setattr(api, 'fetch_multi_year_monthly_baseline', lambda *_: {'mean_temperature_c': 25})
    monkeypatch.setattr(api, 'build_analysis_summary', lambda result: result)
    monkeypatch.setattr(api, 'finalize_explanation', lambda result: result)
    monkeypatch.setattr(api, 'merge_area_results', lambda rows: rows[0])
    result, _ = api.build_analysis_result(body={'polygon': __import__('test_cagro_soil').square(7.39242,125.62293), 'place_name': 'Test fixture'})
    assert result['temperature_c'] == 27
    assert result['historical_climate_baseline']['mean_temperature_c'] == 25
    assert 'temperature_c_combined' not in result
