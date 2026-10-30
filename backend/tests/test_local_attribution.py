"""Known-tree arithmetic and real-forest local attribution, no provider traffic."""
from copy import deepcopy
import hashlib
import io
import json
from types import SimpleNamespace

import joblib
import numpy as np
import pandas as pd
import pytest
from sklearn.ensemble import RandomForestClassifier

from local_attribution import (METHOD, TOLERANCE, sample_attribution, input_hash, numeric_hash,
                               bind_local_explanation, core_hash, aggregate_hash)
from model_explainability import FEATURE_LABELS, forest_snapshot
from model_ranking import attach_model_ranking


def version(model):
    buffer = io.BytesIO(); joblib.dump(model, buffer)
    return hashlib.sha256(buffer.getvalue()).hexdigest()


def stump():
    frame = pd.DataFrame({'N': [0, 0, 1, 1], 'P': [7, 7, 7, 7]})
    model = RandomForestClassifier(n_estimators=1, bootstrap=False, max_features=None, random_state=42).fit(frame, ['rice', 'rice', 'banana', 'banana'])
    return model


def explain(model, values):
    values = {key: float(values[key]) for key in model.feature_names_in_}
    frame = pd.DataFrame([values], columns=list(model.feature_names_in_))
    probabilities = dict(zip((str(c) for c in model.classes_), model.predict_proba(frame)[0].tolist()))
    return sample_attribution(model, version(model), values, probabilities), values, probabilities


def test_known_stump_base_signed_class_mapping_and_zero_unused_feature():
    model = stump()
    core, _, _ = explain(model, {'N': 0, 'P': 7})
    assert core['status'] == 'available'
    assert core['class_order'] == ['banana', 'rice']
    assert core['base_values'] == [.5, .5]
    np.testing.assert_allclose(core['contributions'], [[-.5, 0], [.5, 0]], atol=1e-15)
    assert core['model_scores'] == [0, 1]
    assert core_hash(core) == core['attribution_hash']


def test_float32_threshold_routing_matches_actual_sklearn_prediction():
    model = stump()
    threshold = model.estimators_[0].tree_.threshold[0]
    edge = np.nextafter(threshold, np.inf)
    assert edge > threshold and np.float32(edge) <= threshold
    core, _, _ = explain(model, {'N': edge, 'P': 7})
    assert core['status'] == 'available'
    assert core['model_scores'] == [0, 1]


def test_repeated_feature_splits_accumulate_to_the_known_single_feature_change():
    x = pd.DataFrame({'N': [0, 1, 2, 3]*4, 'P': [7]*16})
    model = RandomForestClassifier(n_estimators=1, bootstrap=False, max_features=None,
                                   random_state=7).fit(x, ['rice', 'banana', 'rice', 'banana']*4)
    core, _, _ = explain(model, {'N': 2, 'P': 7})
    assert model.estimators_[0].tree_.max_depth > 1
    np.testing.assert_allclose(core['contributions'], [[-.5, 0], [.5, 0]], atol=1e-15)


@pytest.mark.parametrize('layout', ['counts_3d', 'counts_2d', 'probability_3d'])
def test_explicit_supported_node_tensor_layouts_and_class_indices(layout):
    model = stump()
    values = np.array([[2, 2], [0, 2], [2, 0]], dtype=float)
    if layout == 'probability_3d':
        values = values/values.sum(axis=1, keepdims=True)
    if layout != 'counts_2d':
        values = values[:, None, :]
    tree = SimpleNamespace(value=values, node_count=3, max_depth=1,
                           children_left=np.array([1, -1, -1]), children_right=np.array([2, -1, -1]),
                           feature=np.array([0, -2, -2]), threshold=np.array([.5, -2, -2]))
    model.estimators_ = [SimpleNamespace(tree_=tree, classes_=np.array([0., 1.]))]
    # Explicit independent probabilities from the artificial three-node tree.
    core = sample_attribution(model, 'a'*64, {'N': 0., 'P': 7.}, {'rice': 1., 'banana': 0.})
    assert core['status'] == 'available'
    np.testing.assert_allclose(core['contributions'], [[-.5, 0], [.5, 0]])


