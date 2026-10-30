"""Bounded signed tree-path decomposition of the existing forest probabilities.

For each tree, attribute each traversed child-minus-parent class distribution
to its split feature. Average roots and contributions across trees. This is an
additive, split-order-dependent model explanation, not SHAP or a causal effect.
No background dataset, retraining, feature substitution or rank adjustment.
"""
from collections import OrderedDict
from copy import deepcopy
import hashlib
import json
import math
import re
import struct
from threading import RLock

import numpy as np
from sklearn.ensemble import RandomForestClassifier

SCHEMA = 1
METHOD = 'random_forest_tree_path_probability'
METHOD_VERSION = 'rf-path-probability-v1'
TOLERANCE = 1e-9
MAX_SAMPLES = 64
_LOCK = RLock()
_PREPARED = None
_CONTEXTS = OrderedDict()

LIMITATIONS = [
    'Contributions describe the stored model score relative to its training-root baseline; they do not prove crop success or causal effects.',
    'Tree-path allocation depends on split order and correlated features. It is not a Shapley/SHAP explanation and has no causal or consistency guarantee.',
    'The baseline is the mean of stored weighted training-root class distributions, not measured farm suitability or a separate field reference population.',
    'N/P/K model inputs remain estimates/proxies with unresolved physical unit compatibility; these contributions are not soil measurements or fertilizer advice.',
    'Legacy training includes synthetic GIS/local rows and has no established Panabo field validation. Class scores are uncalibrated, not harvest probabilities.',
    'Parcel attribution averages the recorded sample predictions. It is not a new prediction on averaged inputs or a full-raster suitability assessment.',
]


def numeric_hash(domain, metadata, values):
    """Cross-language signature: sorted UTF-8 JSON metadata + big-endian float64.

    Using numeric bytes avoids Python/Dart JSON exponent-format differences.
    This is an integrity/context checksum, not an authentication signature.
    """
    header = json.dumps(metadata, sort_keys=True, ensure_ascii=False, allow_nan=False,
                        separators=(',', ':')).encode()
    numbers = [float(value) for value in values]
    if not all(math.isfinite(value) for value in numbers):
        raise ValueError('Nonfinite attribution value')
    payload = domain.encode()+b'\0'+header+b'\0'+struct.pack('>'+str(len(numbers))+'d', *numbers)
    return hashlib.sha256(payload).hexdigest()


def input_hash(version, order, inputs):
    if set(inputs) != set(order) or any(isinstance(inputs[key], bool) for key in order):
        raise ValueError('Input feature contract mismatch')
    return numeric_hash('geosustain-local-input-v1',
                        {'feature_order': order, 'model_version': version}, [inputs[key] for key in order])


def unavailable(reason, version=None):
    return {'schema_version': SCHEMA, 'status': 'unavailable', 'method': METHOD,
            'method_version': METHOD_VERSION, 'model_version': version, 'reason': reason}


def core_metadata(core):
    return {key: core[key] for key in ('class_order', 'feature_order', 'input_hash', 'method_version', 'model_version')}


def core_values(core):
    return [*core['base_values'], *(v for row in core['contributions'] for v in row), *core['model_scores']]


def core_hash(core):
    return numeric_hash('geosustain-rf-path-attribution-v1', core_metadata(core), core_values(core))


