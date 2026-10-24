"""Real deployed forest, fixed inputs; no network, database or synthetic weights."""
from copy import deepcopy
import json
from unittest.mock import Mock

import pytest
import rainfallDatasets as engine
import fastapi_app as api
import database as db
from model_explainability import finalize_explanation, content_hash
from test_mobile_workflow import connection


def prediction(rain=105, temp=27.5):
    explanation = {}
    raw, crops = engine.get_ai_prediction(80, 47, 50, temp, 80, 6, rain, .6, 25, 2,
                                          inference_context=explanation)
    return {'lat': 7.3, 'lon': 125.6, 'is_crop_recommended': True,
            'predicted_crop': crops[0]['crop'], 'raw_predicted_crop': str(raw),
            'crop_compatibility_pct': crops[0]['compatibility_pct'],
            'top_crop_recommendations': crops, 'model_explanation': explanation}


def test_native_importance_and_exact_inputs_are_preserved():
    result = finalize_explanation(prediction())
    explanation = result['model_explanation']
    assert explanation['scope'] == 'global'
    assert explanation['supports_direction'] is False
    assert explanation['supports_crop_specific'] is False
    assert [f['importance'] for f in explanation['features']] == list(engine.MODEL.feature_importances_)
    assert sum(f['importance'] for f in explanation['features']) == pytest.approx(1)
    sample = explanation['samples'][0]
    assert sample['inputs']['rainfall'] == 105
    assert sample['model_version'] == engine.MODEL_VERSION
    assert len(engine.MODEL_VERSION) == 64
    assert sample['raw_prediction'] == result['raw_predicted_crop']
    assert sum(sample['class_probabilities'].values()) == pytest.approx(1)
    assert explanation['input_snapshot_hash'] == content_hash(explanation['samples'])
    assert json.loads(json.dumps(result))['model_explanation'] == explanation


def test_every_crop_has_its_own_scoring_conditions():
    result = prediction(rain=12, temp=35)
    for crop in result['top_crop_recommendations']:
        comparison = crop['condition_comparison']
        assert comparison['crop'] == crop['crop']
        assert len(comparison['factors']) == 7
        rain = next(f for f in comparison['factors'] if f['feature'] == 'rain')
        assert rain['value'] == pytest.approx(.65 * 105 + .35 * 12)
        assert comparison['rainfall_context']['recent_30d_mm'] == 12
        assert comparison['sample_id'] == result['model_explanation']['samples'][0]['sample_id']
        assert 'not model' in comparison['method']
    assert len({c['condition_comparison']['rules_version'] for c in result['top_crop_recommendations']}) > 1


def test_polygon_retains_each_inference_not_average_inputs():
    first, second = prediction(rain=12), prediction(rain=260)
    originals = deepcopy([first, second])
    merged = api.merge_area_results([first, second])
    assert [s['inputs']['rainfall'] for s in merged['model_explanation']['samples']] == [12, 260]
    assert [first, second] == originals
    crop = merged['top_crop_recommendations'][0]
    assert crop['condition_comparison']['scope'] == 'ranking_sample'
    assert crop['condition_comparison']['sample_id'] in {s['sample_id'] for s in merged['model_explanation']['samples']}


def test_season_reordering_does_not_reuse_old_winner_explanation():
    result = prediction()
    result['top_crop_recommendations'] = [
        {'crop': 'Rice', 'compatibility_pct': 80, 'condition_comparison': {'crop': 'Rice', 'summary': 'Rice conditions'}},
        {'crop': 'Corn (White/Yellow)', 'compatibility_pct': 79, 'condition_comparison': {'crop': 'Corn (White/Yellow)', 'summary': 'Corn conditions'}},
    ]
    updated = finalize_explanation(api.apply_local_seasonality(result, 1))
    assert updated['predicted_crop'] == 'Corn (White/Yellow)'
    assert updated['xai_explanation']['plain_summary'] == 'Corn conditions'
    assert updated['model_explanation']['selected_output'] == updated['predicted_crop']
    assert updated['model_explanation']['ranking'] == updated['top_crop_recommendations']


def test_history_restores_snapshot_without_running_current_model(monkeypatch):
    result = finalize_explanation(prediction())
    frozen = deepcopy(result)
    monkeypatch.setattr(engine.MODEL, 'predict', Mock(side_effect=AssertionError('historical inference')))
    row = db.enrich_history_rows([{'session_id': 81, 'result_snapshot': result}])[0]
    assert row['model_explanation'] == frozen['model_explanation']
    assert result == frozen
    old = db.enrich_history_rows([{'session_id': 1, 'predicted_crop': 'Cacao'}])[0]
    assert 'model_explanation' not in old


def test_persistence_and_history_api_keep_explanation(client, monkeypatch):
    result = finalize_explanation(prediction())
    conn, cursor = connection(monkeypatch, [{'id': 81}])
    assert db.save_analysis_session(10, result, 'selected-polygon') == 81
    stored = next(p.adapted for p in cursor.queries[0][1] if hasattr(p, 'adapted') and isinstance(p.adapted, dict))
    assert stored['model_explanation'] == result['model_explanation']
    row = db.enrich_history_rows([{'session_id': 81, 'result_snapshot': stored}])[0]
    monkeypatch.setattr(api, 'get_user_history', lambda *a, **k: [row])
    response = client.get('/api/mobile/history')
    assert response.status_code == 200
    assert 'random_forest_mean_decrease_in_impurity' in response.text
    conn.commit.assert_called_once()


def test_invalid_importance_is_honest_without_failing_prediction(monkeypatch):
    from model_explainability import forest_snapshot
    model = Mock(feature_names_in_=['N'], feature_importances_=[float('nan')])
    explanation = forest_snapshot(model, 'version', {'N': 80}, 'rice', {'rice': .5})
    assert explanation['status'] == 'unavailable'
    assert explanation['features'] == []
    assert explanation['samples'][0]['inputs'] == {'N': 80}


def test_mixed_model_versions_do_not_present_a_shared_chart():
    first, second = prediction(), prediction()
    second['model_explanation']['model_version'] = 'different'
    merged = api.merge_area_results([first, second])
    assert merged['model_explanation']['status'] == 'unavailable'
    assert not merged['model_explanation']['features']