def test_wrong_shape_class_indices_inputs_and_output_fail_without_fabricated_bars():
    model = stump()
    for inputs, probabilities, model_version in [
        ({'P': 7., 'N': 0.}, {'banana': 0., 'rice': 1.}, version(model)),
        ({'N': 0., 'P': 7.}, {'banana': 1., 'rice': 0.}, version(model)),
        ({'N': float('nan'), 'P': 7.}, {'banana': 0., 'rice': 1.}, version(model)),
        ({'N': 0., 'P': 7.}, {'banana': 0., 'rice': 1.}, 'missing-version'),
    ]:
        result = sample_attribution(model, model_version, inputs, probabilities)
        assert result['status'] == 'unavailable'
        assert 'contributions' not in result
    changed = deepcopy(model); changed.estimators_[0].classes_ = np.array([1., 0.])
    result = sample_attribution(changed, version(changed), {'N': 0., 'P': 7.}, {'banana': 0., 'rice': 1.})
    assert result['status'] == 'unavailable'
    multiple = RandomForestClassifier(n_estimators=1).fit(pd.DataFrame({'N': [0, 1, 2, 3]}), [[0, 0], [1, 1], [0, 1], [1, 0]])
    assert sample_attribution(multiple, version(multiple), {'N': 1.}, {'a': 1.})['status'] == 'unavailable'


def ranked_stump(values=(0., 1.)):
    model = stump(); v = version(model)
    snapshots = []
    for value in values:
        inputs = {'N': value, 'P': 7.}
        frame = pd.DataFrame([inputs])
        probabilities = {str(label): float(value) for label, value in zip(model.classes_, model.predict_proba(frame)[0])}
        snapshots.append(forest_snapshot(model, v, inputs, model.predict(frame)[0], probabilities))
    return attach_model_ranking({}, snapshots), snapshots


def test_parcel_averages_the_same_samples_and_every_crop_still_has_exact_original_score():
    record, snapshots = ranked_stump((0., 0., 1.))
    local = record['local_model_explanation']
    assert local['status'] == 'available' and local['sample_count'] == 3
    assert [c['crop'] for c in record['top_crop_recommendations']] == ['Rice', 'Banana']
    assert record['crop_compatibility_pct'] == pytest.approx(200/3)
    np.testing.assert_allclose(local['base_values'], [.5, .5])
    np.testing.assert_allclose(local['contributions'], [[-1/6, 0], [1/6, 0]])
    np.testing.assert_allclose(np.array(local['base_values'])+np.array(local['contributions']).sum(axis=1), local['model_scores'])
    assert local['snapshot_hash'] == aggregate_hash(local)
    assert local['prediction_context_id'] == record['prediction_context_id']
    assert local['input_snapshot_hash'] == record['model_explanation']['input_snapshot_hash']
    assert local['sample_input_hashes'] == [s['samples'][0]['local_attribution']['input_hash'] for s in snapshots]
    # Explaining mean N=1/3 would give rice=1, not the actual parcel mean 2/3.
    centroid, _, _ = explain(stump(), {'N': 1/3, 'P': 7})
    assert centroid['model_scores'][1] != pytest.approx(local['model_scores'][1])


