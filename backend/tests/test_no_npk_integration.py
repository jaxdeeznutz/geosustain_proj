"""Seven-input inference and real local explanations, with nutrient calls forbidden."""
from copy import deepcopy
import json
from types import SimpleNamespace

import joblib
import numpy as np
import pandas as pd
import pytest

from climate_contract import NO_NPK_PROTOTYPE_MODE, annual_model_ready, annual_prototype_policy
from model_artifacts import ENVIRONMENTAL_FEATURES, load_model_artifact, ModelArtifactError
from model_ranking import ModelRankingUnavailable
from nutrient_contract import attach_display_estimates
from training.activate_colab_no_npk import (CANDIDATE, MODEL_VERSION, prototype_metadata, validate_candidate)
from test_annual_climate_analysis import providers


@pytest.fixture
def no_npk_model(monkeypatch):
    import rainfallDatasets as env
    report = validate_candidate()
    metadata = prototype_metadata(report)
    model = joblib.load(CANDIDATE / 'random_forest.joblib')
    monkeypatch.setattr(env, 'MODEL', model)
    monkeypatch.setattr(env, 'MODEL_VERSION', MODEL_VERSION)
    monkeypatch.setattr(env, 'LOADED_MODEL', SimpleNamespace(metadata=metadata))
    return model, metadata


def test_seven_input_loader_requires_exact_metadata_policy_and_feature_sidecar(tmp_path):
    report = validate_candidate(); metadata = prototype_metadata(report)
    (tmp_path / 'crop_model.pkl').write_bytes((CANDIDATE / 'random_forest.joblib').read_bytes())
    joblib.dump(ENVIRONMENTAL_FEATURES, tmp_path / 'crop_model_features.pkl')
    path = tmp_path / 'crop_model_metadata.json'
    with pytest.raises(ModelArtifactError, match='metadata is required'): load_model_artifact(tmp_path)
    path.write_text(json.dumps(metadata))
    loaded = load_model_artifact(tmp_path, expected_version=MODEL_VERSION)
    assert loaded.health()['feature_contract']['count'] == 7
    assert loaded.health()['feature_contract']['npk_used'] is False
    assert annual_prototype_policy(loaded.metadata, loaded.model.classes_)
    assert not annual_model_ready(loaded.model, loaded.metadata)
    metadata['runtime_input_policy']['npk_used'] = True
    path.write_text(json.dumps(metadata))
    with pytest.raises(ModelArtifactError, match='version-bound'): load_model_artifact(tmp_path)
    metadata['runtime_input_policy']['npk_used'] = False
    path.write_text(json.dumps(metadata))
    joblib.dump(list(reversed(ENVIRONMENTAL_FEATURES)), tmp_path / 'crop_model_features.pkl')
    with pytest.raises(ModelArtifactError, match='Saved feature order'): load_model_artifact(tmp_path)


