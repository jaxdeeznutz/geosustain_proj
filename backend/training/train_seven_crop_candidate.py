"""Train a seven-class migration candidate from existing legacy rows.

This experiment does not establish measurement compatibility or field accuracy.
It cannot publish into backend/; production training keeps its climate guard.
No rows, nutrients, GIS features or source periods are generated or relabelled.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import io
import json
from pathlib import Path
import platform
import sys

import joblib
import numpy as np
import pandas as pd
import sklearn
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score, classification_report, confusion_matrix, f1_score
from sklearn.model_selection import train_test_split
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.svm import SVC
from sklearn.tree import DecisionTreeClassifier

BACKEND = Path(__file__).resolve().parents[1]
REPO = BACKEND.parent
sys.path.insert(0, str(BACKEND))
from model_artifacts import APPROVED_LABELS, FEATURES, artifact_version
from model_explainability import forest_snapshot
from model_ranking import attach_model_ranking
from training.climate_training_contract import validate_training_periods

OUTPUT_ROOT = REPO / 'research/seven-crop-candidates'
PROTECTED = tuple(BACKEND / name for name in (
    'crop_model.pkl', 'crop_model_features.pkl', 'crop_model_metadata.json',
    'Crop_recommendation.csv', 'Crop_recommendation_with_gis.csv',
    'training/climate_training_contract.py',
))


def protected_hashes():
    return {str(path.relative_to(REPO)): artifact_version(path.read_bytes()) for path in PROTECTED}


def prepare_data(path):
    raw = Path(path).read_bytes()
    frame = pd.read_csv(io.BytesIO(raw))
    if not set(FEATURES + ['label']) <= set(frame):
        raise ValueError('Existing dataset must contain all ten features and label; no features are invented.')
    if not 35 <= len(frame) <= 100000:
        raise ValueError('Candidate input must contain 35–100,000 existing rows.')
    frame['label'] = frame['label'].astype(str).str.strip().str.lower()
    total = len(frame)
    frame = frame.loc[frame.label.isin(APPROVED_LABELS), FEATURES + ['label']].copy()
    if set(frame.label) != APPROVED_LABELS:
        raise ValueError('Existing rows do not cover exactly all seven approved crops.')
    frame[FEATURES] = frame[FEATURES].apply(pd.to_numeric, errors='raise')
    if not np.isfinite(frame[FEATURES].to_numpy(dtype=float)).all():
        raise ValueError('Missing or nonfinite feature values; no imputation is performed.')
    if frame.groupby(FEATURES, dropna=False).label.nunique().gt(1).any():
        raise ValueError('Identical inputs have conflicting crop labels; review the source rows.')
    filtered = len(frame)
    # Deduplicate BEFORE splitting; never balance/resample across a holdout.
    frame = frame.drop_duplicates(FEATURES + ['label']).reset_index(drop=True)
    if frame.label.value_counts().min() < 10:
        raise ValueError('Each crop needs at least ten distinct existing input rows.')
    audit = {
        'source_sha256': hashlib.sha256(raw).hexdigest(),
        'source_rows': total, 'filtered_rows': filtered,
        'excluded_other_crop_rows': total - filtered,
        'duplicate_rows_removed_before_split': filtered - len(frame),
        'unique_rows': len(frame), 'class_counts': frame.label.value_counts().sort_index().to_dict(),
        'row_generation': 'none', 'resampling': 'none', 'unit_or_period_conversion': 'none',
    }
    return frame, audit


def fit_candidate(frame, *, seed=42, trees=500):
    if type(trees) is not int or not 1 <= trees <= 1000:
        raise ValueError('Tree count must be in [1, 1000].')
    if type(seed) is not int or not 0 <= seed < 2**32:
        raise ValueError('Seed must be an unsigned 32-bit integer.')
    train, holdout = train_test_split(np.arange(len(frame)), test_size=.20,
                                    stratify=frame.label, random_state=seed)
    keys = pd.util.hash_pandas_object(frame[FEATURES], index=False).astype(str)
    if set(keys.iloc[train]) & set(keys.iloc[holdout]):
        raise ValueError('Exact duplicate input rows cross the holdout.')
    x_train, y_train = frame.iloc[train][FEATURES], frame.iloc[train].label
    x_test, y_test = frame.iloc[holdout][FEATURES], frame.iloc[holdout].label
    forest = RandomForestClassifier(n_estimators=trees, max_depth=14,
        min_samples_leaf=6, min_samples_split=12, max_features='sqrt',
        class_weight='balanced_subsample', random_state=seed, n_jobs=2)
    models = {
        'random_forest': forest,
        'decision_tree': DecisionTreeClassifier(max_depth=14, min_samples_leaf=6,
            min_samples_split=12, class_weight='balanced', random_state=seed),
        'svm': make_pipeline(StandardScaler(), SVC(C=10, kernel='rbf', gamma='scale',
            class_weight='balanced', random_state=seed)),
    }
    metrics = {}
    for name, model in models.items():
        model.fit(x_train, y_train)
        if name == 'random_forest':
            # Serial tree reduction gives byte-stable prediction replay; fitting
            # can still use two workers without changing the learned trees.
            model.set_params(n_jobs=1)
        predictions = model.predict(x_test)
        metrics[name] = {
            'accuracy': float(accuracy_score(y_test, predictions)),
            'f1_macro': float(f1_score(y_test, predictions, average='macro', zero_division=0)),
            'classification_report': classification_report(y_test, predictions,
                labels=sorted(APPROVED_LABELS), output_dict=True, zero_division=0),
            'confusion_matrix': confusion_matrix(y_test, predictions, labels=sorted(APPROVED_LABELS)).tolist(),
        }
    if set(forest.classes_) != APPROVED_LABELS:
        raise ValueError('Candidate forest class scope differs from the seven-crop catalog.')
    probabilities = forest.predict_proba(x_test)
    if probabilities.shape[1] != 7 or not np.allclose(probabilities.sum(axis=1), 1):
        raise ValueError('Seven-class probability contract failed.')
    splits = {'seed': seed, 'holdout_fraction': .20, 'train_rows': len(train),
        'holdout_rows': len(holdout), 'exact_duplicate_overlap': 0,
        'train': [int(i) for i in train], 'holdout': [int(i) for i in holdout],
        'independent_farm_groups': 'unknown; no farm/source observation IDs in legacy CSV'}
    return forest, metrics, splits


def explanation_fixture(model, version, frame):
    samples = []
    for _, row in frame.head(9).iterrows():
        inputs = {key: float(row[key]) for key in FEATURES}
        data = pd.DataFrame([inputs], columns=FEATURES)
        probabilities = dict(zip(map(str, model.classes_), map(float, model.predict_proba(data)[0])))
        samples.append(forest_snapshot(model, version, inputs, model.predict(data)[0], probabilities))
    result = attach_model_ranking({}, samples)
    if result['local_model_explanation']['status'] != 'available':
        raise ValueError('Candidate did not produce a verified saved local explanation.')
    return result


def train(dataset, output, *, seed=42, trees=500):
    output = Path(output).resolve()
    if not output.is_relative_to(OUTPUT_ROOT.resolve()) or output == OUTPUT_ROOT.resolve():
        raise ValueError('Candidate output must be a new subdirectory of research/seven-crop-candidates; production output is forbidden.')
    if output.exists():
        raise ValueError('Candidate output already exists; use a new run directory.')
    before = protected_hashes()
    frame, audit = prepare_data(dataset)
    model, metrics, splits = fit_candidate(frame, seed=seed, trees=trees)
    payload = io.BytesIO()
    joblib.dump(model, payload)
    model_bytes = payload.getvalue()
    version = artifact_version(model_bytes)
    restored = joblib.load(io.BytesIO(model_bytes))
    np.testing.assert_array_equal(model.predict_proba(frame[FEATURES]), restored.predict_proba(frame[FEATURES]))
    record = explanation_fixture(restored, version, frame.iloc[splits['holdout']])
    try:
        validate_training_periods()
    except ValueError as error:
        climate_blocker = str(error)
    else:
        climate_blocker = None
    report = {
        'schema_version': 1, 'purpose': 'seven_crop_legacy_migration_experiment',
        'status': 'trained_candidate_not_approved_for_production',
        'created_at_utc': datetime.now(timezone.utc).isoformat(),
        'model_version': version, 'classes': sorted(APPROVED_LABELS), 'feature_order': FEATURES,
        'source': str(Path(dataset).resolve().relative_to(REPO)), 'data_audit': audit,
        'split': splits, 'comparison': metrics,
        'environment': {'python': platform.python_version(), 'sklearn': sklearn.__version__,
                        'numpy': np.__version__, 'pandas': pd.__version__},
        'script_sha256': artifact_version(Path(__file__).read_bytes()),
        'parameters': model.get_params(), 'production_promotion_allowed': False,
        'promotion_blockers': [item for item in [climate_blocker,
            'N/P/K physical measurement/unit compatibility with inference remains unverified.',
            'Legacy rows include synthetic crop/GIS profiles; field/source group identities are unavailable.',
            'No independent Panabo field validation; holdout scores are not harvest probabilities.'] if item],
        'checks': {'class_count': 7, 'all_catalog_crops_covered': True,
            'exact_duplicate_holdout_overlap': 0, 'pickle_prediction_roundtrip': True,
            'saved_local_explanation': 'available', 'production_artifacts_unchanged': before == protected_hashes()},
        'protected_production_hashes': before,
    }
    if not report['checks']['production_artifacts_unchanged']:
        raise RuntimeError('Protected production data/artifact changed during candidate training.')
    output.mkdir(parents=True)
    (output / 'crop_model.pkl').write_bytes(model_bytes)
    joblib.dump(FEATURES, output / 'crop_model_features.pkl')
    # The production loader intentionally rejects this unvalidated provenance status.
    metadata = {'schema_version': 1, 'model_version': version,
        'model_type': 'RandomForestClassifier', 'feature_names': FEATURES,
        'classes': sorted(APPROVED_LABELS), 'training': {'status': 'candidate_unvalidated',
            'report': 'training_report.json', 'production_promotion_allowed': False}}
    for name, body in [('crop_model_metadata.json', metadata), ('training_report.json', report),
                       ('synthetic_source_explanation.json', record)]:
        (output / name).write_text(json.dumps(body, indent=2, allow_nan=False) + '\n', encoding='utf-8')
    print(json.dumps({'output': str(output.relative_to(REPO)), 'classes': report['classes'],
        'rows': audit, 'holdout_accuracy': {key: item['accuracy'] for key, item in metrics.items()},
        'checks': report['checks'], 'production_promotion_allowed': False}, indent=2))
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--seed', type=int, default=42)
    parser.add_argument('--trees', type=int, default=500)
    args = parser.parse_args()
    train(BACKEND / 'Crop_recommendation_with_gis.csv', args.output, seed=args.seed, trees=args.trees)


if __name__ == '__main__':
    main()
