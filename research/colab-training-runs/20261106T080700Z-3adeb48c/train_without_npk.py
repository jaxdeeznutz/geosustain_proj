"""Reproducible DT/SVM/RF research training on the existing seven-crop rows.

NPK is excluded. This never installs a model into the application. Source rows
retain their original values/period uncertainty; no annual values are invented.
"""
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
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.svm import SVC
from sklearn.tree import DecisionTreeClassifier

FEATURES = ['temperature', 'humidity', 'ph', 'rainfall', 'ndvi', 'elevation', 'slope']
LABELS = ['banana', 'cacao', 'coconut', 'durian', 'mango', 'rice', 'rubber']
MODELS = ['decision_tree', 'svm', 'random_forest']
VERSION = 'seven-crop-no-npk-colab-v1'
LIMITATIONS = [
    'Research comparison on existing augmented data; not independent farm accuracy.',
    'Original Kaggle rows cover banana, coconut, mango and rice only. Cacao, durian and rubber use existing generated profiles.',
    'GIS predictors in this legacy dataset were generated using crop profiles; their label dependence can inflate evaluation.',
    'Rainfall periods and temperature aggregation in the labelled rows are unresolved. No annual conversion or relabelling is performed.',
    'Exact duplicates are removed before splitting; independent farm/source groups are unknown, so a row split cannot establish farm generalization.',
    'N, P and K are excluded. Received PAGRO measurements require compatible methods/units and matched crop-labelled records before retraining.',
    'This seven-input candidate cannot replace the current ten-input application model without integration and input-contract review.',
]


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


def make_models(seed=42, trees=500):
    if type(trees) is not int or not 1 <= trees <= 1000:
        raise ValueError('Forest tree count must be 1–1000.')
    return {
        'decision_tree': DecisionTreeClassifier(max_depth=14, min_samples_leaf=6,
            min_samples_split=12, class_weight='balanced', random_state=seed),
        'svm': make_pipeline(StandardScaler(), SVC(C=10, kernel='rbf', gamma='scale',
            class_weight='balanced', random_state=seed)),
        'random_forest': RandomForestClassifier(n_estimators=trees, max_depth=14,
            min_samples_leaf=6, min_samples_split=12, max_features='sqrt',
            class_weight='balanced_subsample', random_state=seed, n_jobs=1),
    }


def save_plots(output, summary, reports, forest):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    from sklearn.metrics import ConfusionMatrixDisplay
    for name, report in reports.items():
        fig, ax = plt.subplots(figsize=(8, 7))
        ConfusionMatrixDisplay(np.asarray(report['confusion_matrix']), display_labels=LABELS).plot(
            ax=ax, xticks_rotation=45, cmap='Greens', colorbar=False)
        ax.set_title(name.replace('_', ' ').title() + ' — legacy holdout, NPK excluded')
        fig.tight_layout(); fig.savefig(output / f'{name}_confusion_matrix.png', dpi=160); plt.close(fig)
    ax = summary.set_index('model')[['holdout_accuracy', 'holdout_f1_macro']].plot.bar(
        figsize=(9, 5), ylim=(0, 1), color=['#087b43', '#6aa6d3'], rot=0)
    ax.set_title('Three-model comparison — legacy data, NPK excluded')
    ax.set_ylabel('Fraction on held-out rows; not farm accuracy')
    ax.figure.tight_layout(); ax.figure.savefig(output / 'model_comparison.png', dpi=160); plt.close(ax.figure)
    importance = pd.DataFrame({'feature': FEATURES, 'impurity_importance': forest.feature_importances_})
    importance.to_csv(output / 'random_forest_feature_importance.csv', index=False)
    ax = importance.sort_values('impurity_importance').plot.barh(x='feature', y='impurity_importance',
        figsize=(8, 5), color='#087b43', legend=False)
    ax.set_title('Random Forest global impurity importance — not a local explanation')
    ax.figure.tight_layout(); ax.figure.savefig(output / 'random_forest_feature_importance.png', dpi=160); plt.close(ax.figure)


