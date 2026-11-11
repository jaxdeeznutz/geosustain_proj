"""Install the verified owner Colab RF as a seven-input experimental model.

Backs up all active assets, validates before publication, retains exact model
bytes and never edits source datasets or claims annual/field validation.
"""
import argparse
from copy import deepcopy
from datetime import datetime, timezone
import hashlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile

import joblib
import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score, f1_score

BACKEND = Path(__file__).resolve().parents[1]
ROOT = BACKEND.parent
sys.path.insert(0, str(BACKEND))
from climate_contract import VERSION, NO_NPK_PROTOTYPE_MODE, annual_prototype_policy
from crop_requirements import annual_rainfall_references, slope_references, elevation_references
from model_artifacts import ENVIRONMENTAL_FEATURES, APPROVED_LABELS, load_model_artifact

RUN_ID = '20261106T080700Z-3adeb48c'
MODEL_VERSION = '6cefb5545173c05521a5c1fe71e5cb654b2a17161a1e1399d88f93afa867c8cd'
DATASET_HASH = 'bfd1f5b9c2a1b745b62f93f16e95464f3d2bb7e81f4bbaeb3621a986c134c3c1'
CANDIDATE = ROOT / 'research/colab-training-runs' / RUN_ID
ASSETS = ('crop_model.pkl', 'crop_model_features.pkl', 'crop_model_metadata.json')
DATA_FILES = ('Crop_recommendation.csv', 'Crop_recommendation_with_gis.csv')


def digest(path):
    path = Path(path)
    raw = path.read_bytes()
    # Colab records LF text; Git on Windows may check that same text out as
    # CRLF. Canonicalize text line endings only; binary model bytes stay exact.
    if path.suffix.lower() in ('.csv', '.json', '.txt', '.py'):
        raw = raw.replace(b'\r\n', b'\n')
    return hashlib.sha256(raw).hexdigest()


def validate_candidate(directory=CANDIDATE):
    directory = Path(directory)
    report = json.loads((directory / 'training_run.json').read_text())
    hashes = json.loads((directory / 'artifact_hashes.json').read_text())
    if len(hashes) != 26 or any(Path(n).name != n or digest(directory / n) != h for n, h in hashes.items()):
        raise ValueError('Colab artifact hashes do not match the preserved run.')
    if (report['run_id'] != RUN_ID or report['features'] != ENVIRONMENTAL_FEATURES
            or set(report['classes']) != APPROVED_LABELS or report['npk_used'] is not False
            or report['selection']['selected_model'] != 'random_forest'
            or report['split']['test_set_used_for_selection'] is not False):
        raise ValueError('Unexpected Colab run, feature scope, class scope or selection method.')
    if digest(directory / 'random_forest.joblib') != MODEL_VERSION or digest(directory / 'input_dataset.csv') != DATASET_HASH:
        raise ValueError('Candidate differs from the exact verified Colab model/dataset.')
    model = joblib.load(directory / 'random_forest.joblib')
    if (not isinstance(model, RandomForestClassifier)
            or list(model.feature_names_in_) != ENVIRONMENTAL_FEATURES
            or set(model.classes_) != APPROVED_LABELS):
        raise ValueError('Estimator feature or class contract differs from the report.')
    rows = pd.read_csv(directory / 'training_rows_deduplicated.csv').set_index('_record_id')
    predictions = pd.read_csv(directory / 'holdout_predictions.csv')
    test = rows.loc[predictions['_record_id'], ENVIRONMENTAL_FEATURES]
    actual = model.predict(test)
    np.testing.assert_array_equal(actual, predictions.random_forest_prediction)
    measured = next(item for item in report['comparison'] if item['model'] == 'random_forest')
    if (accuracy_score(predictions.label, actual) != measured['holdout_accuracy']
            or f1_score(predictions.label, actual, average='macro') != measured['holdout_f1_macro']):
        raise ValueError('Colab held-out metrics do not replay.')
    winner = sorted(report['comparison'], key=lambda row: (-row['cv_f1_macro_mean'], row['model']))[0]['model']
    if winner != 'random_forest':
        raise ValueError('Random Forest was not selected by the recorded training-only CV rule.')
    return report