def _prepare(model, version):
    global _PREPARED
    if not isinstance(model, RandomForestClassifier) or not re.fullmatch('[0-9a-f]{64}', str(version)):
        raise ValueError('Unsupported model or missing exact artifact identity')
    names = [str(value) for value in model.feature_names_in_]
    classes = [str(value) for value in model.classes_]
    if (model.n_outputs_ != 1 or not 1 <= len(names) <= 32 or not 2 <= len(classes) <= 64
            or len(set(names)) != len(names) or len(set(classes)) != len(classes)
            or not 1 <= len(model.estimators_) <= 1000):
        raise ValueError('Unsupported feature/class/tree shape')
    signature = (tuple(names), tuple(classes), tuple(id(tree) for tree in model.estimators_))
    with _LOCK:
        if (_PREPARED is not None and _PREPARED['model'] is model
                and _PREPARED['version'] == version and _PREPARED['signature'] == signature):
            return _PREPARED
        if (sum(tree.tree_.node_count for tree in model.estimators_) > 300000
                or sum(tree.tree_.value.size for tree in model.estimators_) > 5000000
                or sum(tree.tree_.max_depth for tree in model.estimators_) > 50000):
            raise ValueError('Explanation work/memory budget exceeded')
        trees = []
        for estimator in model.estimators_:
            tree = estimator.tree_
            if not np.array_equal(estimator.classes_, np.arange(len(classes))):
                raise ValueError('Tree-to-forest class index mismatch')
            value = np.asarray(tree.value, dtype=np.float64)
            if value.shape == (tree.node_count, 1, len(classes)):
                value = value[:, 0, :]
            elif value.shape != (tree.node_count, len(classes)):
                raise ValueError('Unsupported node/output/class tensor shape')
            total = value.sum(axis=1, keepdims=True)
            if not np.isfinite(value).all() or np.any(value < 0) or np.any(total <= 0):
                raise ValueError('Invalid class distributions')
            probabilities = value/total  # Accept both counts and normalized sklearn layouts.
            probabilities.setflags(write=False)
            trees.append((tree.children_left, tree.children_right, tree.feature, tree.threshold, probabilities))
        _PREPARED = {'model': model, 'version': version, 'signature': signature,
                     'features': names, 'classes': classes, 'trees': trees,
                     'base': np.mean([tree[4][0] for tree in trees], axis=0),
                     'normalized_node_bytes': sum(tree[4].nbytes for tree in trees)}
        _CONTEXTS.clear()
        return _PREPARED


def sample_attribution(model, version, inputs, probabilities):
    """Optional attribution: failure never changes the already computed score."""
    try:
        prepared = _prepare(model, version)
        order, classes = prepared['features'], prepared['classes']
        if list(inputs) != order or set(probabilities) != set(classes):
            raise ValueError('Feature/class probability contract mismatch')
        expected = np.array([probabilities[label] for label in classes], dtype=float)
        if (not np.isfinite(expected).all() or np.any(expected < 0) or np.any(expected > 1)
                or not math.isclose(float(expected.sum()), 1, abs_tol=TOLERANCE)):
            raise ValueError('Invalid source probabilities')
        context_hash = input_hash(version, order, inputs)
        with _LOCK:
            prior = deepcopy(_CONTEXTS.get(context_hash)) if _PREPARED is prepared else None
            if prior:
                _CONTEXTS.move_to_end(context_hash)
        if prior:
            if np.max(np.abs(np.asarray(prior['model_scores'])-expected)) > TOLERANCE:
                raise ValueError('Cached attribution/source score mismatch')
            return prior
        # sklearn uses float32 inputs at prediction time. Match its threshold routing.
        values = np.asarray([inputs[key] for key in order], dtype=np.float32)
        if not np.isfinite(values).all():
            raise ValueError('Model input outside float32 range')
        contributions = np.zeros((len(classes), len(order)), dtype=float)
        leaves = np.zeros(len(classes), dtype=float)
        visits = 0
        for left, right, feature, threshold, distributions in prepared['trees']:
            node = 0
            while left[node] != -1:
                visits += 1
                if visits > 50000:
                    raise ValueError('Tree path budget exceeded')
                index = int(feature[node])
                if not 0 <= index < len(order):
                    raise ValueError('Invalid split feature index')
                child = int(left[node] if values[index] <= threshold[node] else right[node])
                if not 0 <= child < len(distributions):
                    raise ValueError('Invalid child index')
                contributions[:, index] += distributions[child]-distributions[node]
                node = child
            leaves += distributions[node]
        contributions /= len(prepared['trees'])
        leaves /= len(prepared['trees'])
        base = prepared['base']
        if (np.max(np.abs(base+contributions.sum(axis=1)-leaves)) > TOLERANCE
                or np.max(np.abs(leaves-expected)) > TOLERANCE):
            raise ValueError('Local attribution did not reconstruct the exact model output')
        core = {'schema_version': SCHEMA, 'status': 'available', 'method': METHOD, 'method_version': METHOD_VERSION,
                'model_version': version, 'feature_order': order, 'class_order': classes,
                'input_hash': context_hash, 'base_values': base.tolist(),
                'contributions': contributions.tolist(), 'model_scores': leaves.tolist(),
                'tolerance_probability': TOLERANCE,
                'baseline_definition': 'Arithmetic mean of stored weighted class distributions at the 500-tree training roots' if len(prepared['trees']) == 500
                    else 'Arithmetic mean of stored weighted training-root class distributions',
                'tree_count': len(prepared['trees']), 'input_dtype': 'float32 threshold routing; original float64 inputs retained and hashed'}
        core['attribution_hash'] = core_hash(core)
        with _LOCK:
            if _PREPARED is prepared:
                _CONTEXTS[context_hash] = deepcopy(core)
                _CONTEXTS.move_to_end(context_hash)
                while len(_CONTEXTS) > 128:
                    _CONTEXTS.popitem(last=False)
        return core
    except Exception:
        return unavailable('A matching local attribution could not be verified for these model inputs and class scores. The recorded model score is unchanged.', version)


