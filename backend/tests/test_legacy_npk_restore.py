"""Offline restoration checks; no database writes or external provider requests."""
from copy import deepcopy

import pytest

from nutrient_contract import attach_display_estimates, legacy_inputs


def sample(n, p, k, *, fallback=False):
    return {'inputs': {'N': n, 'P': p, 'K': k},
            'model_nutrient_inputs': legacy_inputs(n, p, k,
                'fallback_default' if fallback else 'estimated_proxy',
                'Regional default' if fallback else 'SoilGrids fixture')}


def test_parcel_display_uses_all_recorded_inputs_without_replacing_cagro():
    historical = {'status': 'matched', 'observations': [{'nitrogen_pct': .09, 'potassium_ppm': 1337.2}]}
    record = {'cagro_soil': deepcopy(historical), 'model_explanation': {
        'samples': [sample(0, 40, 50), sample(80, 60, 70, fallback=True)]}}
    saved_samples = deepcopy(record['model_explanation'])
    result = attach_display_estimates(record)
    assert (result['nitrogen'], result['phosphorus'], result['potassium']) == (40, 50, 60)
    assert result['model_nutrient_aggregation']['sample_count'] == 2
    assert result['nutrient_display_basis'] == 'legacy_model_estimates'
    assert result['data_quality']['nitrogen']['quality'] == 'fallback_default'
    assert result['model_explanation'] == saved_samples
    assert result['cagro_soil'] == historical


def test_missing_sample_never_becomes_partial_mean_or_cagro_substitution():
    result = attach_display_estimates({'nitrogen': 80, 'cagro_soil': {
        'observations': [{'nitrogen_pct': .09}]}, 'model_explanation': {
        'samples': [sample(80, 47, 50), sample(None, 47, 50)]}})
    assert result['nitrogen'] is None
    assert result['phosphorus'] == 47
    assert result['data_quality']['nitrogen']['quality'] == 'unavailable'


def test_no_inference_does_not_create_npk():
    record = {'land_status': 'Water', 'model_explanation': None}
    assert attach_display_estimates(deepcopy(record)) == record


@pytest.mark.parametrize('polygon', [False, True])
@pytest.mark.parametrize('cover_state', ['eligible', 'unknown', 'unavailable'])
def test_unmatched_panabo_area_runs_real_forest_with_estimated_npk(monkeypatch, polygon, cover_state):
    import environmental_pipeline as pipeline
    import fastapi_app as api
    import rainfallDatasets as env

    assert env.MODEL is not None
    # All retrieval is explicit local test data; use the actual existing model.
    monkeypatch.setattr(pipeline, 'retrieve', lambda key, fn, lat, lon, ttl: fn(lat, lon))
    for name, value in [('get_soil_ph', 6), ('get_elevation', 100),
                        ('get_ndvi', .65), ('get_rainfall', 110)]:
        monkeypatch.setattr(env, name, lambda *args, value=value: (value, 'measured', 'Test fixture'))
    monkeypatch.setattr(env, 'get_live_weather', lambda *a: (80, 'Cloudy', 1, 30, 'measured'))
    monkeypatch.setattr(env, 'get_soil_nitrogen', lambda *a: (80, 'fallback_default', 'Regional default'))
    monkeypatch.setattr(pipeline, 'terrain_slope', lambda *a: 3)
    monkeypatch.setattr(pipeline, 'climate_normals', lambda *a: {
        'temperature': {'value': 27, 'unit': 'C', 'period': 'annual_mean', 'quality': 'modelled'},
        'rainfall': {'value': 2100, 'unit': 'mm/year', 'period': 'annual_mean_total', 'quality': 'modelled'}})
    monkeypatch.setattr(api, 'get_active_crop_keys', lambda: ['rice', 'banana'])
    monkeypatch.delenv('CAGRO_REFERENCE_ENABLED', raising=False)
    def screen(*args):
        if cover_state == 'unavailable':
            raise RuntimeError('Controlled offline provider failure')
        return {'allow_crops': cover_state == 'eligible', 'status': cover_state,
                'observed_fraction': 1 if cover_state == 'eligible' else .2}
    monkeypatch.setattr(api, 'screen_land_cover', screen)
    monkeypatch.setattr(api, 'reverse_geocode_place', lambda *a: 'Explicit fixture')
    body = {'lat': 7.29, 'lon': 125.62, 'place_name': 'Explicit fixture'}
    if polygon:
        body['polygon'] = [{'lat': 7.29 + dy, 'lng': 125.62 + dx}
                           for dy, dx in [(0, 0), (0, .001), (.001, .001), (.001, 0)]]
    result, _ = api.build_analysis_result(body=body)
    assert result['analysis_mode'] == 'legacy_model_estimates'
    assert result['analysis_coverage']['can_analyze']
    assert not result['analysis_coverage']['supported']
    assert result['analysis_coverage']['matches'] == []
    assert result['cagro_soil']['observations'] == []
    assert result['cagro_soil']['status'] == 'disabled'
    assert result['cagro_reference_enabled'] is False
    assert result['soil_nutrients_observed']['used_for_prediction'] is False
    assert result['predicted_crop'] in ('Rice', 'Banana')
    assert result['recommendation_basis'] == 'model_probability'
    screening = result['application_screening']
    assert screening['used_for_ranking'] is False
    for crop in screening['crops']:
        assert crop['factors']['humidity']['status'] == 'suitable'
        assert crop['factors']['ndvi']['status'] == 'suitable'
        assert set(crop['factors']) == {'humidity', 'ndvi'}
    assert result['model_explanation']['model_version'] == env.MODEL_VERSION
    p, k = env.estimate_phosphorus_potassium(.65, 6, 100)
    assert (result['nitrogen'], result['phosphorus'], result['potassium']) == (80, p, k)
    assert result['data_quality']['nitrogen']['quality'] == 'fallback_default'
    samples = result['model_explanation']['samples']
    assert len(samples) > 1 if polygon else len(samples) == 1
    assert all(s['inputs']['N'] == 80 for s in samples)
    assert result['model_nutrient_aggregation']['sample_count'] == len(samples)
    assert result['model_nutrient_inputs']['status'] == 'recorded'
    if cover_state != 'eligible':
        assert result['land_cover_notice']
        assert result['land_cover']['verification_status'] == 'unverified'


def test_old_preliminary_snapshot_is_not_upgraded_or_rewritten():
    from database import enrich_history_rows
    old = {'analysis_mode': 'preliminary_environmental', 'model_explanation': None,
           'top_crop_recommendations': [], 'crop_compatibility_pct': None}
    restored = enrich_history_rows([{'result_snapshot': deepcopy(old)}])[0]
    assert all(restored[key] == value for key, value in old.items())
    assert 'nutrient_display_basis' not in restored
    assert 'nitrogen' not in restored
