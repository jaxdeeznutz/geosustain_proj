"""Persist the deployed forest's native importance, without inventing local attribution.

MDI is global, unsigned and shared across classes. It cannot explain why a
particular sample received a particular class or the application's blended score.
"""
from copy import deepcopy
import hashlib
import json
import math
import uuid
from local_attribution import sample_attribution, bind_local_explanation


FEATURE_LABELS = {
    'N': ('Nitrogen', 'unit unspecified'),
    'P': ('Phosphorus', 'unit unspecified'),
    'K': ('Potassium', 'unit unspecified'),
    'temperature': ('Temperature', '°C'),
    'humidity': ('Humidity', '%'),
    'ph': ('Soil pH', 'pH'),
    'rainfall': ('Recent rainfall (30 days)', 'mm / 30 days'),
    'ndvi': ('Plant cover (NDVI)', 'index'),
    'elevation': ('Elevation', 'm'),
    'slope': ('Slope', '%'),
}


def content_hash(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, allow_nan=False,
                                    separators=(',', ':')).encode()).hexdigest()


def forest_snapshot(model, version, inputs, raw_prediction, probabilities):
    """Called at inference, using the same frame and probability output."""
    sample = {
        'model_version': version, 'inputs': inputs,
        'raw_prediction': str(raw_prediction), 'class_probabilities': probabilities,
    }
    sample['sample_id'] = content_hash(sample)
    sample['local_attribution'] = sample_attribution(model, version, inputs, probabilities)
    result = {
        'schema_version': 1, 'status': 'unavailable', 'scope': 'global',
        'method': 'random_forest_mean_decrease_in_impurity',
        'method_label': 'Random Forest impurity-based feature importance',
        'model_type': type(model).__name__, 'model_version': version,
        'supports_direction': False, 'supports_crop_specific': False,
        'samples': [sample], 'features': [],
        'local_explanation_status': 'not_supported',
    }
    try:
        names = list(model.feature_names_in_)
        values = [float(v) for v in model.feature_importances_]
        if len(names) != len(values) or names != list(inputs):
            raise ValueError('Feature contract mismatch')
        if not all(math.isfinite(v) and v >= 0 for v in values):
            raise ValueError('Invalid importance values')
        result['features'] = [
            {'feature': name, 'label': FEATURE_LABELS.get(name, (name, ''))[0],
             'unit': FEATURE_LABELS.get(name, (name, ''))[1], 'importance': value}
            for name, value in zip(names, values)
        ]
        result['status'] = 'available'
    except (AttributeError, TypeError, ValueError):
        result['reason'] = 'The model did not provide valid native feature importance.'
    return result


def merge_model_snapshots(results, merged):
    """Retain every real inference, not a new prediction on averaged inputs."""
    snapshots = [r.get('model_explanation') for r in results]
    present = [s for s in snapshots if isinstance(s, dict)]
    if not present:
        merged.pop('model_explanation', None)
        return
    snapshot = deepcopy(present[0])
    snapshot['samples'] = [deepcopy(sample) for s in present
                           for sample in s.get('samples', [])]
    versions = {s.get('model_version') for s in present}
    if len(present) != len(results) or len(versions) != 1:
        snapshot.update(status='unavailable', features=[],
                        reason='Some sampled predictions have missing or different model provenance.')
    snapshot['aggregation'] = (
        'The farm crop is selected by sample winner count, then average winner score. '
        'The displayed crop ranking comes from a recorded sample of that winner. '
        'Seasonal rules are applied afterwards. No model was run on the averaged land indicators.'
    )
    merged['model_explanation'] = snapshot
    merged['top_crop_recommendations'] = deepcopy(merged.get('top_crop_recommendations') or [])
    for crop in merged.get('top_crop_recommendations') or []:
        comparison = crop.get('condition_comparison')
        if isinstance(comparison, dict):
            comparison['scope'] = 'ranking_sample'
    merged['alternative_crops'] = merged['top_crop_recommendations'][1:]


def finalize_explanation(result):
    """Bind the stored explanation to the final output after seasonal ranking."""
    snapshot = result.get('model_explanation')
    if not isinstance(snapshot, dict):
        return result
    snapshot = deepcopy(snapshot)
    context_id = str(uuid.uuid4())
    result['prediction_context_id'] = context_id
    result['model_version'] = snapshot.get('model_version')
    snapshot['prediction_context_id'] = context_id
    snapshot['selected_output'] = result.get('predicted_crop')
    snapshot['selected_score'] = result.get('crop_compatibility_pct')
    snapshot['input_snapshot_hash'] = content_hash(snapshot.get('samples', []))
    snapshot['ranking'] = deepcopy(result.get('top_crop_recommendations') or [])
    result['model_explanation'] = snapshot
    return bind_local_explanation(result, snapshot, FEATURE_LABELS)
