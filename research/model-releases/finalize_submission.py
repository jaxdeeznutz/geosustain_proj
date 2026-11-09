"""Freeze the owner-selected model for submission without changing its claims.

Creates a portable, checksummed archive of existing artifacts and evaluation.
Does not train, change the active model, or promote agronomic validation status.
"""
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[2]
LABEL = 'GeoSustain_Model_Submission_v1_2026-11-08'
ACTIVE = ['crop_model.pkl', 'crop_model_features.pkl', 'crop_model_metadata.json']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def finalize():
    metadata = json.loads((ROOT / 'backend/crop_model_metadata.json').read_text())
    before = {name: sha(ROOT / 'backend' / name) for name in ACTIVE}
    receipt_path = Path(__file__).parent / 'submission-v1-2026-11-08' / 'release_receipt.json'
    if receipt_path.is_file():
        prior = json.loads(receipt_path.read_text(encoding='utf-8'))
        for name, expected in before.items():
            if prior['files'].get('model/' + name) != expected:
                raise ValueError('Submission v1 is already frozen. Create a separate release version for changed artifacts.')
        archive = Path(prior['archive'])
        if not archive.is_file() or sha(archive) != prior['archive_sha256']:
            raise ValueError('Frozen submission archive is missing or changed; restore its verified copy before proceeding.')
        return {'frozen': True, 'already_frozen': True, 'archive': str(archive),
                'model_unchanged': True, 'archive_verified': True,
                'model_version': metadata['model_version'], 'npk_used': False}
    if before['crop_model.pkl'] != metadata['model_version']:
        raise ValueError('Model identity does not match the recorded metadata.')
    if metadata['runtime_input_policy']['npk_used'] is not False:
        raise ValueError('This submission archive is for the selected no-NPK model.')
    run_id = metadata['training']['provenance']['colab_run_id']
    source = ROOT / 'research/colab-training-runs' / run_id
    if sha(source / 'input_dataset.csv') != metadata['training']['dataset_sha256']:
        raise ValueError('The source dataset differs from the trained model record.')
    original_hashes = json.loads((source / 'artifact_hashes.json').read_text())
    for name, expected in original_hashes.items():
        if Path(name).name != name or sha(source / name) != expected:
            raise ValueError(f'Received Colab artifact changed: {name}')
    if sha(source / 'random_forest.joblib') != before['crop_model.pkl']:
        raise ValueError('The installed forest differs from the selected Colab forest.')

    stage = ROOT / 'output' / LABEL
    stage.mkdir(parents=True, exist_ok=True)
    for name in ACTIVE:
        target = stage / 'model' / name
        target.parent.mkdir(exist_ok=True)
        shutil.copyfile(ROOT / 'backend' / name, target)
    for name in [*original_hashes, 'artifact_hashes.json']:
        target = stage / 'colab_run' / name
        target.parent.mkdir(exist_ok=True)
        shutil.copyfile(source / name, target)
    shutil.copyfile(ROOT / 'research/colab-seven-crop/requirements.txt', stage / 'requirements.txt')

    # This existing verifier exercises the real installed artifact, input order,
    # catalog and reconstruction of its signed local explanations, without APIs.
    sys.path.insert(0, str(ROOT / 'backend'))
    spec = importlib.util.spec_from_file_location('submission_model_verifier', ROOT / 'backend/training/verify_annual_prototype.py')
    verifier = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(verifier)
    verification = verifier.verify()
    verification['scope'] = 'Artifact/software consistency only; not independent field validation'
    (stage / 'artifact_verification.json').write_text(json.dumps(verification, indent=2) + '\n', encoding='utf-8')

    readme = '''GEOSUSTAIN - CURRENT SUBMISSION MODEL v1

This is the owner-selected version frozen for the present submission using the
available data. It preserves the exact model already used by the application.

Seven crop groups: Banana, Cacao, Coconut, Durian, Mango, Rice and Rubber.
Seven model inputs: temperature, humidity, pH, rainfall, NDVI, elevation, slope.
NPK is excluded. Banana varieties are reference guidance, not separate classes.

The model folder contains the exact active Random Forest and input-order file.
The colab_run folder preserves the received Decision Tree, SVM and Random Forest
models, original training code/data, splits, metrics, predictions and figures.
These are historical research-run records; their reported scores describe the
existing held-out dataset, not independently measured real-farm accuracy.

FINAL FOR THE CURRENT SUBMISSION SCOPE does not mean field validated. The source
data include generated crop/GIS profiles and unresolved climate input periods.
Annual-input prediction compatibility remains unverified. Model scores are not
harvest-success probabilities. These recorded limitations are retained.
The newer 2026 seasonal observations/outlooks are contextual updates; they have
not been inserted into the labelled training data in this archive.

LATER PAGRO NPK UPDATE - VERSION 2
1. Preserve this v1 archive before changing the model.
2. Check PAGRO dates, locations, soil sampling depths, laboratory methods, units
   and nutrient forms. Do not equate unlike units or nutrient definitions.
3. Link measurements to appropriate crop-labelled records and compatible
   environmental inputs. Unmatched soil records remain contextual evidence.
4. Train and compare the three algorithms with NPK included only when the
   matched training records support it; keep independent records for evaluation.
5. Recheck feature order, units, model identity, explanations and APK/web flows.
   Activate the new model as a separate version with rollback to v1 available.

Receiving NPK alone does not resolve annual-input compatibility, generated
training-data limitations, or independent farm-validation requirements.
'''
    (stage / 'README.txt').write_text(readme, encoding='utf-8')
    manifest = {
        'schema_version': 1,
        'release_name': LABEL,
        'release_status': 'frozen_for_current_submission_scope',
        'owner_decision': 'Use available data for the current version; consider a separately verified model update when PAGRO NPK arrives.',
        'created_at_utc': datetime.now(timezone.utc).isoformat(),
        'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'model_version': metadata['model_version'],
        'feature_names': metadata['feature_names'],
        'classes': metadata['classes'],
        'training_run_id': run_id,
        'npk_used': False,
        'training_status_retained': metadata['training']['status'],
        'annual_input_compatibility': metadata['runtime_input_policy']['annual_input_compatibility'],
        'agronomic_validation': 'not_established',
        'evaluation_scope': metadata['training']['evaluation']['basis'],
        'model_comparison': metadata['training']['evaluation']['comparison'],
        'active_model_modified': False,
        'training_performed_by_freeze': False,
        'npk_update_requires': ['Check sampling methods, units, dates and location',
                                'Matched crop-labelled training records',
                                'Retraining and model comparison',
                                'Input/XAI/workflow verification and a separate version'],
        'files': {str(p.relative_to(stage)).replace('\\', '/'): sha(p)
                  for p in sorted(stage.rglob('*')) if p.is_file() and p.name != 'release_manifest.json'},
    }
    (stage / 'release_manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    archive = ROOT.parent / (LABEL + '.zip')
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as bundle:
        for path in sorted(stage.rglob('*')):
            if path.is_file():
                bundle.write(path, str(path.relative_to(stage)).replace('\\', '/'))
    with zipfile.ZipFile(archive) as bundle:
        if bundle.testzip() is not None:
            raise ValueError('Archive integrity check failed.')
        for name, expected in manifest['files'].items():
            if hashlib.sha256(bundle.read(name)).hexdigest() != expected:
                raise ValueError(f'Archived file hash mismatch: {name}')
        for name, expected in before.items():
            if hashlib.sha256(bundle.read('model/' + name)).hexdigest() != expected:
                raise ValueError('The archived active artifact differs from the installed model.')
    after = {name: sha(ROOT / 'backend' / name) for name in ACTIVE}
    if before != after:
        raise ValueError('The active model was unexpectedly modified.')
    receipt = {**manifest, 'archive': str(archive), 'archive_bytes': archive.stat().st_size,
               'archive_sha256': sha(archive), 'archive_verified': True,
               'artifact_verification': verification}
    receipt_path.parent.mkdir(exist_ok=True)
    receipt_path.write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    return {'frozen': True, 'archive': str(archive), 'model_unchanged': before == after,
            'release_status': manifest['release_status'], 'model_version': metadata['model_version'],
            'npk_used': False, 'annual_training_validated': False,
            'receipt': str(receipt_path), 'archive_verified': True}


if __name__ == '__main__':
    print(json.dumps(finalize(), indent=2))
