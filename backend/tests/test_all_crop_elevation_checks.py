"""Traceable elevation checks without inventing missing optimum/class ranges."""
from copy import deepcopy

import numpy as np
import pandas as pd
import pytest

from crop_requirements import REQUIREMENTS, VERSION, elevation_references
from database import enrich_history_rows
from model_artifacts import FEATURES, load_model_artifact
from model_explainability import forest_snapshot
from model_ranking import attach_model_ranking
from suitability import assess, attach_assessment, factor_result


def elevation_results(change=None):
    observation = {'value': 29.89, 'unit': 'm', 'period': 'terrain', 'quality': 'modelled',
                   'source': 'Controlled DEM-compatible software test, not a farm', **(change or {})}
    return {row['crop']: next(f for f in row['factors'] if f['factor'] == 'elevation')
            for row in assess({'elevation': observation})}


@pytest.mark.parametrize('name', list(REQUIREMENTS))
def test_all_seven_crops_save_cited_elevation_checks_for_a_compatible_observation(name):
    item = elevation_results()[name]
    assert item['value'] == 29.89 and item['unit'] == 'm' and item['period'] == 'terrain'
    assert item['score'] == 100
    assert item['requirement'] == REQUIREMENTS[name]['elevation']
    rule = item['requirement']
    assert rule['source']['url'].startswith('https://')
    assert rule['source']['title'] and rule['source']['section'] and rule['limitations']


@pytest.mark.parametrize('name,limit,exclusive', [
    ('Banana', 2400, False), ('Rice', 2500, False), ('Mango', 600, False),
    ('Coconut', 600, True), ('Durian', 800, True),
])
def test_published_upper_altitude_limits_keep_their_inclusive_or_strict_boundary(name, limit, exclusive):
    rule = REQUIREMENTS[name]['elevation']
    assert rule['optimal'] == [None, limit]  # No invented optimum lower altitude.
    assert rule['classes'] is None
    assert rule.get('optimal_upper_exclusive', False) == exclusive
    for value, expected in [(0, 100), (limit - .01, 100),
                            (limit, 0 if exclusive else 100), (limit + .01, 0)]:
        score, result = factor_result(value, rule, 'elevation')
        assert score == expected
        assert result not in ('S1', 'S2', 'S3', 'N')


@pytest.mark.parametrize('name,lower,upper', [('Cacao', 1000, 1500), ('Rubber', 500, 1000)])
def test_bswm_altitude_classes_preserve_shared_and_strict_endpoints(name, lower, upper):
    rule = REQUIREMENTS[name]['elevation']
    for value, expected in [(0, 'S1'), (lower - .01, 'S1'), (lower, 'S2'),
                            (upper, 'S2'), (upper + .01, 'S3')]:
        assert factor_result(value, rule, 'elevation')[1] == expected
    assert 'N' not in rule['classes']


@pytest.mark.parametrize('change', [
    {'value': None}, {'value': True}, {'value': float('nan')}, {'value': float('inf')},
    {'unit': 'feet'}, {'period': 'current'}, {'quality': 'estimated'},
])
def test_missing_incompatible_or_fallback_altitude_remains_unassessed_for_every_crop(change):
    assert all(item['score'] is None for item in elevation_results(change).values())


def test_elevation_metadata_is_frozen_separately_from_the_fitted_forest():
    refs = elevation_references()
    assert load_model_artifact().metadata['elevation_reference_requirements'] == refs
    assert refs['version'] == VERSION
    assert refs['affects_fitted_model'] is False
    assert (refs['unit'], refs['period']) == ('m', 'terrain')
    assert set(refs['crops']) == {name.lower() for name in REQUIREMENTS}
    refs['crops']['cacao']['classes']['S1'][0][1] = 999
    assert REQUIREMENTS['Cacao']['elevation']['classes']['S1'][0][1] == 1000


def test_historical_unassessed_altitude_is_not_regraded_with_new_criteria():
    saved = {'crop_config_version': 'panabo-annual-terrain-references-2026-11-06-v4',
             'crop_assessments': [{'crop': 'Cacao', 'factors': [
                 {'factor': 'elevation', 'value': 29.89, 'score': None, 'requirement': None}]}]}
    before = deepcopy(saved)
    row = enrich_history_rows([{'session_id': 91, 'result_snapshot': saved}])[0]
    assert row['crop_config_version'] == before['crop_config_version']
    assert row['crop_assessments'] == before['crop_assessments']
    assert saved == before


def test_elevation_checks_preserve_real_forest_probabilities_and_local_explanation(monkeypatch):
    import model_explainability
    monkeypatch.setattr(model_explainability.uuid, 'uuid4', lambda: 'fixed-elevation-test-context')
    loaded = load_model_artifact()
    inputs = dict(zip(FEATURES, [80, 55, 46, 27, 80, 6, 2100, .6, 29.89, 5.83]))
    names = list(loaded.model.feature_names_in_)
    inputs = {name: inputs[name] for name in names}
    frame = pd.DataFrame([inputs], columns=names)
    probabilities = dict(zip(map(str, loaded.model.classes_), map(float, loaded.model.predict_proba(frame)[0])))
    snapshot = forest_snapshot(loaded.model, loaded.version, inputs, loaded.model.predict(frame)[0], probabilities)
    base = attach_model_ranking({}, [deepcopy(snapshot)])
    comparison = attach_assessment({}, {'elevation': {'value': 29.89, 'unit': 'm',
        'period': 'terrain', 'quality': 'modelled', 'source': 'Controlled software test'}})
    changed = attach_model_ranking(comparison, [deepcopy(snapshot)])
    assert changed['predicted_crop'] == base['predicted_crop']
    assert changed['crop_compatibility_pct'] == base['crop_compatibility_pct']
    np.testing.assert_array_equal(changed['local_model_explanation']['model_scores'],
                                  base['local_model_explanation']['model_scores'])
    assert changed['local_model_explanation']['snapshot_hash'] == base['local_model_explanation']['snapshot_hash']
    assert all(next(f for f in c['factors'] if f['factor'] == 'elevation')['score'] is not None
               for c in changed['crop_assessments'])
