"""Package/software checks; these are not the user's reported Colab experiment."""
import ast
import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import zipfile

import joblib
import nbformat
import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
spec = importlib.util.spec_from_file_location('rf_training', HERE / 'train_random_forest.py')
trainer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(trainer)


def test_rf_only_sources_and_active_baseline_identity():
    source = (HERE / 'train_random_forest.py').read_text(encoding='utf-8')
    assert 'DecisionTreeClassifier' not in source and 'SVC' not in source
    imports = [n.module for n in ast.walk(ast.parse(source)) if isinstance(n, ast.ImportFrom)]
    assert 'sklearn.svm' not in imports and 'sklearn.tree' not in imports
    model = joblib.load(ROOT / 'backend/crop_model.pkl')
    reference = json.loads((HERE / 'current_model_reference.json').read_text())
    assert reference['installed_artifact_sha256'] == trainer.file_hash(ROOT / 'backend/crop_model.pkl')
    assert reference['dataset_sha256'] == trainer.file_hash(HERE / 'seven_crop_without_npk.csv')
    assert reference['feature_order'] == trainer.FEATURES
    assert reference['crop_classes'] == list(model.classes_) == trainer.LABELS
    assert all(model.get_params()[key] == value for key, value in reference['baseline_parameters'].items())


def test_unexecuted_colab_defaults_to_na_and_does_not_fit(monkeypatch, tmp_path):
    notebook = nbformat.read(HERE / 'GeoSustain_Random_Forest_Seven_Crops.ipynb', as_version=4)
    nbformat.validate(notebook)
    for cell in notebook.cells:
        if cell.cell_type == 'code':
            assert cell.execution_count is None and cell.outputs == []
            ast.parse(cell.source)
    restoration = next(cell.source for cell in notebook.cells if 'DATASET_BASE64 =' in cell.source)
    assignments = {node.targets[0].id: node.value for node in ast.parse(restoration).body
                   if isinstance(node, ast.Assign) and isinstance(node.targets[0], ast.Name)}
    assert ast.literal_eval(assignments['TRAINER_SOURCE']) == (HERE / 'train_random_forest.py').read_text(encoding='utf-8')
    assert base64.b64decode(ast.literal_eval(assignments['DATASET_BASE64'])) == (HERE / 'seven_crop_without_npk.csv').read_bytes()
    monkeypatch.chdir(tmp_path)
    def forbidden_fit(*args, **kwargs):
        raise AssertionError('Chapter 2 N/A mode must not train.')
    monkeypatch.setattr(RandomForestClassifier, 'fit', forbidden_fit)
    environment = {}
    for cell in notebook.cells:
        if cell.cell_type == 'code':
            exec(compile(cell.source, '<rf-notebook-qa>', 'exec'), environment)
    assert environment['RUN_TRAINING'] is False
    assert environment['run'] is None and environment['results_zip'] is None
    assert not list(tmp_path.rglob('metrics.csv'))
    assert not list(tmp_path.rglob('*.joblib'))


def test_real_training_outputs_replay_with_one_estimator(tmp_path):
    output, archive, run = trainer.run_training(HERE / 'seven_crop_without_npk.csv',
        HERE / 'dataset_manifest.json', HERE / 'current_model_reference.json',
        tmp_path / 'software-qa', trees=3, cv_folds=2, researcher='Local software test only')
    assert run['algorithm'] == 'Random Forest'
    assert run['hyperparameters']['n_estimators'] == 3
    assert run['execution_platform_reported'] == 'local'
    assert run['production_model_changed'] is False
    assert run['data_audit']['unique_rows'] == 1394
    assert run['data_audit']['duplicate_rows_removed_before_split'] == 426
    assert run['split']['test_used_for_selection'] is False
    assert len(list(output.glob('*.joblib'))) == 1
    predictions = pd.read_csv(output / 'holdout_predictions.csv')
    rows = pd.read_csv(output / 'training_rows_deduplicated.csv').set_index('_record_id')
    x_test = rows.loc[predictions['_record_id'], trainer.FEATURES]
    model = joblib.load(output / 'random_forest.joblib')
    np.testing.assert_array_equal(model.predict(x_test), predictions.predicted_crop)
    assert accuracy_score(predictions.label, predictions.predicted_crop) == run['metrics']['holdout_accuracy']
    split = pd.read_csv(output / 'split_manifest.csv')
    assert not set(split[split.partition == 'train'].input_fingerprint) & set(split[split.partition == 'holdout'].input_fingerprint)
    hashes = json.loads((output / 'artifact_hashes.json').read_text())
    assert all(trainer.file_hash(output / name) == value for name, value in hashes.items())
    with zipfile.ZipFile(archive) as zipped:
        assert zipped.testzip() is None
    assert (output / 'confusion_matrix.png').is_file()
