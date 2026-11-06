"""Replay a trusted local migration candidate without approving production use."""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import sys

import joblib
import numpy as np
import pandas as pd
from sklearn.metrics import accuracy_score, confusion_matrix

BACKEND = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))
from model_artifacts import APPROVED_LABELS, FEATURES, artifact_version
from model_explainability import FEATURE_LABELS
from local_attribution import aggregate_hash, bind_local_explanation
from training.train_seven_crop_candidate import OUTPUT_ROOT, prepare_data


def require(condition, message):
    if not condition:
        raise ValueError(message)


def verify(directory):
    directory = Path(directory).resolve()
    require(directory.is_relative_to(OUTPUT_ROOT.resolve()), 'Only trusted local research candidates are accepted.')
    report = json.loads((directory / 'training_report.json').read_text(encoding='utf-8'))
    metadata = json.loads((directory / 'crop_model_metadata.json').read_text(encoding='utf-8'))
    payload = (directory / 'crop_model.pkl').read_bytes()
    version = artifact_version(payload)
    require(version == report['model_version'] == metadata['model_version'], 'Candidate artifact identity mismatch.')
    require(report['production_promotion_allowed'] is False and
            metadata['training']['status'] == 'candidate_unvalidated', 'Candidate cannot claim production approval.')
    require(set(report['classes']) == set(metadata['classes']) == APPROVED_LABELS,
            'Candidate classes must exactly match the seven-crop catalog.')
    require(report['feature_order'] == FEATURES == metadata['feature_names'], 'Feature order mismatch.')
    repo = BACKEND.parent
    # Hashes must include each protected production file; they cannot be omitted.
    from training.train_seven_crop_candidate import protected_hashes
    normalize = lambda values: {key.replace('\\', '/'): value for key, value in values.items()}
    current = normalize(protected_hashes())
    original = normalize(report['protected_production_hashes'])
    contract_path = 'backend/training/climate_training_contract.py'
    require({k: v for k, v in current.items() if k != contract_path} ==
            {k: v for k, v in original.items() if k != contract_path}, 'Protected production data/model files changed.')
    contract_changed = current.get(contract_path) != original.get(contract_path)
    source = repo / report['source'].replace('\\', '/')
    frame, audit = prepare_data(source)
    require(audit == report['data_audit'], 'Dataset bytes or preparation results changed.')
    model = joblib.load(directory / 'crop_model.pkl')
    require(set(model.classes_) == APPROVED_LABELS and list(model.feature_names_in_) == FEATURES,
            'Actual estimator class/feature scope differs from metadata.')
    require(joblib.load(directory / 'crop_model_features.pkl') == FEATURES, 'Features sidecar mismatch.')
    train, holdout = report['split']['train'], report['split']['holdout']
    require(len(set(train)) == len(train) and len(set(holdout)) == len(holdout)
            and not set(train) & set(holdout) and set(train + holdout) == set(range(len(frame))),
            'Holdout partitions are incomplete or overlap.')
    keys = pd.util.hash_pandas_object(frame[FEATURES], index=False).astype(str)
    require(not set(keys.iloc[train]) & set(keys.iloc[holdout]), 'Duplicate feature rows cross the holdout.')
    predictions = model.predict(frame.iloc[holdout][FEATURES])
    expected = report['comparison']['random_forest']
    require(accuracy_score(frame.iloc[holdout].label, predictions) == expected['accuracy'], 'Holdout accuracy does not replay.')
    require(confusion_matrix(frame.iloc[holdout].label, predictions, labels=sorted(APPROVED_LABELS)).tolist()
            == expected['confusion_matrix'], 'Holdout confusion matrix does not replay.')
    record = json.loads((directory / 'synthetic_source_explanation.json').read_text(encoding='utf-8'))
    local = record['local_model_explanation']
    require(local['status'] == 'available' and set(local['class_order']) == APPROVED_LABELS,
            'Saved seven-crop explanation is unavailable.')
    require(local['snapshot_hash'] == aggregate_hash(local), 'Saved attribution checksum mismatch.')
    rebound = bind_local_explanation(deepcopy(record), record['model_explanation'], FEATURE_LABELS)
    require(rebound['local_model_explanation'] == local, 'Saved explanation cannot be verified against its samples.')
    for sample in record['model_explanation']['samples']:
        data = pd.DataFrame([sample['inputs']], columns=FEATURES)
        expected_scores = [sample['class_probabilities'][str(label)] for label in model.classes_]
        np.testing.assert_allclose(model.predict_proba(data)[0], expected_scores, rtol=0, atol=1e-12)
    result = {'candidate_verified': True, 'model_version': version, 'class_count': 7,
        'holdout_accuracy_replayed': expected['accuracy'], 'saved_explanation_verified': True,
        'production_artifacts_unchanged': True, 'production_promotion_allowed': False,
        'training_contract_changed_since_run': contract_changed,
        'annual_training_compatibility': 'unverified; this saved experiment is not an annual-trained release'}
    print(json.dumps(result, indent=2))
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    verify(parser.parse_args().directory)