def run_training(dataset, manifest_path, output_parent, *, seed=42, trees=500, cv_folds=5,
                 execution_platform='local', researcher='Not supplied'):
    """Fit on training only, select with CV, then evaluate all three on one holdout."""
    started = datetime.now(timezone.utc)
    frame, manifest, audit = prepare_data(dataset, manifest_path)
    train, holdout, cv, splits = make_partitions(frame, seed, cv_folds)
    run_id = started.strftime('%Y%m%dT%H%M%SZ') + '-' + uuid.uuid4().hex[:8]
    output = Path(output_parent) / run_id
    # Avoid accidental application publication even when invoked locally.
    if any(part.lower() == 'backend' for part in output.resolve().parts):
        raise ValueError('Research output cannot be written into backend/.')
    output.mkdir(parents=True, exist_ok=False)
    x_train, y_train = frame.iloc[train][FEATURES], frame.iloc[train].label
    x_test, y_test = frame.iloc[holdout][FEATURES], frame.iloc[holdout].label
    models, cv_rows, summary_rows, reports = make_models(seed, trees), [], [], {}
    parameters = {name: {k: str(v) if not isinstance(v, (str, int, float, bool, type(None))) else v
                         for k, v in model.get_params().items()} for name, model in models.items()}
    scoring = {'accuracy': 'accuracy', 'precision_macro': 'precision_macro',
               'recall_macro': 'recall_macro', 'f1_macro': 'f1_macro'}
    # Scaling lives inside the SVM pipeline and is fitted separately within each CV fold.
    for name, model in models.items():
        print(f'Cross-validating {name}: {cv_folds} training-only folds', flush=True)
        scores = cross_validate(model, x_train, y_train, cv=cv, scoring=scoring,
                                n_jobs=1, error_score='raise', return_train_score=False)
        for fold in range(cv_folds):
            cv_rows.append({'model': name, 'fold': fold,
                **{metric: float(scores['test_' + metric][fold]) for metric in scoring}})
        summary_rows.append({'model': name, **{f'cv_{metric}_mean': float(scores['test_' + metric].mean())
                                              for metric in scoring},
                             'cv_f1_macro_std': float(scores['test_f1_macro'].std(ddof=1))})
    # Declare the selection before reading held-out predictions. Never choose by test score.
    selected = sorted(summary_rows, key=lambda row: (-row['cv_f1_macro_mean'], row['model']))[0]['model']
    print(f'Selected by training CV macro F1: {selected}. Now evaluating the fixed holdout.', flush=True)
    predictions = frame.iloc[holdout][['_record_id', 'label', '_source_basis']].copy()
    for row in summary_rows:
        name, model = row['model'], models[row['model']]
        tick = perf_counter(); model.fit(x_train, y_train); row['fit_seconds'] = perf_counter() - tick
        predicted = model.predict(x_test)
        report = classification_report(y_test, predicted, labels=LABELS, output_dict=True, zero_division=0)
        row.update(holdout_accuracy=float(accuracy_score(y_test, predicted)),
            holdout_precision_macro=float(report['macro avg']['precision']),
            holdout_recall_macro=float(report['macro avg']['recall']),
            holdout_f1_macro=float(report['macro avg']['f1-score']),
            holdout_f1_weighted=float(report['weighted avg']['f1-score']),
            selected_by_cv=name == selected)
        reports[name] = {'classification_report': report,
            'confusion_matrix': confusion_matrix(y_test, predicted, labels=LABELS).tolist()}
        predictions[name + '_prediction'] = predicted
        pd.DataFrame(report).T.to_csv(output / f'{name}_classification_report.csv')
        write_json(output / f'{name}_metrics.json', reports[name])
        path = output / f'{name}.joblib'; joblib.dump(model, path)
        restored = joblib.load(path)
        np.testing.assert_array_equal(restored.predict(x_test), predicted)
        if hasattr(model, 'predict_proba'):
            np.testing.assert_allclose(restored.predict_proba(x_test), model.predict_proba(x_test), rtol=0, atol=0)
        print(f'{name}: holdout accuracy={row["holdout_accuracy"]:.4f}, macro F1={row["holdout_f1_macro"]:.4f}', flush=True)
    summary = pd.DataFrame(summary_rows)
    summary.to_csv(output / 'comparison.csv', index=False)
    pd.DataFrame(cv_rows).to_csv(output / 'cross_validation.csv', index=False)
    splits.to_csv(output / 'split_manifest.csv', index=False)
    predictions.to_csv(output / 'holdout_predictions.csv', index=False)
    frame.to_csv(output / 'training_rows_deduplicated.csv', index=False)
    save_plots(output, summary, reports, models['random_forest'])
    write_json(output / 'dataset_manifest.json', manifest)
    record = {'schema_version': 1, 'experiment': VERSION, 'run_id': run_id,
        'started_at_utc': started.isoformat(), 'finished_at_utc': datetime.now(timezone.utc).isoformat(),
        'execution_platform': execution_platform, 'researcher': researcher,
        'environment': {'python': platform.python_version(), 'sklearn': sklearn.__version__,
                        'pandas': pd.__version__, 'numpy': np.__version__, 'joblib': joblib.__version__},
        'training_script_sha256': file_hash(__file__),
        'features': FEATURES, 'classes': LABELS, 'data_audit': audit,
        'split': {'seed': seed, 'train_rows': len(train), 'holdout_rows': len(holdout),
                  'holdout_fraction': .2, 'cv_folds': cv_folds, 'exact_predictor_overlap': 0,
                  'same_splits_for_all_models': True, 'test_set_used_for_selection': False},
        'selection': {'rule': 'Highest mean training-only CV macro F1; alphabetical model-name tie break.',
                      'selected_model': selected, 'production_model_changed': False},
        'hyperparameters': parameters, 'comparison': summary.to_dict(orient='records'),
        'model_fit_scope': 'training partition only; exported models replay the held-out predictions',
        'npk_used': False, 'annual_input_compatibility': 'not established', 'field_validation': 'not established',
        'application_integration_ready': False, 'limitations': LIMITATIONS}
    write_json(output / 'training_run.json', record)
    write_json(output / 'feature_order.json', FEATURES)
    (output / 'README.txt').write_text(
        'GeoSustain: seven crops, Decision Tree / SVM / Random Forest, NPK excluded.\n'
        f'Run: {run_id}\nExecution platform reported by runner: {execution_platform}\n'
        f'Selected by training-only CV macro F1: {selected}\n'
        'Keep the executed notebook with its outputs as the record of your own Colab run.\n'
        'Timestamps and this JSON are reproducibility records, not independent proof of execution location.\n'
        'Do not copy these seven-input models into the current ten-input app.\n\n'
        + '\n'.join('- ' + item for item in LIMITATIONS) + '\n', encoding='utf-8')
    # Bundle exact input bytes as well as cleaned rows, so the audit can be replayed.
    (output / 'input_dataset.csv').write_bytes(Path(dataset).read_bytes())
    (output / 'train_without_npk.py').write_bytes(Path(__file__).read_bytes())
    write_json(output / 'artifact_hashes.json', {p.name: file_hash(p) for p in sorted(output.iterdir()) if p.is_file()})
    archive = output.with_suffix('.zip')
    with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED) as z:
        for path in sorted(output.iterdir()): z.write(path, arcname=output.name + '/' + path.name)
    return output, archive, record


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dataset', type=Path, required=True)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--trees', type=int, default=500)
    args = parser.parse_args()
    output, archive, report = run_training(args.dataset, args.manifest, args.output, trees=args.trees)
    print(json.dumps({'output': str(output), 'archive': str(archive), 'selection': report['selection']}, indent=2))
