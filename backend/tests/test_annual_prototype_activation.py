"""Explicit experimental activation never masquerades as annual validation."""
from copy import deepcopy
from types import SimpleNamespace

import pytest

from climate_contract import (PROTOTYPE_MODE, PROTOTYPE_NOTICE, VERSION,
                              annual_model_ready, annual_prototype_policy)
from model_artifacts import load_model_artifact, ModelArtifactError
from test_annual_climate_analysis import providers, seven_class_fixture
from test_model_artifacts import release, change_metadata


def fixture_policy(version):
    return {'mode': PROTOTYPE_MODE, 'model_version': version,
            'climate_contract_version': VERSION, 'annual_input_compatibility': 'unverified',
            'use_raw_annual_values': True, 'validation_claim': 'experimental_only',
            'legacy_nutrients': 'estimated_proxies_not_soil_tests'}


def test_prototype_requires_explicit_version_bound_policy_and_is_not_validated(release):
    directory, _, _, metadata = release
    def select_prototype(m):
        m['training']['status'] = 'experimental_prototype'
        m['runtime_input_policy'] = fixture_policy(m['model_version'])
    change_metadata(directory, select_prototype)
    loaded = load_model_artifact(directory)
    assert annual_prototype_policy(loaded.metadata, loaded.model.classes_)
    assert not annual_model_ready(loaded.model, loaded.metadata)
    assert loaded.health()['metadata_status'] == 'experimental_prototype'
    assert loaded.health()['scope_matches_catalog']
    assert loaded.health()['warnings']
    # Strict scientific/recorded release admission still rejects this experiment.
    with pytest.raises(ModelArtifactError, match='Recorded training metadata'):
        load_model_artifact(directory, require_metadata=True)
    change_metadata(directory, lambda m: m['runtime_input_policy'].update(model_version='wrong'))
    with pytest.raises(ModelArtifactError, match='version-bound'):
        load_model_artifact(directory)


def test_prototype_runs_raw_annual_inputs_and_preserves_warnings_in_parcel(providers, monkeypatch):
    import rainfallDatasets as env
    pipeline, _, seen = providers
    forest, version, metadata = seven_class_fixture()
    metadata.update(model_version=version, runtime_input_policy=fixture_policy(version))
    metadata['training']['status'] = 'experimental_prototype'
    monkeypatch.setattr(env, 'MODEL', forest)
    monkeypatch.setattr(env, 'MODEL_VERSION', version)
    monkeypatch.setattr(env, 'LOADED_MODEL', SimpleNamespace(metadata=metadata))
    sample = pipeline.analyze_location(7.29, 125.62)
    assert 'rainfall_recent' not in seen
    assert sample['model_usage'] == PROTOTYPE_MODE
    assert sample['model_ranking_status'] == 'experimental'
    assert sample['npk_assessment']['status'] == 'not_assessed'
    assert sample['local_model_explanation']['status'] == 'available'
    recorded = sample['model_explanation']['samples'][0]
    assert recorded['inputs']['rainfall'] == 2100  # no division/relabelled recent rain
    assert recorded['model_climate_inputs']['rainfall']['unit'] == 'mm/year'
    assert recorded['runtime_input_policy']['validation_claim'] == 'experimental_only'
    merged = pipeline.merge_results([sample, deepcopy(sample)])
    assert merged['model_ranking_status'] == 'experimental'
    assert merged['prototype_model_notice'] == PROTOTYPE_NOTICE
    assert PROTOTYPE_NOTICE in merged['data_quality_warnings']
    assert merged['local_model_explanation']['status'] == 'available'


