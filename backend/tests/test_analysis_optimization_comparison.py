"""Compare shared observations/provider calls with an immutable older pipeline.
Annual policy intentionally suppresses unsupported legacy model rankings.
No live services or production records are used.
"""
from collections import Counter
import subprocess
import types
from pathlib import Path
import hashlib
import joblib

import pytest
import environmental_pipeline as current
import provider_cache
import rainfallDatasets as env


@pytest.fixture
def comparison(monkeypatch):
    # Exercise the default guarded path, independently of the installed experiment.
    monkeypatch.setattr(env, 'LOADED_MODEL', types.SimpleNamespace(metadata={}))
    # The immutable older pipeline expects ten inputs. Keep its own archived
    # estimator independent of whichever seven-input model is active today.
    path = Path(__file__).resolve().parents[2] / 'research/seven-crop-candidates/20261103-seven-crops/crop_model.pkl'
    monkeypatch.setattr(env, 'MODEL', joblib.load(path))
    monkeypatch.setattr(env, 'MODEL_VERSION', hashlib.sha256(path.read_bytes()).hexdigest())
    # Last pipeline revision before provider reuse/caching (immutable baseline).
    source = subprocess.check_output(['git', 'show', '1f2155f:backend/environmental_pipeline.py']).decode('utf-8')
    previous = types.ModuleType('previous_pipeline')
    exec(compile(source, 'previous_pipeline.py', 'exec'), previous.__dict__)
    provider_cache._values.clear()
    clock = [0.0]
    monkeypatch.setattr(provider_cache, 'monotonic', lambda: clock[0])
    values = {'soil_ph': 6.3, 'elevation': 80, 'ndvi': .65, 'rainfall': 110,
              'nitrogen': 50, 'humidity': 80, 'temperature': 27, 'annual_rainfall': 2100, 'slope': 3}
    calls = Counter()

    def scalar(name):
        def fetch(*_):
            calls[name] += 1
            return (values[name], 'measured', 'controlled provider')
        return fetch

    for name in ['soil_ph', 'elevation', 'ndvi', 'rainfall', 'nitrogen']:
        monkeypatch.setattr(env, 'get_' + ('soil_nitrogen' if name == 'nitrogen' else name), scalar(name))

    def weather(*_):
        calls['weather'] += 1
        return (values['humidity'], 'Cloudy', 1, 30, 'measured')

    def climate(*_):
        calls['climate'] += 1
        return {'temperature': {'value': values['temperature'], 'unit': 'C', 'period': 'annual_mean', 'quality': 'modelled'},
                'rainfall': {'value': values['annual_rainfall'], 'unit': 'mm/year', 'period': 'annual_mean_total', 'quality': 'modelled'}}

    def slope(*_):
        calls['slope'] += 1
        return values['slope']

    monkeypatch.setattr(env, 'get_live_weather', weather)
    for module in [previous, current]:
        monkeypatch.setattr(module, 'climate_normals', climate)
        monkeypatch.setattr(module, 'terrain_slope', slope)
    assert env.MODEL is not None
    yield previous, values, calls, clock
    provider_cache._values.clear()


def assert_equivalent(old, new):
    # Shared physical observations must match. Recent rain/model rankings are
    # deliberately excluded by the new annual-only contract.
    def observations(result):
        return {k: {field: value for field, value in m.items() if field != 'spatial_method'}
                for k, m in result['environmental_measurements'].items() if k != 'rainfall_recent'}
    assert observations(old) == observations(new)
    assert new['model_explanation'] is None
    assert new['reference_screening_reason'] == 'annual_model_pending'
    assert new['top_crop_recommendations'] == []
    assert new['rainfall_annual_mean_5y_mm'] == old['environmental_measurements']['rainfall']['value']
    if old.get('reference_screening_reason') == 'annual_model_pending':
        assert old['crop_assessments'] == new['crop_assessments']


@pytest.mark.parametrize('changes', [{}, {'soil_ph': 5.1, 'ndvi': .35, 'rainfall': 45, 'elevation': 220},
                                     {'soil_ph': 7.2, 'ndvi': .8, 'rainfall': 250, 'humidity': 92}])
def test_annual_observations_reuse_providers_without_unsupported_rankings(comparison, changes):
    previous, values, calls, _ = comparison
    values.update(changes)
    old = previous.analyze_location(7.29, 125.62)
    assert sum(calls.values()) == 11
    calls.clear()
    new = current.analyze_location(7.29, 125.62)
    assert sum(calls.values()) == 6
    assert calls['rainfall'] == calls['nitrogen'] == 0
    assert_equivalent(old, new)
    calls.clear()
    warm = current.analyze_location(7.29, 125.62)
    assert sum(calls.values()) == 0
    assert_equivalent(new, warm)


def test_nine_sample_parcel_preserves_annual_observations_with_fewer_calls(comparison):
    previous, values, calls, _ = comparison
    points = [(7.29 + i * .0001, 125.62) for i in range(9)]
    old = previous.merge_results([previous.analyze_location(*point) for point in points])
    assert sum(calls.values()) == 99
    calls.clear()
    new = current.merge_results([current.analyze_location(*point) for point in points])
    assert sum(calls.values()) == 54
    assert_equivalent(old, new)


def test_cache_retains_weather_until_ttl_then_matches_fresh_analysis(comparison):
    previous, values, calls, clock = comparison
    initial = current.analyze_location(7.29, 125.62)
    values['humidity'] = 35
    cached = current.analyze_location(7.29, 125.62)
    assert_equivalent(initial, cached)
    fresh = previous.analyze_location(7.29, 125.62)
    assert fresh['model_explanation']['samples'][0]['inputs']['humidity'] == 35
    assert cached['humidity_current_pct'] == 80
    clock[0] = 301
    refreshed = current.analyze_location(7.29, 125.62)
    assert_equivalent(fresh, refreshed)
