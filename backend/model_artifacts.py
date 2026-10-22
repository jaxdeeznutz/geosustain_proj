"""Artifact identity and validation shared by training, inference and deployment."""
from copy import deepcopy
from dataclasses import dataclass
import hashlib
import io
import json
import os
from pathlib import Path
import tempfile

import joblib
from sklearn.ensemble import RandomForestClassifier

BACKEND_DIR = Path(__file__).resolve().parent
FEATURES = ['N', 'P', 'K', 'temperature', 'humidity', 'ph', 'rainfall',
            'ndvi', 'elevation', 'slope']
APPROVED_LABELS = frozenset({
    'rice', 'maize', 'banana', 'coconut', 'abaca', 'cacao', 'durian',
    'cassava', 'sweet potato', 'rubber', 'pomelo', 'papaya', 'watermelon',
})
METADATA_FILE = 'crop_model_metadata.json'


class ModelArtifactError(ValueError):
    pass


def artifact_version(data):
    """SHA-256 of exact deployed pickle bytes, independent of file dates/paths."""
    return hashlib.sha256(data).hexdigest()


def validate_metadata(metadata, version, features, classes):
    if metadata.get('schema_version') != 1:
        raise ModelArtifactError('Unsupported model metadata schema.')
    if metadata.get('model_version') != version:
        raise ModelArtifactError('Model version metadata does not match artifact bytes.')
    if metadata.get('feature_names') != features:
        raise ModelArtifactError('Model metadata feature order mismatch.')
    if metadata.get('classes') != classes:
        raise ModelArtifactError('Model metadata classes mismatch.')
    if metadata.get('model_type') != 'RandomForestClassifier':
        raise ModelArtifactError('Production model must remain a RandomForestClassifier.')
    training = metadata.get('training')
    if not isinstance(training, dict) or training.get('status') not in ('recorded', 'legacy_unverified'):
        raise ModelArtifactError('Missing model training provenance status.')
    required = ('timestamp_utc', 'random_seed', 'script_sha256', 'dataset_sha256',
                'provenance', 'evaluation')
    if any(key not in training for key in required):
        raise ModelArtifactError('Incomplete model training metadata.')
    if training['status'] == 'recorded':
        if any(training[key] is None for key in required):
            raise ModelArtifactError('Recorded training metadata contains unknown fields.')
        if set(classes) != APPROVED_LABELS:
            raise ModelArtifactError('Trained classes differ from the approved crop list.')


@dataclass
class LoadedCropModel:
    model: object
    version: str
    metadata: dict
    directory: Path
    metadata_status: str

    def health(self):
        """Describe this process, comparing disk identity without hot reloading."""
        try:
            disk_version = artifact_version((self.directory / 'crop_model.pkl').read_bytes())
        except OSError:
            disk_version = None
        stale = disk_version != self.version
        classes = [str(c) for c in self.model.classes_]
        warnings = []
        if self.metadata_status != 'recorded':
            warnings.append('Legacy training timestamp, script identity and evaluation are unverified.')
        if set(classes) != APPROVED_LABELS:
            warnings.append('Legacy artifact classes differ from the current approved training list; ranking still filters to approved catalog crops.')
        return {
            'status': 'stale' if stale else 'loaded',
            'model_type': type(self.model).__name__, 'model_version': self.version,
            'artifact_version_on_disk': disk_version, 'restart_required': stale,
            'metadata_status': self.metadata_status,
            'feature_contract': {'names': list(self.model.feature_names_in_),
                                 'count': int(self.model.n_features_in_), 'order_required': True},
            'classes': classes, 'supported_classes': sorted(set(classes) & APPROVED_LABELS),
            'approved_classes': sorted(APPROVED_LABELS),
            'training': deepcopy(self.metadata.get('training')), 'warnings': warnings,
        }


def load_model_artifact(directory=BACKEND_DIR, *, expected_version=None, require_metadata=False):
    directory = Path(directory)
    data = (directory / 'crop_model.pkl').read_bytes()
    version = artifact_version(data)
    expected = expected_version or os.getenv('GEOSUSTAIN_EXPECTED_MODEL_VERSION')
    if expected and version != expected:
        raise ModelArtifactError('Loaded artifact differs from GEOSUSTAIN_EXPECTED_MODEL_VERSION.')
    model = joblib.load(io.BytesIO(data))
    if not isinstance(model, RandomForestClassifier):
        raise ModelArtifactError('Production model must remain a RandomForestClassifier.')
    names = list(model.feature_names_in_)
    if names != FEATURES or model.n_features_in_ != len(FEATURES):
        raise ModelArtifactError('Trained model feature order mismatch.')
    if joblib.load(directory / 'crop_model_features.pkl') != names:
        raise ModelArtifactError('Saved feature order mismatch.')
    path = directory / METADATA_FILE
    if not path.exists():
        if require_metadata:
            raise ModelArtifactError('Model version metadata is missing.')
        # Backwards compatible with old releases, visibly unverified, never invented.
        metadata, status = {}, 'missing_legacy'
    else:
        metadata = json.loads(path.read_text(encoding='utf-8'))
        validate_metadata(metadata, version, names, [str(c) for c in model.classes_])
        status = metadata['training']['status']
        if require_metadata and status != 'recorded':
            raise ModelArtifactError('Recorded training metadata is required; legacy metadata is unverified.')
    return LoadedCropModel(model, version, metadata, directory, status)


def save_training_artifact(model, features, training, comparison, augmented, directory=BACKEND_DIR):
    """Stage and load-verify a release before replacing assets; restart after publication.

    Version binds metadata to model bytes, so partial/mixed releases fail validation.
    """
    directory = Path(directory)
    with tempfile.TemporaryDirectory(prefix='.crop-training-', dir=directory) as temporary:
        stage = Path(temporary)
        joblib.dump(model, stage / 'crop_model.pkl')
        joblib.dump(features, stage / 'crop_model_features.pkl')
        version = artifact_version((stage / 'crop_model.pkl').read_bytes())
        metadata = {
            'schema_version': 1, 'model_version': version,
            'model_type': type(model).__name__, 'feature_names': features,
            'classes': [str(c) for c in model.classes_], 'training': training,
        }
        (stage / METADATA_FILE).write_text(json.dumps(metadata, indent=2, allow_nan=False) + '\n', encoding='utf-8')
        comparison = {**comparison, 'model_version': version}
        (stage / 'model_comparison_report.json').write_text(
            json.dumps(comparison, indent=2, allow_nan=False) + '\n', encoding='utf-8')
        augmented.to_csv(stage / 'Crop_recommendation_with_gis.csv', index=False)
        load_model_artifact(stage, expected_version=version, require_metadata=True)
        for filename in ('crop_model_features.pkl', 'Crop_recommendation_with_gis.csv',
                         'model_comparison_report.json', METADATA_FILE, 'crop_model.pkl'):
            os.replace(stage / filename, directory / filename)
    return metadata
