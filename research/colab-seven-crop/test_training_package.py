"""Software checks for the research notebook, not agricultural validation."""
import ast
import hashlib
import importlib.util
import json
from pathlib import Path

import joblib
import nbformat
import numpy as np
import pandas as pd
import pytest
from sklearn.metrics import accuracy_score

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('no_npk_training', HERE / 'train_without_npk.py')
training = importlib.util.module_from_spec(spec)
spec.loader.exec_module(training)


def test_clean_starter_notebook_has_valid_schema_parses_and_embeds_current_sources():
    notebook = nbformat.read(HERE / 'GeoSustain_Seven_Crops_No_NPK.ipynb', as_version=4)
    nbformat.validate(notebook)
    for cell in notebook.cells:
        if cell.cell_type == 'code':
            assert cell.execution_count is None and not cell.outputs
            ast.parse(cell.source)
    packaged = next(c.source for c in notebook.cells if 'DATASET_BASE64 =' in c.source)
    # Read only assignments; do not start training in a schema/source test.
    assignments = {n.targets[0].id: n.value for n in ast.parse(packaged).body
                   if isinstance(n, ast.Assign) and isinstance(n.targets[0], ast.Name)}
    source = ast.literal_eval(assignments['TRAINER_SOURCE'])
    assert source == (HERE / 'train_without_npk.py').read_text(encoding='utf-8')
    import base64
    assert base64.b64decode(ast.literal_eval(assignments['DATASET_BASE64'])) == (HERE / 'data/seven_crop_without_npk.csv').read_bytes()


def test_bundled_data_excludes_npk_and_preserves_explicit_generated_source_provenance():
    frame, manifest, audit = training.prepare_data(HERE / 'data/seven_crop_without_npk.csv', HERE / 'data/dataset_manifest.json')
    assert set(frame.label) == set(training.LABELS)
    assert not {'N', 'P', 'K'} & set(frame)
    assert audit['duplicate_rows_removed_before_split'] == 426
    assert audit['unique_rows'] == 1394
    assert audit['npk_used'] is False
    for crop in ['cacao', 'durian', 'rubber']:
        assert manifest['class_and_provenance_counts'][crop]['matches_original_kaggle_feature_row'] == 0
    train, holdout, cv, split = training.make_partitions(frame)
    assert not set(split.iloc[train].input_fingerprint) & set(split.iloc[holdout].input_fingerprint)
    assert set(split.iloc[train].label) == set(split.iloc[holdout].label) == set(training.LABELS)
    assert len(cv) == 5 and len(train) + len(holdout) == len(frame)


def mutated_data(tmp_path, mutation):
    frame = pd.read_csv(HERE / 'data/seven_crop_without_npk.csv')
    if mutation == 'npk': frame['N'] = 0
    elif mutation == 'nonfinite': frame.loc[0, 'rainfall'] = float('inf')
    elif mutation == 'missing_crop': frame = frame[frame.label != 'cacao']
    elif mutation == 'label_conflict':
        row = frame.iloc[0].copy(); row['label'] = 'cacao'; row['_record_id'] = 'conflict-source'
        frame = pd.concat([frame, row.to_frame().T], ignore_index=True)
    path = tmp_path / 'data.csv'; frame.to_csv(path, index=False)
    manifest = json.loads((HERE / 'data/dataset_manifest.json').read_text())
    manifest['dataset_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    m = tmp_path / 'manifest.json'; m.write_text(json.dumps(manifest))
    return path, m


@pytest.mark.parametrize('mutation,message', [('npk', 'NPK'), ('nonfinite', 'nonfinite'),
    ('missing_crop', 'seven approved'), ('label_conflict', 'conflicting')])
def test_invalid_inputs_are_rejected_instead_of_silently_filled_or_relabelled(tmp_path, mutation, message):
    with pytest.raises(ValueError, match=message): training.prepare_data(*mutated_data(tmp_path, mutation))


def test_changed_dataset_cannot_use_a_stale_manifest(tmp_path):
    path = tmp_path / 'changed.csv'
    path.write_bytes((HERE / 'data/seven_crop_without_npk.csv').read_bytes() + b'\n')
    with pytest.raises(ValueError, match='bytes differ'):
        training.prepare_data(path, HERE / 'data/dataset_manifest.json')


def test_trains_all_three_models_exports_replayable_predictions_and_selects_using_cv(tmp_path):
    output, archive, report = training.run_training(HERE / 'data/seven_crop_without_npk.csv',
        HERE / 'data/dataset_manifest.json', tmp_path / 'research', trees=3, cv_folds=2)
    predictions = pd.read_csv(output / 'holdout_predictions.csv')
    rows = pd.read_csv(output / 'training_rows_deduplicated.csv').set_index('_record_id')
    inputs = rows.loc[predictions['_record_id'], training.FEATURES]
    for row in report['comparison']:
        name = row['model']; model = joblib.load(output / f'{name}.joblib')
        np.testing.assert_array_equal(model.predict(inputs), predictions[name + '_prediction'])
        assert accuracy_score(predictions.label, predictions[name + '_prediction']) == row['holdout_accuracy']
    winner = sorted(report['comparison'], key=lambda row: (-row['cv_f1_macro_mean'], row['model']))[0]['model']
    assert report['selection']['selected_model'] == winner
    assert report['split']['test_set_used_for_selection'] is False
    assert report['execution_platform'] == 'local'
    assert report['application_integration_ready'] is False
    assert report['npk_used'] is False
    hashes = json.loads((output / 'artifact_hashes.json').read_text())
    assert all(training.file_hash(output / name) == digest for name, digest in hashes.items())
    assert archive.is_file() and (output / 'model_comparison.png').is_file()
    assert model.n_features_in_ == 7


def test_output_cannot_publish_into_backend(tmp_path):
    with pytest.raises(ValueError, match='cannot be written into backend'):
        training.run_training(HERE / 'data/seven_crop_without_npk.csv',
            HERE / 'data/dataset_manifest.json', tmp_path / 'backend', trees=1, cv_folds=2)
