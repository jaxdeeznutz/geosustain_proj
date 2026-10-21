from copy import deepcopy

import pytest

from crop_requirements import REQUIREMENTS
from model_ranking import attach_model_ranking, ModelRankingUnavailable
from suitability import attach_assessment


def snapshot(probabilities, version='test-model'):
    return {'model_version': version, 'samples': [{'class_probabilities': probabilities}],
            'features': [], 'status': 'unavailable'}


def test_top_five_follow_raw_probability_not_reference_score_or_coverage():
    probabilities = {'banana': .10, 'rice': .30, 'durian': .05, 'rubber': .15,
                     'mango': .20, 'cacao': .12, 'coconut': .08}
    result = {'crop_assessments': [{'crop': 'Durian', 'compatibility_pct': 100,
                                   'assessed_count': 6}]}
    out = attach_model_ranking(result, [snapshot(probabilities)])
    top = out['top_crop_recommendations']
    assert [c['crop'] for c in top] == ['Rice', 'Mango', 'Rubber', 'Cacao', 'Banana']
    assert [c['compatibility_pct'] for c in top] == pytest.approx([30, 20, 15, 12, 10])
    assert [c['rank'] for c in top] == [1, 2, 3, 4, 5]
    assert out['crop_compatibility_pct'] == 30
    assert out['recommendation_basis'] == 'model_probability'
    assert out['model_explanation']['ranking'] == top


def test_polygon_means_every_class_across_every_sample_without_renormalizing():
    a = snapshot({'rice': .6, 'banana': .1, 'durian': .1, 'maize': .2})
    b = snapshot({'rice': .1, 'banana': .4, 'durian': .1, 'maize': .4})
    out = attach_model_ranking({}, [a, b], active_crops={'banana', 'rice'})
    assert [c['compatibility_pct'] for c in out['top_crop_recommendations']] == pytest.approx([35, 25])
    assert len(out['model_explanation']['samples']) == 2
    assert sum(c['compatibility_pct'] for c in out['top_crop_recommendations']) == pytest.approx(60)


@pytest.mark.parametrize('snapshots', [[], [None], [snapshot({'rice': 2})],
    [snapshot({'rice': float('nan')})], [snapshot({'rice': 1}), snapshot({'banana': 1})],
    [snapshot({'rice': 1}), snapshot({'rice': 1}, 'different')]])
def test_missing_or_invalid_model_output_never_falls_back_to_rule_ranking(snapshots):
    with pytest.raises(ModelRankingUnavailable):
        attach_model_ranking({'crop_compatibility_pct': 100}, snapshots)


@pytest.mark.parametrize('weather_available', [True, False])
def test_real_model_drives_pipeline_and_polygon_aggregation(monkeypatch, weather_available):
    import rainfallDatasets as env
    import environmental_pipeline as pipeline
    assert env.MODEL is not None
    for function, value in [('get_soil_ph', 6), ('get_elevation', 100), ('get_ndvi', .65), ('get_rainfall', 110)]:
        monkeypatch.setattr(env, function, lambda *args, value=value: (value, 'measured', 'test provider'))
    monkeypatch.setattr(env, 'get_live_weather', lambda *args: (80, 'Cloudy', 1, 30, 'measured' if weather_available else 'fallback_default'))
    if not weather_available:
        from unittest.mock import Mock
        response = Mock()
        response.json.return_value = {'current': {'relative_humidity_2m': 73}}
        monkeypatch.setattr(env.requests, 'get', Mock(return_value=response))
    monkeypatch.setattr(env, 'get_soil_nitrogen', lambda *args: (50, 'estimated_proxy', 'SoilGrids test fixture'))
    monkeypatch.setattr(pipeline, 'terrain_slope', lambda *args: 3)
    monkeypatch.setattr(pipeline, 'climate_normals', lambda *args: {
        'temperature': {'value': 27, 'unit': 'C', 'period': 'annual_mean', 'quality': 'modelled'},
        'rainfall': {'value': 2100, 'unit': 'mm/year', 'period': 'annual_mean_total', 'quality': 'modelled'}})
    point = pipeline.analyze_location(7.29, 125.62)
    sample = point['model_explanation']['samples'][0]
    from nutrient_contract import model_values
    assert model_values(sample['model_nutrient_inputs']) == {k: sample['inputs'][k] for k in ('N', 'P', 'K')}
    assert len(point['top_crop_recommendations']) == 5
    raw = point['model_explanation']['samples'][0]['class_probabilities']
    for crop in point['top_crop_recommendations']:
        assert crop['compatibility_pct'] == pytest.approx(raw[crop['crop'].lower()] * 100)
    parcel = pipeline.merge_results([point, deepcopy(point)])
    assert [c['compatibility_pct'] for c in parcel['top_crop_recommendations']] == [c['compatibility_pct'] for c in point['top_crop_recommendations']]
    assert len(parcel['model_explanation']['samples']) == 2
    assert set(c['crop'] for c in parcel['crop_assessments']) <= set(REQUIREMENTS)


def test_reference_comparisons_remain_available_but_do_not_determine_ranking():
    result = attach_assessment({}, {})
    out = attach_model_ranking(result, [snapshot({'rice': .2, 'banana': .8})])
    assert out['predicted_crop'] == 'Banana'
    assert out['best_crop']['reference_score'] is None
    assert out['best_crop']['factors']
