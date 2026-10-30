"""Monthly units/periods, failure states and ranking invariance; no live I/O."""
from copy import deepcopy
from unittest.mock import Mock

import pytest
import requests

import seasonal_assessment as seasonal


def payload():
    return {
        'header': {'fill_value': -999},
        'parameters': {'T2M': {'units': 'C'}, 'PRECTOTCORR': {'units': 'mm/day'}, 'RH2M': {'units': '%'}},
        'properties': {'parameter': {
            key: {f'{year}{month:02d}': (month if key == 'T2M' else 2 if key == 'PRECTOTCORR' else 80)
                  for year in seasonal.YEARS for month in range(1, 13)}
            for key in ('T2M', 'PRECTOTCORR', 'RH2M')
        }},
    }


@pytest.fixture(autouse=True)
def fresh_cache():
    seasonal._CACHE.clear()
    yield
    seasonal._CACHE.clear()


def test_month_filter_year_bounds_units_and_leap_month_total():
    raw = payload()
    raw['properties']['parameter']['T2M'].update({'200402': 90, '202502': 90, '200513': 90})
    baseline = seasonal.parse_baseline(raw, 7.3, 125.62, 2)
    assert baseline['status'] == 'available'
    assert baseline['mean_temperature_c'] == 2
    rainfall = baseline['metrics']['rainfall']
    assert rainfall['value'] == pytest.approx((15 * 28 + 5 * 29) * 2 / 20)
    assert rainfall['unit'] == 'mm/month' and rainfall['source_unit'] == 'mm/day'
    assert rainfall['valid_observations'] == 20
    assert rainfall['valid_years'] == seasonal.YEARS
    assert baseline['requested_location'] == {'latitude': 7.3, 'longitude': 125.62}


def test_partial_counts_and_missing_values_are_not_filled():
    raw = payload()
    raw['parameters']['RH2M']['units'] = 'fraction'
    for year, value in zip(seasonal.YEARS, [None, -999, float('nan'), float('inf'), True, -2]):
        raw['properties']['parameter']['PRECTOTCORR'][f'{year}01'] = value
    baseline = seasonal.parse_baseline(raw, 7.3, 125.62, 1)
    assert baseline['status'] == 'partial'
    assert baseline['metrics']['rainfall']['valid_observations'] == 14
    assert baseline['mean_monthly_rainfall_mm'] == 62
    assert baseline['metrics']['humidity']['value'] is None
    assert baseline['metrics']['humidity']['unavailable_reason'] == 'Missing or incompatible provider unit'
    empty = seasonal.parse_baseline({}, 7.3, 125.62, 1)
    assert empty['status'] == 'unavailable'
    assert all(m['value'] is None for m in empty['metrics'].values())


def test_provider_timeout_cached_failure_ttl_recovery_and_copy(monkeypatch):
    clock = [100]
    monkeypatch.setattr(seasonal, 'monotonic', lambda: clock[0])
    get = Mock(side_effect=[requests.Timeout(), Mock(json=payload)])
    monkeypatch.setattr(seasonal.requests, 'get', get)
    first = seasonal.fetch_baseline(7.3, 125.62, 1)
    assert first['status'] == 'unavailable'
    first['limitations'].clear()
    second = seasonal.fetch_baseline(7.3, 125.62, 1)
    assert second['limitations'] and second['cache_hit'] is True
    assert get.call_count == 1
    clock[0] += 301
    assert seasonal.fetch_baseline(7.3, 125.62, 1)['status'] == 'available'
    assert get.call_count == 2 and get.call_args.kwargs['timeout'] == (3, 8)


def test_cache_is_bounded_and_month_and_location_specific(monkeypatch):
    get = Mock(return_value=Mock(json=payload))
    monkeypatch.setattr(seasonal.requests, 'get', get)
    monkeypatch.setattr(seasonal, 'CACHE_LIMIT', 2)
    seasonal.fetch_baseline(7.3, 125.62, 1)
    seasonal.fetch_baseline(7.3, 125.62, 2)
    seasonal.fetch_baseline(7.31, 125.62, 2)
    assert len(seasonal._CACHE) == 2 and get.call_count == 3
    assert seasonal.fetch_baseline(7.3, 125.62, 2)['cache_hit']


@pytest.mark.parametrize('month', [0, 13, True])
def test_invalid_month_does_not_call_provider(monkeypatch, month):
    get = Mock()
    monkeypatch.setattr(seasonal.requests, 'get', get)
    with pytest.raises(ValueError):
        seasonal.fetch_baseline(7.3, 125.62, month)
    get.assert_not_called()


def test_seasonal_snapshot_is_separate_with_no_unsourced_calendar_claim():
    original = {
        'top_crop_recommendations': [{'crop': 'Rice', 'compatibility_pct': 41.123}],
        'crop_compatibility_pct': 41.123, 'model_explanation': {'probabilities': [0.41123]},
        'crop_assessments': [{'factors': [{'factor': 'rainfall', 'score': 100}]}],
        'temperature_mean_5y_c': 27, 'rainfall_30d_mm': 110,
    }
    snapshots = []
    for month in (1, 6):
        result = deepcopy(original)
        baseline = seasonal.parse_baseline(payload(), 7.3, 125.62, month)
        seasonal.attach_seasonal_assessment(result, baseline, month)
        assert {key: result[key] for key in original} == original
        snapshot = result['seasonal_assessment']
        assert snapshot['calendar']['status'] == 'unavailable'
        assert snapshot['ranking_effect'] == 'none'
        assert snapshot['year_interpretation'].endswith('forecast selected')
        assert 'season_adjusted_score' not in result and 'season_status' not in result
        baseline['metrics']['temperature']['value'] = -500
        snapshots.append(snapshot)
    assert snapshots[0]['monthly_climate']['mean_temperature_c'] == 1
    assert snapshots[1]['monthly_climate']['mean_temperature_c'] == 6


@pytest.mark.parametrize('modern', [True, False])
def test_real_build_path_always_attaches_month_without_changing_rank(monkeypatch, modern):
    import fastapi_app as api
    raw = {'is_crop_recommended': True, 'predicted_crop': 'Rice', 'crop': 'Rice',
           'crop_compatibility_pct': 41.123, 'temperature_c': 27,
           'top_crop_recommendations': [{'crop': 'Rice', 'compatibility_pct': 41.123}]}
    if modern:
        raw['scoring_version'] = 'test-modern'
    monkeypatch.setattr(api, 'get_active_crop_keys', lambda: None)
    monkeypatch.setattr(api, 'analyze_location', lambda *_: deepcopy(raw))
    monkeypatch.setattr(api, 'fetch_multi_year_monthly_baseline',
                        lambda lat, lon, month: seasonal.parse_baseline(payload(), lat, lon, month))
    for month in (2, 8):
        result, _ = api.build_analysis_result(body={'lat': 7.3, 'lon': 125.62, 'place_name': 'Fixture', 'intended_planting_month': month})
        assert result['seasonal_assessment']['selected_month'] == month
        assert result['historical_climate_baseline']['mean_temperature_c'] == month
        assert result['temperature_c'] == 27
        assert result['top_crop_recommendations'] == raw['top_crop_recommendations']
        assert result['crop_compatibility_pct'] == 41.123
