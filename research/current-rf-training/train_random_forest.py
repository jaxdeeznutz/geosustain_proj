"""Random Forest only, seven crop classes, no NPK. Research outputs only."""
from datetime import datetime, timezone
import hashlib
import io
import json
from pathlib import Path
import platform
from time import perf_counter
import uuid
import zipfile
import joblib
import numpy as np
import pandas as pd
import sklearn
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score, classification_report, confusion_matrix
from sklearn.model_selection import StratifiedKFold, cross_validate, train_test_split

FEATURES = ['temperature', 'humidity', 'ph', 'rainfall', 'ndvi', 'elevation', 'slope']
LABELS = ['banana', 'cacao', 'coconut', 'durian', 'mango', 'rice', 'rubber']


def file_hash(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_json(path, value):
    Path(path).write_text(json.dumps(value, indent=2, allow_nan=False) + '\n', encoding='utf-8')


def prepare_data(dataset, manifest_path):
    raw = Path(dataset).read_bytes()
    manifest = json.loads(Path(manifest_path).read_text(encoding='utf-8'))
    if manifest.get('dataset_sha256') != hashlib.sha256(raw).hexdigest():
        raise ValueError('Dataset bytes differ from the bundled provenance manifest. Review and document a new dataset before training.')
    if manifest.get('feature_order') != FEATURES or manifest.get('classes') != LABELS:
        raise ValueError('Expected the documented seven-input, seven-crop, no-NPK experiment.')
    frame = pd.read_csv(io.BytesIO(raw), dtype={'_record_id': str, '_source_basis': str})
    if not set(FEATURES + ['label', '_record_id', '_source_basis']) <= set(frame):
        raise ValueError('CSV is missing documented predictors, label or source identifiers.')
    if {'N', 'P', 'K'} & set(frame):
        raise ValueError('NPK columns are excluded from this experiment, not replaced with zeros or guessed values.')
    if not 70 <= len(frame) <= 100000:
        raise ValueError('Expected 70–100,000 source rows.')
    for key in ['label', '_record_id', '_source_basis']:
        if frame[key].isna().any() or frame[key].astype(str).str.strip().eq('').any():
            raise ValueError(f'Missing {key}; source rows are not silently filled.')
    if frame['_record_id'].duplicated().any():
        raise ValueError('Source record identifiers must be unique.')
    frame['label'] = frame.label.astype(str).str.strip().str.lower()
    if set(frame.label) != set(LABELS):
        raise ValueError('Existing labelled rows must cover exactly the seven approved crops.')
    if any(pd.api.types.is_bool_dtype(frame[key]) for key in FEATURES):
        raise ValueError('Boolean predictors are not numeric measurements.')
    frame[FEATURES] = frame[FEATURES].apply(pd.to_numeric, errors='raise')
    if not np.isfinite(frame[FEATURES].to_numpy(dtype=float)).all():
        raise ValueError('Missing/nonfinite values need source review; no imputation is performed.')
    if frame.groupby(FEATURES, dropna=False).label.nunique().gt(1).any():
        raise ValueError('Identical predictors have conflicting crop labels; resolve those records before training.')
    source_count = len(frame)
    frame = frame.drop_duplicates(FEATURES + ['label']).reset_index(drop=True)
    if frame.label.value_counts().min() < 10:
        raise ValueError('Every crop needs at least ten distinct labelled input rows.')
    audit = {'dataset_sha256': hashlib.sha256(raw).hexdigest(), 'input_rows': source_count,
        'duplicate_rows_removed_before_split': source_count - len(frame), 'unique_rows': len(frame),
        'class_counts': {k: int(v) for k, v in frame.label.value_counts().sort_index().items()},
        'source_basis_counts': {k: int(v) for k, v in frame['_source_basis'].value_counts().items()},
        'rows_generated_this_run': 0, 'period_conversion': 'none', 'npk_used': False,
        'independent_farm_groups': 'unknown; row-level experiment only'}
    return frame, manifest, audit


def make_partitions(frame, seed=42, cv_folds=5):
    if type(seed) is not int or not 0 <= seed < 2**32:
        raise ValueError('Seed must be an unsigned 32-bit integer.')
    if type(cv_folds) is not int or not 2 <= cv_folds <= 10:
        raise ValueError('Cross-validation folds must be 2–10.')
    train, holdout = train_test_split(np.arange(len(frame)), test_size=.2,
        stratify=frame.label, random_state=seed)
    if frame.iloc[train].label.value_counts().min() < cv_folds:
        raise ValueError('Not enough training rows per crop for the requested CV folds.')
    keys = pd.util.hash_pandas_object(frame[FEATURES], index=False).astype(str)
    assert not set(keys.iloc[train]) & set(keys.iloc[holdout])
    cv = list(StratifiedKFold(n_splits=cv_folds, shuffle=True, random_state=seed + 1)
              .split(frame.iloc[train][FEATURES], frame.iloc[train].label))
    assignments = {}
    for fold, (a, b) in enumerate(cv):
        assert not set(keys.iloc[train[a]]) & set(keys.iloc[train[b]])
        for j in train[b]: assignments[int(j)] = fold
    split = frame[['_record_id', 'label', '_source_basis']].copy()
    split['partition'] = ['train' if i in set(train.tolist()) else 'holdout' for i in range(len(frame))]
    split['cv_validation_fold'] = [assignments.get(i) for i in range(len(frame))]
    split['input_fingerprint'] = keys
    return train, holdout, cv, split


def run_training(dataset, manifest_path, reference_path, output_parent, *, seed=42,
                 trees=500, cv_folds=5, execution_platform='local', researcher='Not supplied'):
    """Fit one predefined RF on training rows; score an untouched test partition."""
    if type(trees) is not int or not 1 <= trees <= 1000:
        raise ValueError('Tree count must be 1-1000.')
    frame, manifest, audit = prepare_data(dataset, manifest_path)
    reference = json.loads(Path(reference_path).read_text(encoding='utf-8'))
    if reference['dataset_sha256'] != audit['dataset_sha256'] or reference['feature_order'] != FEATURES:
        raise ValueError('Dataset/input contract differs from the baseline reference.')
    train, holdout, cv, split = make_partitions(frame, seed, cv_folds)
    started = datetime.now(timezone.utc)
    run_id = started.strftime('%Y%m%dT%H%M%SZ') + '-' + uuid.uuid4().hex[:8]
    output = Path(output_parent) / run_id
    if any(part.lower() == 'backend' for part in output.resolve().parts):
        raise ValueError('Research outputs cannot be written into backend/.')
    output.mkdir(parents=True, exist_ok=False)
    x_train, y_train = frame.iloc[train][FEATURES], frame.iloc[train].label
    x_test, y_test = frame.iloc[holdout][FEATURES], frame.iloc[holdout].label
    model = RandomForestClassifier(n_estimators=trees, max_depth=14, min_samples_leaf=6,
        min_samples_split=12, max_features='sqrt', class_weight='balanced_subsample',
        random_state=seed, n_jobs=1)
    scoring = {key: key for key in ['accuracy', 'precision_macro', 'recall_macro', 'f1_macro']}
    print(f'Random Forest: {cv_folds} training-only cross-validation folds', flush=True)
    scores = cross_validate(model, x_train, y_train, cv=cv, scoring=scoring,
                            n_jobs=1, error_score='raise', return_train_score=False)
    cv_rows = [{'fold': fold + 1, **{key: float(scores['test_' + key][fold]) for key in scoring}}
               for fold in range(cv_folds)]
    tick = perf_counter()
    model.fit(x_train, y_train)
    fit_seconds = perf_counter() - tick
    prediction = model.predict(x_test)
    report = classification_report(y_test, prediction, labels=LABELS, output_dict=True, zero_division=0)
    matrix = confusion_matrix(y_test, prediction, labels=LABELS)
    metrics = {'algorithm': 'Random Forest', 'holdout_accuracy': float(accuracy_score(y_test, prediction)),
        'holdout_precision_macro': float(report['macro avg']['precision']),
        'holdout_recall_macro': float(report['macro avg']['recall']),
        'holdout_f1_macro': float(report['macro avg']['f1-score']),
        'holdout_f1_weighted': float(report['weighted avg']['f1-score']),
        **{f'cv_{key}_mean': float(scores['test_' + key].mean()) for key in scoring}}
    pd.DataFrame([metrics]).to_csv(output / 'metrics.csv', index=False)
    pd.DataFrame(report).T.to_csv(output / 'classification_report.csv')
    pd.DataFrame(matrix, index=LABELS, columns=LABELS).to_csv(output / 'confusion_matrix.csv', index_label='actual_crop')
    pd.DataFrame(cv_rows).to_csv(output / 'cross_validation.csv', index=False)
    split.to_csv(output / 'split_manifest.csv', index=False)
    frame.to_csv(output / 'training_rows_deduplicated.csv', index=False)
    predictions = frame.iloc[holdout][['_record_id', 'label', '_source_basis']].copy()
    predictions['predicted_crop'] = prediction
    for index, crop in enumerate(model.classes_):
        predictions['probability_' + crop] = model.predict_proba(x_test)[:, index]
    predictions.to_csv(output / 'holdout_predictions.csv', index=False)
    joblib.dump(model, output / 'random_forest.joblib')
    restored = joblib.load(output / 'random_forest.joblib')
    np.testing.assert_array_equal(restored.predict(x_test), prediction)
    np.testing.assert_allclose(restored.predict_proba(x_test), model.predict_proba(x_test), rtol=0, atol=0)
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    from sklearn.metrics import ConfusionMatrixDisplay
    fig, ax = plt.subplots(figsize=(8, 7))
    ConfusionMatrixDisplay(matrix, display_labels=LABELS).plot(ax=ax, xticks_rotation=45, cmap='Greens', colorbar=False)
    ax.set_title('Random Forest: held-out dataset rows')
    fig.tight_layout(); fig.savefig(output / 'confusion_matrix.png', dpi=160); plt.close(fig)
    pd.DataFrame({'feature': FEATURES, 'global_impurity_importance': model.feature_importances_}).to_csv(
        output / 'feature_importance.csv', index=False)
    record = {'run_id': run_id, 'algorithm': 'Random Forest',
        'started_at_utc': started.isoformat(), 'finished_at_utc': datetime.now(timezone.utc).isoformat(),
        'researcher': researcher, 'execution_platform_reported': execution_platform,
        'environment': {'python': platform.python_version(), 'sklearn': sklearn.__version__,
                        'numpy': np.__version__, 'pandas': pd.__version__, 'joblib': joblib.__version__},
        'features': FEATURES, 'classes': LABELS, 'hyperparameters': model.get_params(),
        'split': {'seed': seed, 'train_rows': len(train), 'holdout_rows': len(holdout),
                  'cv_folds': cv_folds, 'exact_predictor_overlap': 0, 'test_used_for_selection': False},
        'algorithm_selection': 'Random Forest specified before evaluation; no algorithm comparison.',
        'data_audit': audit, 'metrics': metrics, 'fit_seconds': fit_seconds,
        'training_script_sha256': file_hash(__file__),
        'new_artifact_sha256': file_hash(output / 'random_forest.joblib'),
        'baseline_reference': reference, 'production_model_changed': False,
        'fit_scope': 'training partition only; exported model replays held-out predictions',
        'npk_used': False, 'field_validation': 'not established',
        'annual_input_compatibility': 'not established',
        'limitations': ['Existing mixed Kaggle-based and generated profile/GIS rows; not independent farm accuracy.',
          'Independent farm groups and consistent labelled climate periods are unavailable.',
          'Banana variety labels and NPK measurements are not available in these rows.',
          'Recorded platform/timestamps support replay but do not independently authenticate the place of execution.']}
    write_json(output / 'training_run.json', record)
    write_json(output / 'feature_order.json', FEATURES)
    for source, name in [(dataset, 'input_dataset.csv'), (manifest_path, 'dataset_manifest.json'),
                         (reference_path, 'current_model_reference.json'), (__file__, 'train_random_forest.py')]:
        (output / name).write_bytes(Path(source).read_bytes())
    write_json(output / 'artifact_hashes.json', {p.name: file_hash(p) for p in sorted(output.iterdir()) if p.is_file()})
    archive = output.with_suffix('.zip')
    with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED) as zipped:
        for path in sorted(output.iterdir()):
            zipped.write(path, arcname=output.name + '/' + path.name)
    print('Random Forest training finished. Keep the executed notebook with outputs.', flush=True)
    return output, archive, record


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dataset', type=Path, default=Path('seven_crop_without_npk.csv'))
    parser.add_argument('--manifest', type=Path, default=Path('dataset_manifest.json'))
    parser.add_argument('--reference', type=Path, default=Path('current_model_reference.json'))
    parser.add_argument('--output', type=Path, default=Path('runs'))
    args = parser.parse_args()
    run_training(args.dataset, args.manifest, args.reference, args.output)