def _validated_sample(sample, version):
    core = sample.get('local_attribution')
    if not isinstance(core, dict) or core.get('status') != 'available':
        raise ValueError('At least one sample lacks a valid local attribution')
    if (core.get('schema_version') != SCHEMA or core.get('method') != METHOD
            or core.get('method_version') != METHOD_VERSION or core.get('model_version') != version
            or sample.get('model_version') != version):
        raise ValueError('Sample model/method mismatch')
    order, classes = core['feature_order'], core['class_order']
    if core['input_hash'] != input_hash(version, order, sample['inputs']):
        raise ValueError('Sample input hash mismatch')
    if core['attribution_hash'] != core_hash(core):
        raise ValueError('Sample attribution checksum mismatch')
    base, contributions, scores = (np.asarray(core[key], dtype=float) for key in ('base_values', 'contributions', 'model_scores'))
    if (base.shape != (len(classes),) or scores.shape != base.shape or contributions.shape != (len(classes), len(order))
            or len(set(classes)) != len(classes) or len(set(order)) != len(order)
            or not np.isfinite(contributions).all() or not np.isfinite(base).all() or not np.isfinite(scores).all()):
        raise ValueError('Attribution tensor/class shape mismatch')
    expected = np.array([sample['class_probabilities'][label] for label in classes])
    if set(sample['class_probabilities']) != set(classes):
        raise ValueError('Attribution/source class mismatch')
    if (np.max(np.abs(base+contributions.sum(axis=1)-scores)) > TOLERANCE
            or np.max(np.abs(scores-expected)) > TOLERANCE):
        raise ValueError('Sample additivity mismatch')
    return core


def aggregate_metadata(body):
    return {key: body[key] for key in ('class_order', 'crop_classes', 'feature_definitions', 'feature_order',
            'input_snapshot_hash', 'method_version', 'model_version', 'prediction_context_id',
            'sample_attribution_hashes', 'sample_count', 'sample_input_hashes')}


def aggregate_values(body):
    return [*body['base_values'], *(v for row in body['contributions'] for v in row), *body['model_scores'],
            *(float(item[key]) for item in body['feature_inputs'] for key in ('mean', 'minimum', 'maximum'))]


def aggregate_hash(body):
    return numeric_hash('geosustain-rf-path-aggregate-v1', aggregate_metadata(body), aggregate_values(body))


