"""Verify the generated portable notebook, input data and source hashes offline."""
import ast
import base64
import hashlib
import io
import json
from pathlib import Path
import zipfile
import nbformat

ROOT = Path(__file__).resolve().parents[2]
NAME = 'GeoSustain_Current_Model_Training_2026-11-07'


def verify():
    location = ROOT.parent
    notebook = nbformat.read(location / (NAME + '.ipynb'), as_version=4)
    nbformat.validate(notebook)
    for cell in notebook.cells:
        if cell.cell_type == 'code':
            assert cell.execution_count is None and not cell.outputs
            ast.parse(cell.source)
    cell = next(c for c in notebook.cells if c.cell_type == 'code' and 'CURRENT_PACKAGE_BASE64 =' in c.source)
    embedded = next(ast.literal_eval(n.value) for n in ast.parse(cell.source).body
                    if isinstance(n, ast.Assign) and isinstance(n.targets[0], ast.Name)
                    and n.targets[0].id == 'CURRENT_PACKAGE_BASE64')
    with zipfile.ZipFile(location / (NAME + '.zip')) as archive:
        prefix = NAME + '/'
        manifest = json.loads(archive.read(prefix + 'package_manifest.json'))
        for name, digest in manifest['files_sha256'].items():
            assert hashlib.sha256(archive.read(prefix + name)).hexdigest() == digest, name
        contract = manifest['contract']
        assert len(contract['features']) == len(contract['classes']) == 7
        assert not contract['npk_used'] and not contract['automatic_model_activation']
        assert not contract['banana_variety_prediction_classes']
        assert contract['training_dataset_sha256'] == hashlib.sha256(archive.read(prefix + 'data/seven_crop_without_npk.csv')).hexdigest()
        with zipfile.ZipFile(io.BytesIO(base64.b64decode(embedded))) as materials:
            assert materials.read('data/seven_crop_without_npk.csv') == archive.read(prefix + 'data/seven_crop_without_npk.csv')
            pilot = json.loads(materials.read('supplemental_NOT_TRAINING/environmental-pilot.json'))
            assert not pilot['model_training_ready'] and not pilot['psa_joined']
            for name, digest in pilot['raw_file_sha256'].items():
                assert hashlib.sha256(materials.read('supplemental_NOT_TRAINING/' + name)).hexdigest() == digest
            audit = json.loads(materials.read('banana_varieties/old_variety_handling_audit.json'))
            assert audit['old_display_mapping']['banana'] == 'Banana (Cavendish/Lakatan)'
            assert audit['old_display_mapping']['muskmelon'] == 'Banana (Saba)'
            assert not audit['separate_cavendish_lakatan_saba_trained_classes_present']
            ready = json.loads(materials.read('banana_varieties/readiness.json'))
            assert ready['variety_counts'] == {'cavendish':0,'lakatan':0,'saba':0}
            assert not ready['training_ready'] and not ready['varieties_trained']
            partial = json.loads(materials.read('banana_varieties/published_trial_observations_partial.json'))
            assert partial['record_count'] == 3 and partial['independent_sites'] == 2
            assert partial['complete_model_training_rows'] == 0 and not partial['used_for_fitting']
            assert ready['published_partial_trial_records'] == 3
        assignments = next(c for c in notebook.cells if c.cell_type == 'code' and 'DATASET_BASE64 =' in c.source)
        nodes = {n.targets[0].id: n.value for n in ast.parse(assignments.source).body if isinstance(n, ast.Assign) and isinstance(n.targets[0], ast.Name)}
        assert base64.b64decode(ast.literal_eval(nodes['DATASET_BASE64'])) == archive.read(prefix + 'data/seven_crop_without_npk.csv')
        assert ast.literal_eval(nodes['TRAINER_SOURCE']).encode('utf-8') == archive.read(prefix + 'train_without_npk.py')
    print('PASS: notebook schema, blank outputs, executable syntax, embedded trainer/data, seven classes/features, all package/provider hashes, and unmatched-data exclusion.')


if __name__ == '__main__':
    verify()
