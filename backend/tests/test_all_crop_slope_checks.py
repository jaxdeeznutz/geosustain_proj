"""Crop-specific percent-slope references, independent of model ranking."""
from copy import deepcopy

import numpy as np
import pandas as pd
import pytest

from crop_requirements import REQUIREMENTS, VERSION, slope_references
from database import enrich_history_rows
from model_artifacts import FEATURES, load_model_artifact
from model_explainability import forest_snapshot
from model_ranking import attach_model_ranking
from suitability import assess, attach_assessment, factor_result


def slope_results(observation):
    return {crop['crop']: next(f for f in crop['factors'] if f['factor'] == 'slope')
            for crop in assess({'slope': observation})}


@pytest.mark.parametrize('name', list(REQUIREMENTS))
def test_all_seven_crops_assess_a_compatible_measured_slope_with_saved_citation(name):
    measured = {'value': 5.83, 'unit': '%', 'period': 'terrain', 'quality': 'modelled',
                'source': 'Controlled SRTM-compatible software test, not a real farm'}
    before = deepcopy(measured)
    item = slope_results(measured)[name]
    assert item['value'] == 5.83
    assert item['unit'] == '%'
    assert item['period'] == 'terrain'
    assert (item['score'], item['result']) == ((67, 'S2') if name == 'Rice' else (100, 'S1'))
    assert item['requirement'] == REQUIREMENTS[name]['slope']
    assert item['requirement']['source']['url'].startswith('https://')
    assert item['requirement']['source']['title'] and item['requirement']['source']['section']
    assert item['requirement']['limitations']
    assert measured == before


@pytest.mark.parametrize('name', ['Banana', 'Coconut', 'Mango', 'Durian'])
def test_four_class_slopes_keep_printed_boundaries_and_strict_unsuitable_limit(name):
    for value, expected in [(0, 'S1'), (7.99, 'S1'), (8, 'S2'), (15.99, 'S2'),
                            (16, 'S3'), (30, 'S3'), (30.01, 'N')]:
        assert factor_result(value, REQUIREMENTS[name]['slope'], 'slope')[1] == expected


@pytest.mark.parametrize('name', ['Cacao', 'Rubber'])
def test_three_class_source_does_not_invent_an_unsuitable_slope_class(name):
    for value, expected in [(0, 'S1'), (7.99, 'S1'), (8, 'S2'), (16, 'S2'),
                            (30, 'S2'), (30.01, 'S3'), (100, 'S3')]:
        assert factor_result(value, REQUIREMENTS[name]['slope'], 'slope')[1] == expected
    assert 'N' not in REQUIREMENTS[name]['slope']['classes']


@pytest.mark.parametrize('change', [
    {'value': None}, {'value': True}, {'value': float('nan')}, {'value': -1},
    {'unit': 'degrees'}, {'period': 'current'}, {'quality': 'estimated'},
])
def test_missing_wrong_unit_or_unsupported_slope_is_not_graded_for_any_crop(change):
    observation = {'value': 5.83, 'unit': '%', 'period': 'terrain', 'quality': 'modelled', **change}
    assert all(f['score'] is None for f in slope_results(observation).values())


def test_seven_crop_slope_metadata_matches_catalog_and_is_a_deep_copy():
    loaded = load_model_artifact()
    refs = slope_references()
    assert loaded.metadata['slope_reference_requirements'] == refs
    assert set(refs['crops']) == {name.lower() for name in REQUIREMENTS}
    assert refs['version'] == VERSION
    assert refs['affects_fitted_model'] is False
    refs['crops']['banana']['classes']['S1'][0][1] = 999
    assert REQUIREMENTS['Banana']['slope']['classes']['S1'][0][1] == 8


def test_historical_missing_crop_criterion_is_not_replaced_by_new_rules():
    saved = {'crop_config_version': 'panabo-annual-terrain-references-2026-11-06-v3',
             'crop_assessments': [{'crop': 'Mango', 'factors': [
                 {'factor': 'slope', 'value': 5.83, 'score': None, 'requirement': None}]}]}
    before = deepcopy(saved)
    row = enrich_history_rows([{'session_id': 90, 'result_snapshot': saved}])[0]
    assert row['crop_config_version'] == before['crop_config_version']
    assert row['crop_assessments'] == before['crop_assessments']
    assert saved == before


def test_new_slope_comparisons_leave_actual_forest_scores_and_attribution_unchanged(monkeypatch):
    import model_explainability
    monkeypatch.setattr(model_explainability.uuid, 'uuid4', lambda: 'fixed-slope-comparison-context')
    loaded = load_model_artifact()
    inputs = dict(zip(FEATURES, [80, 55, 46, 27, 80, 6, 2100, .6, 30, 5.83]))
    names = list(loaded.model.feature_names_in_)
    inputs = {name: inputs[name] for name in names}
    frame = pd.DataFrame([inputs], columns=names)
    probabilities = dict(zip(map(str, loaded.model.classes_), map(float, loaded.model.predict_proba(frame)[0])))
    snapshot = forest_snapshot(loaded.model, loaded.version, inputs, loaded.model.predict(frame)[0], probabilities)
    base = attach_model_ranking({}, [deepcopy(snapshot)])
    comparison = attach_assessment({}, {'slope': {'value': 5.83, 'unit': '%',
        'period': 'terrain', 'quality': 'modelled', 'source': 'Controlled test'}})
    changed = attach_model_ranking(comparison, [deepcopy(snapshot)])
    assert changed['predicted_crop'] == base['predicted_crop']
    assert changed['crop_compatibility_pct'] == base['crop_compatibility_pct']
    np.testing.assert_array_equal(changed['local_model_explanation']['model_scores'],
                                  base['local_model_explanation']['model_scores'])
    assert changed['local_model_explanation']['snapshot_hash'] == base['local_model_explanation']['snapshot_hash']
    assert all(next(f for f in c['factors'] if f['factor'] == 'slope')['score'] is not None
               for c in changed['crop_assessments'])
