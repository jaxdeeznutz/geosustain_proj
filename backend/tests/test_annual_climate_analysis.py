"""Annual-only new analyses; legacy recent-rain training is never relabelled."""
from copy import deepcopy
import hashlib
import io
from types import SimpleNamespace
from unittest.mock import Mock

import joblib
import numpy as np
import pandas as pd
import pytest
from sklearn.ensemble import RandomForestClassifier

from climate_contract import annual_model_ready
from crop_requirements import REQUIREMENTS
from model_artifacts import FEATURES


@pytest.fixture
def providers(monkeypatch):
    import environmental_pipeline as pipeline
    def observation(value, unit, period):
        return {'value': value, 'unit': unit, 'period': period, 'quality': 'modelled',
                'source': 'Software-only test observation', 'start': '2021-01-01', 'end_exclusive': '2026-01-01'}
    data = {'soil_ph': (6, 'measured', 'Test'), 'elevation': (30, 'measured', 'Test'),
            'ndvi': (.7, 'measured', 'Test'), 'slope': 3,
            'weather': (80, '', 0, 0, 'measured'), 'nitrogen': (50, 'estimated_proxy', 'Test'),
            'climate': {'temperature': observation(27, 'C', 'annual_mean'),
                        'rainfall': observation(2100, 'mm/year', 'annual_mean_total')}}
    seen = []
    def retrieve(key, *_):
        seen.append(key)
        return deepcopy(data[key])
    monkeypatch.setattr(pipeline, 'retrieve', retrieve)
    return pipeline, data, seen


def test_legacy_forest_returns_annual_checks_without_recent_rain_or_nutrient_calls(providers, monkeypatch):
    import rainfallDatasets as env
    pipeline, _, seen = providers
    model = Mock(classes_=np.array(['rice', 'banana', 'unapproved_crop']))
    model.predict_proba.side_effect = AssertionError('Annual totals must not enter the legacy forest')
    monkeypatch.setattr(env, 'MODEL', model)
    result = pipeline.analyze_location(7.29, 125.62)
    assert 'rainfall_recent' not in seen and 'nitrogen' not in seen
    assert result['rainfall_annual_mean_5y_mm'] == result['annual_rainfall_mm'] == 2100
    assert result['rainfall_mm'] is None and 'rainfall_30d_mm' not in result
    assert result['temperature_mean_5y_c'] == 27
    assert result['reference_screening_reason'] == 'annual_model_pending'
    assert result['model_ranking_status'] == 'unavailable'
    assert result['assessment_scope'] == 'online_environmental_reference_screening'
    assert result['npk_assessment']['status'] == 'not_assessed'
    assert result['npk_assessment']['pending_source'] == 'PAGRO'
    assert result['crop_compatibility_pct'] is None and result['top_crop_recommendations'] == []
    assert {row['crop'] for row in result['crop_assessments']} == set(REQUIREMENTS)
    assert all(row['rank'] is None for row in result['crop_assessments'])
    model.predict_proba.assert_not_called()
    merged = pipeline.merge_results([result, deepcopy(result)])
    assert merged['rainfall_annual_mean_5y_mm'] == 2100
    assert merged['reference_screening_reason'] == 'annual_model_pending'
    assert merged['crop_compatibility_pct'] is None


def seven_class_fixture():
    # All values are controlled software fixtures, not farm observations.
    labels = sorted(name.lower() for name in REQUIREMENTS) * 8
    values = np.arange(len(labels) * len(FEATURES), dtype=float).reshape(-1, len(FEATURES))
    frame = pd.DataFrame(values, columns=FEATURES)
    forest = RandomForestClassifier(n_estimators=8, random_state=42, n_jobs=1).fit(frame, labels)
    payload = io.BytesIO()
    joblib.dump(forest, payload)
    metadata = {'training': {'status': 'recorded', 'provenance': {'climate_sources': {
        'software-only-fixture': {'rainfall': 'annual_mean_total', 'temperature': 'annual_mean', 'humidity': 'current'}}}}}
    return forest, hashlib.sha256(payload.getvalue()).hexdigest(), metadata


def test_documented_seven_class_fixture_records_annual_inputs_and_explanation(providers, monkeypatch):
    import rainfallDatasets as env
    pipeline, _, seen = providers
    forest, version, metadata = seven_class_fixture()
    monkeypatch.setattr(env, 'MODEL', forest)
    monkeypatch.setattr(env, 'MODEL_VERSION', version)
    monkeypatch.setattr(env, 'LOADED_MODEL', SimpleNamespace(metadata=metadata))
    result = pipeline.analyze_location(7.29, 125.62)
    assert 'rainfall_recent' not in seen and 'nitrogen' in seen
    sample = result['model_explanation']['samples'][0]
    assert sample['inputs']['rainfall'] == 2100
    assert sample['model_climate_inputs']['rainfall']['unit'] == 'mm/year'
    assert sample['model_climate_inputs']['rainfall']['period'] == 'annual_mean_total'
    local = result['local_model_explanation']
    assert local['status'] == 'available'
    rain = next(item for item in local['feature_definitions'] if item['feature'] == 'rainfall')
    assert rain == {'feature': 'rainfall', 'label': 'Annual rainfall (5-year mean)', 'unit': 'mm/year'}
    assert set(local['class_order']) == {name.lower() for name in REQUIREMENTS}


@pytest.mark.parametrize('change', ['missing', 'recent_rain', 'legacy_status'])
def test_annual_model_guard_rejects_unproven_or_recent_periods(change):
    forest, _, metadata = seven_class_fixture()
    assert annual_model_ready(forest, metadata)
    if change == 'missing':
        metadata = {}
    elif change == 'recent_rain':
        metadata['training']['provenance']['climate_sources']['software-only-fixture']['rainfall'] = 'rolling_30_days'
    else:
        metadata['training']['status'] = 'legacy_unverified'
    assert not annual_model_ready(forest, metadata)
