"""Activate the owner-requested seven-crop raw-annual experiment, not validated training.

The original model and sidecars are backed up before activation. Source CSVs and
the archived training report/candidate are never rewritten or relabelled.
"""
import argparse
from copy import deepcopy
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import os

import joblib

BACKEND = Path(__file__).resolve().parents[1]
ROOT = BACKEND.parent
sys.path.insert(0, str(BACKEND))
from climate_contract import VERSION, PROTOTYPE_MODE, annual_prototype_policy
from model_artifacts import APPROVED_LABELS, FEATURES, load_model_artifact
from crop_requirements import annual_rainfall_references, slope_references, elevation_references

CANDIDATE = ROOT / 'research/seven-crop-candidates/20261103-seven-crops'
ASSETS = ('crop_model.pkl', 'crop_model_features.pkl', 'crop_model_metadata.json')
DATA_FILES = ('Crop_recommendation.csv', 'Crop_recommendation_with_gis.csv')


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def prototype_metadata(report):
    if set(report['classes']) != APPROVED_LABELS or report['feature_order'] != FEATURES:
        raise ValueError('Candidate must contain the exact seven crops and original feature order.')
    return {
        'schema_version': 1, 'model_version': report['model_version'],
        'model_type': 'RandomForestClassifier', 'feature_names': FEATURES,
        'classes': sorted(APPROVED_LABELS),
        'training': {
            'status': 'experimental_prototype', 'timestamp_utc': report['created_at_utc'],
            'random_seed': report['split']['seed'], 'script_sha256': report['script_sha256'],
            'dataset_sha256': report['data_audit']['source_sha256'],
            'provenance': {
                'source': report['source'], 'basis': 'Existing Kaggle-based augmented dataset; generated GIS and local crop profiles.',
                'climate_sources': {
                    'Crop_recommendation.csv': {'rainfall': None, 'temperature': None, 'humidity': None},
                    'LOCAL_CROP_PROFILES': {'rainfall': 'rolling_30_days', 'temperature': None, 'humidity': None}},
                'annual_input_compatibility': 'unverified',
                'nutrient_compatibility': 'Legacy proxy representation only; physical units/methods unverified. PAGRO data pending.',
                'field_validation': 'Not established',
                'source_limitations': deepcopy(report['promotion_blockers']),
            },
            'evaluation': {'basis': 'Legacy-data experiment; not annual or farm validation',
                           'holdout_rows': report['split']['holdout_rows'],
                           'comparison': deepcopy(report['comparison'])},
        },
        'runtime_input_policy': {
            'mode': PROTOTYPE_MODE, 'model_version': report['model_version'],
            'climate_contract_version': VERSION, 'annual_input_compatibility': 'unverified',
            'use_raw_annual_values': True, 'validation_claim': 'experimental_only',
            'legacy_nutrients': 'estimated_proxies_not_soil_tests',
            'owner_instruction_date': '2026-11-06',
            'basis': 'Owner explicitly requested activation of the existing seven-crop model using annual rainfall despite the unresolved training-period mismatch.',
        },
        'reference_requirements': annual_rainfall_references(),
        'slope_reference_requirements': slope_references(),
        'elevation_reference_requirements': elevation_references(),
    }


def activate():
    report = json.loads((CANDIDATE / 'training_report.json').read_text(encoding='utf-8'))
    model_path = CANDIDATE / 'crop_model.pkl'
    if digest(model_path) != report['model_version']:
        raise ValueError('Candidate bytes do not match the recorded training report.')
    source = ROOT / report['source'].replace('\\', '/')
    if digest(source) != report['data_audit']['source_sha256']:
        raise ValueError('Candidate source CSV changed; activation stopped.')
    model = joblib.load(model_path)
    if set(model.classes_) != APPROVED_LABELS or list(model.feature_names_in_) != FEATURES:
        raise ValueError('Actual estimator class/feature scope differs from the report.')
    metadata = prototype_metadata(report)
    before = {name: digest(BACKEND / name) for name in ASSETS}
    data_before = {name: digest(BACKEND / name) for name in DATA_FILES}
    current = load_model_artifact()
    if current.version == report['model_version'] and annual_prototype_policy(current.metadata, current.model.classes_):
        return {'activated': True, 'already_active': True, 'model_version': current.version,
                'class_count': len(current.model.classes_), 'validation_status': 'experimental_unvalidated'}
    # Validate the entire replacement before touching the current release.
    with tempfile.TemporaryDirectory(prefix='.annual-prototype-', dir=BACKEND) as directory:
        stage = Path(directory)
        (stage / 'crop_model.pkl').write_bytes(model_path.read_bytes())
        (stage / 'crop_model_features.pkl').write_bytes((CANDIDATE / 'crop_model_features.pkl').read_bytes())
        (stage / 'crop_model_metadata.json').write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
        staged = load_model_artifact(stage, expected_version=report['model_version'])
        if not annual_prototype_policy(staged.metadata, staged.model.classes_):
            raise ValueError('Staged model does not have the explicit experimental policy.')
        stamp = datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S-%f')
        evidence = ROOT / 'defense-evidence/seven-crop-activation' / stamp
        backup = evidence / 'before'
        backup.mkdir(parents=True)
        for name in ASSETS:
            (backup / name).write_bytes((BACKEND / name).read_bytes())
        replaced = []
        try:
            for name in ('crop_model_features.pkl', 'crop_model_metadata.json', 'crop_model.pkl'):
                os.replace(stage / name, BACKEND / name)
                replaced.append(name)
            fresh = load_model_artifact(expected_version=report['model_version'])
            if not annual_prototype_policy(fresh.metadata, fresh.model.classes_):
                raise ValueError('Activated model policy verification failed.')
        except Exception:
            for name in replaced:
                (BACKEND / name).write_bytes((backup / name).read_bytes())
            raise
    if data_before != {name: digest(BACKEND / name) for name in DATA_FILES}:
        raise ValueError('Source data changed during activation.')
    receipt = {'activated_at_utc': datetime.now(timezone.utc).isoformat(),
               'activated': True, 'model_version': fresh.version, 'class_count': len(fresh.model.classes_),
               'classes': list(map(str, fresh.model.classes_)), 'validation_status': 'experimental_unvalidated',
               'before': before, 'after': {name: digest(BACKEND / name) for name in ASSETS},
               'source_csv_hashes_unchanged': data_before,
               'backup': str(backup.relative_to(ROOT)), 'candidate': str(CANDIDATE.relative_to(ROOT)),
               'runtime_input_policy': metadata['runtime_input_policy'],
               'retraining_performed': False, 'deployment_performed': False}
    (evidence / 'activation.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    return {**receipt, 'evidence': str(evidence.relative_to(ROOT))}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--activate', action='store_true', required=True)
    parser.parse_args()
    print(json.dumps(activate(), indent=2))