def test_no_npk_inference_never_calls_nutrient_providers_or_estimates_and_explains_all_seven(providers, no_npk_model, monkeypatch):
    import rainfallDatasets as env
    pipeline, _, seen = providers
    def forbidden(*_): raise AssertionError('NPK must not be retrieved, estimated, defaulted or adapted')
    monkeypatch.setattr(env, 'estimate_phosphorus_potassium', forbidden)
    monkeypatch.setattr(pipeline, 'legacy_inputs', forbidden)
    monkeypatch.setattr(pipeline, 'model_values', forbidden)
    result = pipeline.analyze_location(7.29, 125.62)
    assert 'nitrogen' not in seen and 'rainfall_recent' not in seen
    assert result['model_usage'] == NO_NPK_PROTOTYPE_MODE
    assert result['npk_assessment']['used_for_prediction'] is False
    assert result['model_npk_status'] == 'excluded'
    sample = result['model_explanation']['samples'][0]
    assert list(sample['inputs']) == ENVIRONMENTAL_FEATURES
    assert sample['npk_used'] is False and 'model_nutrient_inputs' not in sample
    assert sample['inputs']['rainfall'] == result['rainfall_annual_mean_5y_mm'] == 2100
    model, _ = no_npk_model
    scores = model.predict_proba(pd.DataFrame([sample['inputs']], columns=ENVIRONMENTAL_FEATURES))[0]
    np.testing.assert_allclose(scores, list(sample['class_probabilities'].values()), rtol=0, atol=1e-12)
    body = result['local_model_explanation']
    assert body['status'] == 'available' and body['feature_order'] == ENVIRONMENTAL_FEATURES
    assert np.asarray(body['contributions']).shape == (7, 7)
    np.testing.assert_allclose(np.asarray(body['base_values']) + np.sum(body['contributions'], axis=1),
                               body['model_scores'], rtol=0, atol=1e-9)
    assert all('N/P/K model inputs remain' not in text for text in body['limitations'])
    parcel = pipeline.merge_results([result, deepcopy(result)])
    assert parcel['model_usage'] == NO_NPK_PROTOTYPE_MODE
    assert parcel['local_model_explanation']['sample_count'] == 2
    attach_display_estimates(parcel)
    assert parcel['nutrient_display_basis'] == 'not_used_by_model'
    assert all(parcel[n] is None for n in ('nitrogen', 'phosphorus', 'potassium'))


def test_complete_new_polygon_and_history_preserve_no_npk_contract_and_verified_explanation(providers, no_npk_model, monkeypatch):
    import fastapi_app as api
    from model_artifacts import APPROVED_LABELS
    from seasonal_assessment import empty_baseline
    from database import enrich_history_rows
    monkeypatch.setattr(api, 'get_active_crop_keys', lambda: sorted(APPROVED_LABELS))
    monkeypatch.setattr(api, 'screen_land_cover', lambda *_: {'allow_crops': True, 'status': 'eligible', 'observed_fraction': 1})
    monkeypatch.setattr(api, 'reverse_geocode_place', lambda *_: 'Controlled no-NPK software fixture')
    monkeypatch.setattr(api, 'build_spatial_assessment', lambda *_: {'status': 'unavailable'})
    monkeypatch.setattr(api, 'fetch_multi_year_monthly_baseline', empty_baseline)
    polygon = [{'lat': 7.29 + dy, 'lng': 125.62 + dx} for dy, dx in [(0, 0), (0, .001), (.001, .001), (.001, 0)]]
    result, _ = api.build_analysis_result(body={'polygon': polygon, 'intended_planting_month': 11})
    assert result['analysis_mode'] == result['analysis_coverage']['analysis_mode'] == 'environmental_model_no_npk'
    assert result['model_nutrient_inputs']['status'] == 'not_used'
    assert result['legacy_model_nutrient_inputs']['samples'] == []
    assert 'NPK is excluded' in result['soil_model_warning']
    assert 'NPK excluded' in result['nutrient_basis']
    assert result['local_model_explanation']['status'] == 'available'
    assert result['model_npk_status'] == 'excluded'
    assert all('N' not in s['inputs'] for s in result['model_explanation']['samples'])
    saved = json.loads(json.dumps(result))
    restored = enrich_history_rows([{'session_id': 91, 'crop_compatibility_pct': round(saved['crop_compatibility_pct'], 2), 'result_snapshot': saved}])[0]
    assert restored['model_explanation'] == result['model_explanation']
    assert restored['local_model_explanation'] == result['local_model_explanation']
    assert restored['model_npk_status'] == 'excluded'


@pytest.mark.parametrize('factor', ['rainfall', 'temperature'])
def test_no_npk_model_still_rejects_missing_required_climate_instead_of_inventing_inputs(providers, no_npk_model, factor):
    pipeline, data, _ = providers
    data['climate'][factor]['value'] = None
    with pytest.raises(ModelRankingUnavailable, match=factor): pipeline.analyze_location(7.29, 125.62)