def prototype_metadata(report):
    return {
        'schema_version': 1, 'model_version': MODEL_VERSION, 'model_type': 'RandomForestClassifier',
        'feature_names': ENVIRONMENTAL_FEATURES, 'classes': sorted(APPROVED_LABELS),
        'training': {'status': 'experimental_prototype', 'timestamp_utc': report['finished_at_utc'],
            'random_seed': report['split']['seed'], 'script_sha256': report['training_script_sha256'],
            'dataset_sha256': DATASET_HASH,
            'provenance': {'source': f'research/colab-training-runs/{RUN_ID}/input_dataset.csv',
                'colab_run_id': RUN_ID, 'execution_platform_reported': report['execution_platform'],
                'basis': 'Owner Colab run; existing Kaggle-based augmented rows and generated crop/GIS profiles; NPK excluded.',
                'climate_sources': {'original_kaggle_rows': {'rainfall': None, 'temperature': None, 'humidity': None},
                    'legacy_profile_rows': {'rainfall': 'rolling_30_days', 'temperature': None, 'humidity': None}},
                'annual_input_compatibility': 'unverified', 'npk_used': False,
                'field_validation': 'Not established', 'source_limitations': deepcopy(report['limitations'])},
            'evaluation': {'basis': 'Held-out legacy augmented rows without NPK; not annual-input or farm accuracy',
                'holdout_rows': report['split']['holdout_rows'], 'train_rows': report['split']['train_rows'],
                'comparison': deepcopy(report['comparison']), 'selection': deepcopy(report['selection'])}},
        'runtime_input_policy': {'mode': NO_NPK_PROTOTYPE_MODE, 'model_version': MODEL_VERSION,
            'climate_contract_version': VERSION, 'feature_order': ENVIRONMENTAL_FEATURES, 'npk_used': False,
            'annual_input_compatibility': 'unverified', 'use_raw_annual_values': True,
            'validation_claim': 'experimental_only', 'owner_instruction_date': '2026-11-06',
            'basis': 'Owner requested integration of the verified Colab model while PAGRO NPK remains pending.'},
        'reference_requirements': annual_rainfall_references(),
        'slope_reference_requirements': slope_references(),
        'elevation_reference_requirements': elevation_references(),
    }


def activate():
    report = validate_candidate()
    metadata = prototype_metadata(report)
    before = {name: digest(BACKEND / name) for name in ASSETS}
    data_before = {name: digest(BACKEND / name) for name in DATA_FILES}
    if before['crop_model.pkl'] == MODEL_VERSION:
        current = load_model_artifact(expected_version=MODEL_VERSION)
        if current.metadata != metadata:
            raise ValueError('This model is active with different metadata; review before replacing it.')
        return {'activated': True, 'already_active': True, 'model_version': MODEL_VERSION}
    with tempfile.TemporaryDirectory(prefix='.colab-no-npk-', dir=BACKEND) as temp:
        stage = Path(temp)
        (stage / 'crop_model.pkl').write_bytes((CANDIDATE / 'random_forest.joblib').read_bytes())
        joblib.dump(ENVIRONMENTAL_FEATURES, stage / 'crop_model_features.pkl')
        (stage / 'crop_model_metadata.json').write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
        staged = load_model_artifact(stage, expected_version=MODEL_VERSION)
        assert annual_prototype_policy(staged.metadata, staged.model.classes_)
        evidence = ROOT / 'defense-evidence/no-npk-integration' / datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S-%f')
        backup = evidence / 'before'; backup.mkdir(parents=True)
        for name in ASSETS: (backup / name).write_bytes((BACKEND / name).read_bytes())
        replaced = []
        try:
            for name in ('crop_model_features.pkl', 'crop_model_metadata.json', 'crop_model.pkl'):
                os.replace(stage / name, BACKEND / name); replaced.append(name)
            fresh = load_model_artifact(expected_version=MODEL_VERSION)
            assert annual_prototype_policy(fresh.metadata, fresh.model.classes_)
            assert data_before == {name: digest(BACKEND / name) for name in DATA_FILES}
        except Exception:
            for name in replaced: (BACKEND / name).write_bytes((backup / name).read_bytes())
            raise
    receipt = {'activated': True, 'activated_at_utc': datetime.now(timezone.utc).isoformat(),
        'model_version': MODEL_VERSION, 'features': ENVIRONMENTAL_FEATURES, 'npk_used': False,
        'validation_status': 'experimental_unvalidated', 'before': before,
        'after': {name: digest(BACKEND / name) for name in ASSETS},
        'source_csvs_unchanged': data_before, 'backup': str(backup.relative_to(ROOT)),
        'colab_run': RUN_ID, 'retraining_performed': False, 'remote_deployment_performed': False}
    (evidence / 'activation.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    return {**receipt, 'evidence': str(evidence.relative_to(ROOT))}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--activate', action='store_true', required=True)
    parser.parse_args()
    print(json.dumps(activate(), indent=2))