@pytest.mark.parametrize('mutation', ['missing', 'version', 'input', 'class', 'contribution', 'score', 'method'])
def test_missing_or_mismatched_sample_attribution_keeps_ranking_and_marks_explanation_unavailable(mutation):
    record, snapshots = ranked_stump((0., 0., 1.))
    expected = deepcopy(record['top_crop_recommendations'])
    broken = deepcopy(snapshots)
    sample = broken[0]['samples'][0]
    if mutation == 'missing':
        sample.pop('local_attribution')
    elif mutation == 'version':
        sample['local_attribution']['model_version'] = 'b'*64
    elif mutation == 'input':
        sample['inputs']['N'] = .25
    elif mutation == 'class':
        sample['local_attribution']['class_order'].reverse()
    elif mutation == 'contribution':
        sample['local_attribution']['contributions'][0][0] += .2
    elif mutation == 'score':
        sample['local_attribution']['model_scores'][0] += .2
    else:
        sample['local_attribution']['method_version'] = 'unknown-method'
    updated = attach_model_ranking({}, broken)
    assert updated['top_crop_recommendations'] == expected
    assert updated['local_model_explanation']['status'] == 'unavailable'
    assert 'contributions' not in updated['local_model_explanation']


def test_legacy_blended_scores_never_borrow_local_raw_probability_explanation():
    record, _ = ranked_stump()
    record['recommendation_basis'] = 'old_blended_rule'
    updated = bind_local_explanation(record, record['model_explanation'], FEATURE_LABELS)
    assert updated['local_model_explanation']['status'] == 'unavailable'


def test_context_cache_returns_independent_copies_and_rechecks_probabilities():
    model = stump()
    first, inputs, probabilities = explain(model, {'N': 0, 'P': 7})
    frozen = deepcopy(first)
    first['contributions'][0][0] = 999
    second = sample_attribution(model, version(model), inputs, probabilities)
    assert second == frozen
    assert sample_attribution(model, version(model), inputs, {'banana': 1., 'rice': 0.})['status'] == 'unavailable'


def test_signatures_are_numeric_ordered_and_json_roundtrip_stable():
    key = input_hash('a'*64, ['N', 'P'], {'P': 7, 'N': 0.0})
    assert key == input_hash('a'*64, ['N', 'P'], {'N': 0, 'P': 7.0})
    assert key != input_hash('a'*64, ['N', 'P'], {'N': -0.0, 'P': 7.0})
    assert numeric_hash('domain', {'z': 1, 'a': 'test'}, [1e-20, -4.5, 0]) == numeric_hash('domain', {'a': 'test', 'z': 1}, [1e-20, -4.5, 0.0])
    record, _ = ranked_stump((0., 0., 1.))
    restored = json.loads(json.dumps(record))
    assert aggregate_hash(restored['local_model_explanation']) == record['local_model_explanation']['snapshot_hash']


def test_actual_500_tree_17_class_forest_reconstructs_all_classes_without_score_change():
    import rainfallDatasets as env
    values = [80., 55., 46., 27., 80., 6., 110., .65, 100., 3.]
    inputs = dict(zip(env.MODEL.feature_names_in_, values))
    frame = pd.DataFrame([inputs])
    probabilities = {str(label): float(value) for label, value in zip(env.MODEL.classes_, env.MODEL.predict_proba(frame)[0])}
    core = sample_attribution(env.MODEL, env.MODEL_VERSION, inputs, probabilities)
    assert core['status'] == 'available'
    assert core['class_order'] == env.MODEL.classes_.tolist()
    calculated = np.asarray(core['base_values'])+np.asarray(core['contributions']).sum(axis=1)
    np.testing.assert_allclose(calculated, list(probabilities.values()), atol=TOLERANCE, rtol=0)
    np.testing.assert_allclose(np.asarray(core['contributions']).sum(axis=0), 0, atol=TOLERANCE)
    snapshot = forest_snapshot(env.MODEL, env.MODEL_VERSION, inputs, env.MODEL.predict(frame)[0], probabilities)
    with_local = attach_model_ranking({}, [snapshot])
    old_style = deepcopy(snapshot);old_style['samples'][0].pop('local_attribution')
    without_local = attach_model_ranking({}, [old_style])
    assert with_local['top_crop_recommendations'] == without_local['top_crop_recommendations']
    assert with_local['local_model_explanation']['status'] == 'available'
