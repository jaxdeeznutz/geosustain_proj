"""Published annual checks change evidence, never fitted forest predictions."""
from copy import deepcopy

import numpy as np
import pandas as pd
import pytest

from crop_requirements import REQUIREMENTS, VERSION, catalog, annual_rainfall_references
from model_artifacts import FEATURES, load_model_artifact
from model_explainability import FEATURE_LABELS, forest_snapshot
from model_ranking import attach_model_ranking
from suitability import attach_assessment, assess


def rainfall_factor(crop, value, period='annual_mean_total', unit='mm/year'):
    observation = {'value': value, 'unit': unit, 'period': period,
                   'quality': 'modelled', 'source': 'Controlled software test observation'}
    item = next(row for row in assess({'rainfall': observation}) if row['crop'] == crop)
    return next(f for f in item['factors'] if f['factor'] == 'rainfall')


def test_all_seven_crops_have_traceable_annual_rules_without_claiming_model_validation():
    assert len(catalog()['crops']) == 7
    for rules in REQUIREMENTS.values():
        rule = rules['rainfall']
        assert rule['source']['url'].startswith('https://')
        assert rule['source']['title'] and rule['source']['section'] and rule['limitations']
    assert VERSION == 'panabo-annual-terrain-references-2026-11-06-v5'
    assert REQUIREMENTS['Durian']['rainfall']['classes'] is None
    assert REQUIREMENTS['Rubber']['rainfall']['classes'] is None
    loaded = load_model_artifact()
    assert loaded.metadata['reference_requirements'] == annual_rainfall_references()
    assert loaded.metadata['reference_requirements']['affects_fitted_model'] is False


@pytest.mark.parametrize('crop,value,score', [
    ('Durian', 1750, 100), ('Durian', 2500, 0),
    ('Mango', 1000, 100), ('Mango', 2200, 50), ('Mango', 2700, 0),
    ('Rubber', 2500, 100), ('Rubber', 3500, 50), ('Rubber', 4000, 50), ('Rubber', 4001, 0),
])
def test_published_intervals_and_rubber_maximum_keep_their_meaning(crop, value, score):
    factor = rainfall_factor(crop, value)
    assert factor['score'] == score
    assert factor['result'] not in ('S1', 'S2', 'S3', 'N')
    if crop == 'Rubber' and 3000 < value <= 4000:
        assert 'upper maximum' in factor['result']


def test_recent_rain_is_not_admitted_by_annual_reference_checks():
    factor = rainfall_factor('Mango', 1000, period='rolling_30_days', unit='mm')
    assert factor['score'] is None
    assert factor['result'] == 'Incompatible unit or time period'


def test_attaching_new_reference_checks_preserves_actual_model_scores_and_attribution(monkeypatch):
    import model_explainability
    # Isolate the reference change; separate real analyses receive fresh context IDs.
    monkeypatch.setattr(model_explainability.uuid, 'uuid4', lambda: 'fixed-reference-comparison-context')
    loaded = load_model_artifact()
    inputs = dict(zip(FEATURES, [80, 55, 46, 27, 80, 6, 2100, .6, 30, 3]))
    names = list(loaded.model.feature_names_in_)
    inputs = {name: inputs[name] for name in names}
    frame = pd.DataFrame([inputs], columns=names)
    probabilities = dict(zip(map(str, loaded.model.classes_), map(float, loaded.model.predict_proba(frame)[0])))
    snapshot = forest_snapshot(loaded.model, loaded.version, inputs, loaded.model.predict(frame)[0], probabilities,
        feature_labels={**FEATURE_LABELS, 'rainfall': ('Annual rainfall (5-year mean)', 'mm/year')})
    snapshot['samples'][0]['model_climate_inputs'] = {'rainfall': {'period': 'annual_mean_total'}}
    base = attach_model_ranking({}, [deepcopy(snapshot)])
    measurements = {'rainfall': {'value': 2100, 'unit': 'mm/year', 'period': 'annual_mean_total',
                                'quality': 'modelled', 'source': 'Software fixture'}}
    changed = attach_model_ranking(attach_assessment({}, measurements), [deepcopy(snapshot)])
    assert changed['predicted_crop'] == base['predicted_crop']
    assert changed['crop_compatibility_pct'] == base['crop_compatibility_pct']
    np.testing.assert_array_equal(changed['local_model_explanation']['model_scores'],
                                  base['local_model_explanation']['model_scores'])
    assert changed['local_model_explanation']['snapshot_hash'] == base['local_model_explanation']['snapshot_hash']
    mango = next(row for row in changed['crop_assessments'] if row['crop'] == 'Mango')
    assert next(f for f in mango['factors'] if f['factor'] == 'rainfall')['requirement']['source']['url'].endswith('id=1416')


def test_saved_older_reference_snapshot_is_not_reinterpreted():
    from database import enrich_history_rows
    old = {'crop_config_version': 'panabo-2026-10-13-v1',
           'scoring_version': 'random-forest-probability-2026-10-14-v1',
           'crop_assessments': [{'crop': 'Durian', 'factors': [{'factor': 'rainfall',
               'requirement': {'optimal': [2000, 3000], 'source': {'title': 'Original saved reference'}}}]}]}
    restored = enrich_history_rows([{'result_snapshot': deepcopy(old)}])[0]
    assert restored['crop_config_version'] == old['crop_config_version']
    assert restored['crop_assessments'] == old['crop_assessments']