def test_unsupported_metadata_and_missing_humidity_still_do_not_infer(providers, monkeypatch):
    import rainfallDatasets as env
    pipeline, data, _ = providers
    forest, version, metadata = seven_class_fixture()
    metadata.update(model_version=version, runtime_input_policy=fixture_policy(version))
    metadata['training']['status'] = 'experimental_prototype'
    monkeypatch.setattr(env, 'MODEL', forest)
    monkeypatch.setattr(env, 'MODEL_VERSION', version)
    monkeypatch.setattr(env, 'LOADED_MODEL', SimpleNamespace(metadata=metadata))
    monkeypatch.setattr(pipeline, 'current_humidity', lambda *_: {
        'value': None, 'unit': '%', 'period': 'current', 'quality': 'unavailable', 'source': 'Test'})
    from model_ranking import ModelRankingUnavailable
    with pytest.raises(ModelRankingUnavailable, match='humidity'):
        pipeline.analyze_location(7.29, 125.62)


def test_installed_seven_crop_prototype_replays_annual_predictions_and_local_attribution(providers):
    import rainfallDatasets as env
    pipeline, _, _ = providers
    assert annual_prototype_policy(env.LOADED_MODEL.metadata, env.MODEL.classes_)
    assert set(env.MODEL.classes_) == {'banana', 'coconut', 'rice', 'durian', 'mango', 'rubber', 'cacao'}
    result = pipeline.analyze_location(7.29, 125.62)
    sample = result['model_explanation']['samples'][0]
    import pandas as pd
    import numpy as np
    frame = pd.DataFrame([sample['inputs']], columns=list(env.MODEL.feature_names_in_))
    np.testing.assert_allclose(env.MODEL.predict_proba(frame)[0],
        [sample['class_probabilities'][str(label)] for label in env.MODEL.classes_], rtol=0, atol=1e-12)
    assert result['local_model_explanation']['status'] == 'available'
    assert result['model_ranking_status'] == 'experimental'
    assert sample['inputs']['rainfall'] == result['rainfall_annual_mean_5y_mm'] == 2100
    parcel = pipeline.merge_results([deepcopy(result) for _ in range(9)])
    assert parcel['local_model_explanation']['status'] == 'available'
    assert parcel['local_model_explanation']['sample_count'] == 9
    assert parcel['model_validation_status'] == 'unvalidated'


def test_complete_polygon_result_keeps_experimental_policy_and_saved_explanation(providers, monkeypatch):
    import fastapi_app as api
    from model_artifacts import APPROVED_LABELS
    from seasonal_assessment import empty_baseline
    monkeypatch.setattr(api, 'get_active_crop_keys', lambda: sorted(APPROVED_LABELS))
    monkeypatch.setattr(api, 'screen_land_cover', lambda *_: {
        'allow_crops': True, 'status': 'eligible', 'observed_fraction': 1})
    monkeypatch.setattr(api, 'reverse_geocode_place', lambda *_: 'Controlled software fixture')
    monkeypatch.setattr(api, 'build_spatial_assessment', lambda *_: {'status': 'unavailable'})
    monkeypatch.setattr(api, 'fetch_multi_year_monthly_baseline', empty_baseline)
    polygon = [{'lat': 7.29 + dy, 'lng': 125.62 + dx}
               for dy, dx in [(0, 0), (0, .001), (.001, .001), (.001, 0)]]
    result, source = api.build_analysis_result(body={'polygon': polygon, 'intended_planting_month': 11})
    assert source == 'selected-polygon'
    import rainfallDatasets as env
    assert result['model_usage'] == env.LOADED_MODEL.metadata['runtime_input_policy']['mode']
    assert result['model_ranking_status'] == 'experimental'
    assert result['local_model_explanation']['status'] == 'available'
    assert set(result['local_model_explanation']['class_order']) == APPROVED_LABELS
    if 'N' in env.MODEL.feature_names_in_:
        assert result['model_nutrient_inputs']['scientific_compatibility'] == 'unverified'
    else:
        assert result['model_nutrient_inputs']['status'] == 'not_used'
        assert result['npk_assessment']['used_for_prediction'] is False
    assert result['npk_assessment']['status'] == 'not_assessed'
    assert result['rainfall_annual_mean_5y_mm'] == 2100
    assert result['rainfall_mm'] is None
    assert PROTOTYPE_NOTICE in result['data_quality_warnings']