def bind_local_explanation(result, snapshot, feature_labels):
    """Bind only actual sample-mean class scores; legacy blended scores refuse."""
    version = snapshot.get('model_version')
    try:
        if result.get('recommendation_basis') != 'model_probability':
            raise ValueError('Result is not a recorded raw model-probability ranking')
        samples = snapshot.get('samples', [])
        if not 1 <= len(samples) <= MAX_SAMPLES:
            raise ValueError('Missing or oversized sampled prediction context')
        cores = [_validated_sample(sample, version) for sample in samples]
        order, classes = cores[0]['feature_order'], cores[0]['class_order']
        if any(core['feature_order'] != order or core['class_order'] != classes for core in cores):
            raise ValueError('Sample feature/class order mismatch')
        base = np.mean([core['base_values'] for core in cores], axis=0)
        contributions = np.mean([core['contributions'] for core in cores], axis=0)
        scores = np.mean([core['model_scores'] for core in cores], axis=0)
        if np.max(np.abs(base+contributions.sum(axis=1)-scores)) > TOLERANCE:
            raise ValueError('Parcel additivity mismatch')
        crops = []
        for crop in result.get('crop_assessments') or []:
            name = str(crop['crop']); label = name.lower()
            if label not in classes:
                raise ValueError('No exact trained class for the displayed crop')
            index = classes.index(label)
            if abs(float(crop['compatibility_pct'])/100-scores[index]) > TOLERANCE:
                raise ValueError('Displayed crop score differs from the explained sample mean')
            crops.append({'crop': name, 'class_label': label, 'class_index': index})
        if not crops or len({c['crop'] for c in crops}) != len(crops):
            raise ValueError('Missing/duplicate displayed crop bindings')
        selected = next((crop for crop in crops if crop['crop'] == result.get('predicted_crop')), None)
        if selected is None or abs(float(result['crop_compatibility_pct'])/100-scores[selected['class_index']]) > TOLERANCE:
            raise ValueError('Selected output/score context mismatch')
        definitions = [{'feature': name, 'label': feature_labels.get(name, (name, ''))[0],
                        'unit': feature_labels.get(name, (name, ''))[1]} for name in order]
        features = []
        for name in order:
            values = [float(sample['inputs'][name]) for sample in samples]
            features.append({'feature': name, 'mean': sum(values)/len(values),
                             'minimum': min(values), 'maximum': max(values)})
        body = {'schema_version': SCHEMA, 'status': 'available', 'scope': 'sample_mean_class_probability',
                'method': METHOD, 'method_version': METHOD_VERSION, 'method_label': 'Signed local tree-path probability contributions',
                'model_version': version, 'prediction_context_id': snapshot['prediction_context_id'],
                'input_snapshot_hash': snapshot['input_snapshot_hash'], 'sample_count': len(samples),
                'sample_input_hashes': [core['input_hash'] for core in cores],
                'sample_attribution_hashes': [core['attribution_hash'] for core in cores],
                'feature_order': order, 'class_order': classes, 'crop_classes': crops,
                'feature_definitions': definitions, 'feature_inputs': features,
                'base_values': base.tolist(), 'contributions': contributions.tolist(), 'model_scores': scores.tolist(),
                'selected_output': result['predicted_crop'], 'selected_score': result['crop_compatibility_pct'],
                'units': 'Probability in stored arrays; display signed contributions as percentage points (x100), not percent change.',
                'aggregation': f'Arithmetic mean of the same {len(samples)} recorded sample class decompositions used for crop ranking. No centroid/mean-input model prediction.',
                'baseline_definition': cores[0]['baseline_definition'], 'tolerance_probability': TOLERANCE,
                'limitations': LIMITATIONS}
        body['snapshot_hash'] = aggregate_hash(body)
        result['local_model_explanation'] = body
    except Exception:
        body = unavailable('A matching local explanation was not verified for every recorded sample and crop score. No signed contributions are shown; the model ranking is unchanged.', version)
        body.update(prediction_context_id=snapshot.get('prediction_context_id'),
                    input_snapshot_hash=snapshot.get('input_snapshot_hash'), limitations=LIMITATIONS)
        result['local_model_explanation'] = body
    return result


def cache_diagnostics():
    with _LOCK:
        return {'models_prepared': int(_PREPARED is not None), 'contexts': len(_CONTEXTS),
                'normalized_node_bytes': _PREPARED['normalized_node_bytes'] if _PREPARED else 0,
                'context_limit': 128, 'normalized_float_limit': 5000000}
