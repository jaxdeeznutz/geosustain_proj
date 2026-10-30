"""Isolated, grouped DT/SVM/RF research evaluation. Never publishes a model.

Run --help from the repository root. Inputs require a hash-bound data contract.
Controlled fixtures test tooling only; scientific inputs need reviewed compatible
measurements and source periods. The production training guard is unchanged.
"""
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
import argparse
import csv
import hashlib
import importlib.metadata
import io
import json
from pathlib import Path
import platform
import sys
from time import perf_counter

import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import classification_report, confusion_matrix
from sklearn.model_selection import StratifiedGroupKFold
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.svm import SVC
from sklearn.tree import DecisionTreeClassifier
from threadpoolctl import threadpool_limits

BACKEND = Path(__file__).resolve().parents[1]
REPO = BACKEND.parent
sys.path.insert(0, str(BACKEND))
from model_artifacts import FEATURES
from training.climate_training_contract import validate_training_periods

VERSION = 'grouped-model-evaluation-v1'
MODEL_NAMES = ('decision_tree', 'svm', 'random_forest')
METRICS = ('accuracy', 'precision_macro', 'recall_macro', 'f1_macro', 'f1_weighted')
OUTPUT_ROOTS = (REPO / 'research/model-evaluation',
                REPO / 'defense-evidence/capstone-fix-execution/phase-04/runs')
PROTECTED = tuple(BACKEND / n for n in ('crop_model.pkl', 'crop_model_features.pkl',
                  'crop_model_metadata.json', 'Crop_recommendation.csv',
                  'Crop_recommendation_with_gis.csv', 'training/climate_training_contract.py'))


class EvaluationError(ValueError):
    pass


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False)


def digest(value):
    return hashlib.sha256(canonical(value).encode()).hexdigest()


def file_hash(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


@dataclass(frozen=True)
class Config:
    seed: int = 42
    holdout_folds: int = 5
    cv_folds: int = 4
    bootstrap_replicates: int = 1000
    forest_trees: int = 500

    def validate(self):
        bounds = {'seed': (0, 2**32-1), 'holdout_folds': (2, 10),
                  'cv_folds': (2, 10), 'bootstrap_replicates': (50, 10000),
                  'forest_trees': (1, 1000)}
        for name, (low, high) in bounds.items():
            value = getattr(self, name)
            if type(value) is not int or not low <= value <= high:
                raise EvaluationError(f'{name} must be an integer in [{low}, {high}].')


def validate_contract(contract, data_hash):
    if contract.get('schema_version') != 1 or contract.get('dataset_sha256') != data_hash:
        raise EvaluationError('Data contract schema/hash does not match the exact CSV bytes.')
    purpose = contract.get('purpose')
    if purpose not in ('controlled_fixture', 'scientific_evaluation'):
        raise EvaluationError('Purpose must explicitly identify controlled fixture or scientific evaluation.')
    if not isinstance(contract.get('source'), str) or not contract['source'].strip():
        raise EvaluationError('A traceable source statement is required.')
    if contract.get('feature_order') != FEATURES:
        raise EvaluationError('Common feature order must exactly match the recorded ten-feature contract.')
    columns = [contract.get(k) for k in ('label_column', 'record_id_column', 'group_column')]
    if any(not isinstance(v, str) or not v.strip() for v in columns) or len(set(columns)) != 3:
        raise EvaluationError('Distinct label, observation ID and independent group columns are required.')
    if set(columns) & set(FEATURES) or not contract.get('group_basis'):
        raise EvaluationError('Grouping/target columns cannot be inference features; group basis is required.')
    metadata = contract.get('features', {})
    if set(metadata) != set(FEATURES):
        raise EvaluationError('Every feature needs its own unit, method, period and source record.')
    for name, item in metadata.items():
        if not isinstance(item, dict) or any(not isinstance(item.get(k), str) or not item[k].strip()
                                             for k in ('unit', 'method', 'period', 'source')):
            raise EvaluationError(f'Incomplete feature definition: {name}.')
    if purpose == 'controlled_fixture':
        if contract.get('data_basis') != 'synthetic_controlled':
            raise EvaluationError('Controlled fixtures must be explicitly synthetic, not agricultural validation.')
    else:
        if contract.get('data_basis') != 'documented_independent_records':
            raise EvaluationError('Scientific evaluation requires documented independent source records.')
        for name, item in metadata.items():
            if any(token in item[key].lower() for key in ('unit', 'period', 'method')
                   for token in ('unknown', 'unverified', 'unspecified', 'fixture', 'synthetic')):
                raise EvaluationError(f'Scientific measurement definition remains unresolved: {name}.')
        review = contract.get('measurement_review', {})
        if review.get('status') != 'documented_compatible' or any(not review.get(k) for k in ('reference', 'reviewer', 'date')):
            raise EvaluationError('Climate/nutrient/measurement compatibility needs a recorded review.')
        sources = contract.get('climate_sources', {})
        validate_training_periods(sources)
        for name in ('rainfall', 'temperature', 'humidity'):
            if any(periods[name] != metadata[name]['period'] for periods in sources.values()):
                raise EvaluationError(f'{name} feature period disagrees with its source periods.')
        known_units = {'rainfall': 'mm', 'temperature': 'C', 'humidity': '%',
                       'ph': 'pH', 'ndvi': 'index', 'elevation': 'm', 'slope': '%'}
        for name, expected in known_units.items():
            if metadata[name]['unit'] != expected:
                raise EvaluationError(f'{name} unit must be explicitly {expected}; no conversion is inferred.')


def read_data(dataset, contract):
    raw = Path(dataset).read_bytes()
    data_hash = hashlib.sha256(raw).hexdigest()
    validate_contract(contract, data_hash)
    id_col, group_col, label_col = (contract[k] for k in ('record_id_column', 'group_column', 'label_column'))
    frame = pd.read_csv(io.BytesIO(raw), dtype={id_col: str, group_col: str, label_col: str})
    if not 20 <= len(frame) <= 100000:
        raise EvaluationError('Evaluation is bounded to 20-100,000 observations.')
    if not set(FEATURES+[id_col, group_col, label_col]) <= set(frame):
        raise EvaluationError('CSV is missing required observation, group, target or feature columns.')
    for col in (id_col, group_col, label_col):
        if frame[col].isna().any() or frame[col].str.strip().eq('').any():
            raise EvaluationError(f'Missing identifier or label: {col}.')
        frame[col] = frame[col].str.strip()
    if frame[id_col].duplicated().any():
        raise EvaluationError('Observation IDs must be unique; repeated measurements need distinct IDs and a shared group.')
    try:
        values = frame[FEATURES].to_numpy(dtype=float)
    except (TypeError, ValueError) as exc:
        raise EvaluationError('Features must be numeric, observed finite values.') from exc
    if not np.isfinite(values).all() or any(pd.api.types.is_bool_dtype(frame[c]) for c in FEATURES):
        raise EvaluationError('Missing/nonfinite/boolean features are not silently imputed or converted.')
    labels = sorted(frame[label_col].unique().tolist())
    if not 2 <= len(labels) <= 100:
        raise EvaluationError('Evaluation requires 2-100 supported classes.')
    if contract['purpose'] == 'controlled_fixture' and any(not label.startswith('fixture_') for label in labels):
        raise EvaluationError('Controlled software fixtures use fixture_* targets, not real crop labels.')
    frame[FEATURES] = values
    return frame, data_hash, labels


def independent_groups(frame, contract, data_hash):
    """Union declared repeated-unit groups AND exact duplicate-feature records.

    Transitive components prevent a duplicated observation from linking two
    nominal farms across a partition. Raw farm/observation IDs are not exported.
    """
    parents = list(range(len(frame)))

    def find(i):
        while parents[i] != i:
            parents[i] = parents[parents[i]]
            i = parents[i]
        return i

    def union(a, b):
        a, b = find(a), find(b)
        parents[max(a, b)] = min(a, b)

    feature_keys = [digest([float(v) if v else 0.0 for v in row])
                    for row in frame[FEATURES].to_numpy()]
    for keys in (frame[contract['group_column']].tolist(), feature_keys):
        seen = {}
        for i, key in enumerate(keys):
            if key in seen:
                union(i, seen[key])
            else:
                seen[key] = i
    record_keys = [digest([data_hash, 'observation', value])
                   for value in frame[contract['record_id_column']]]
    components = {}
    for i, key in enumerate(record_keys):
        components.setdefault(find(i), []).append(key)
    group_keys = {root: digest(sorted(keys)) for root, keys in components.items()}
    groups = np.array([group_keys[find(i)] for i in range(len(frame))])
    return groups, record_keys, feature_keys


def checked_folds(y, groups, count, seed):
    labels = set(y)
    if any(len(set(groups[y == label])) < count for label in labels):
        raise EvaluationError(f'Each class needs at least {count} independent connected groups; do not split repeated observations.')
    folds = list(StratifiedGroupKFold(n_splits=count, shuffle=True, random_state=seed)
                 .split(np.zeros(len(y)), y, groups))
    for train, test in folds:
        if (set(groups[train]) & set(groups[test]) or set(y[train]) != labels or set(y[test]) != labels):
            raise EvaluationError('Grouped stratification cannot retain all classes without leakage; supply more independent groups.')
    return folds


def partitions(frame, contract, data_hash, config):
    y = frame[contract['label_column']].to_numpy()
    groups, keys, feature_keys = independent_groups(frame, contract, data_hash)
    train, test = checked_folds(y, groups, config.holdout_folds, config.seed)[0]
    cv = [(train[a], train[b]) for a, b in checked_folds(y[train], groups[train], config.cv_folds, (config.seed+1) % 2**32)]
    train_set = set(train.tolist())
    validation_fold = {int(row): i for i, (_, val) in enumerate(cv) for row in val}
    manifest = {'version': VERSION, 'dataset_sha256': data_hash,
                'holdout_rule': 'First fold of predeclared stratified grouped split; never chosen by model score.',
                'seed': config.seed, 'holdout_folds': config.holdout_folds, 'cv_folds': config.cv_folds,
                'records': [{'record_key': key, 'feature_hash': feature_keys[i], 'group_key': str(groups[i]),
                             'label': str(y[i]), 'role': 'train' if i in train_set else 'holdout',
                             'cv_validation_fold': validation_fold.get(i)} for i, key in enumerate(keys)],
                'cv': [{'fold': i, 'train_keys': [keys[j] for j in a], 'validation_keys': [keys[j] for j in b]}
                       for i, (a, b) in enumerate(cv)]}
    for a, b in [(train, test), *cv]:
        assert not set(groups[a]) & set(groups[b])
        assert not {feature_keys[i] for i in a} & {feature_keys[i] for i in b}
    return train, test, cv, groups, keys, manifest


def metrics_from_matrix(matrix):
    matrix = np.asarray(matrix, dtype=float)
    true_support, predicted_support = matrix.sum(axis=1), matrix.sum(axis=0)
    diagonal = np.diag(matrix)
    precision = np.divide(diagonal, predicted_support, out=np.zeros_like(diagonal), where=predicted_support != 0)
    recall = np.divide(diagonal, true_support, out=np.zeros_like(diagonal), where=true_support != 0)
    f1 = np.divide(2*precision*recall, precision+recall, out=np.zeros_like(diagonal), where=(precision+recall) != 0)
    total = matrix.sum()
    return {'accuracy': float(diagonal.sum()/total), 'precision_macro': float(precision.mean()),
            'recall_macro': float(recall.mean()), 'f1_macro': float(f1.mean()),
            'f1_weighted': float(np.dot(f1, true_support)/total)}


def cluster_intervals(y, predicted, groups, labels, config):
    unique = sorted(set(groups))
    per_group = np.array([confusion_matrix(y[groups == group], predicted[groups == group], labels=labels) for group in unique])
    random = np.random.default_rng(config.seed+997)
    values = []
    for _ in range(config.bootstrap_replicates):
        sample = random.integers(0, len(unique), size=len(unique))
        values.append(metrics_from_matrix(per_group[sample].sum(axis=0)))
    return {'method': '95% percentile cluster bootstrap of held-out independent groups, with fixed fitted model; all class labels retained in every replicate.',
            'replicates': config.bootstrap_replicates, 'groups': len(unique), 'seed': config.seed+997,
            'limitation': 'Approximate, especially with few independent groups. Conditional on this training set and held-out partition; does not measure retraining uncertainty, geographic transfer, paired model significance or field validity. Missing replicate classes contribute zero to macro metrics.',
            'metrics': {key: {'lower': float(np.quantile([row[key] for row in values], .025)),
                              'upper': float(np.quantile([row[key] for row in values], .975))} for key in METRICS}}


def model_parameters(config):
    trees = {'max_depth': 14, 'min_samples_leaf': 6, 'min_samples_split': 12, 'random_state': config.seed}
    return {'decision_tree': {**trees, 'class_weight': 'balanced'},
            'svm': {'kernel': 'rbf', 'C': 10, 'gamma': 'scale', 'class_weight': 'balanced',
                    'random_state': config.seed, 'probability': False},
            'random_forest': {**trees, 'n_estimators': config.forest_trees, 'max_features': 'sqrt',
                              'class_weight': 'balanced_subsample', 'n_jobs': 1}}


def build_model(name, parameters):
    if name == 'svm':
        return Pipeline([('scaler', StandardScaler()), ('svc', SVC(**parameters))])
    if name == 'decision_tree':
        return DecisionTreeClassifier(**parameters)
    return RandomForestClassifier(**parameters)


def select_model(cv_results):
    # Fixed tie order favors the simpler estimator; held-out metrics never enter.
    return min(MODEL_NAMES, key=lambda name: (-cv_results[name]['mean']['f1_macro'],
                                            -cv_results[name]['mean']['accuracy'], MODEL_NAMES.index(name)))


def evaluate(dataset, contract, config=Config()):
    config.validate()
    frame, data_hash, labels = read_data(dataset, contract)
    train, test, folds, groups, keys, split_manifest = partitions(frame, contract, data_hash, config)
    x, y = frame[FEATURES], frame[contract['label_column']].to_numpy()
    params = model_parameters(config)
    cross_validation, results = {}, {}
    with threadpool_limits(limits=1):
        # No preprocessing, balancing, imputation or augmentation outside folds.
        for name in MODEL_NAMES:
            rows = []
            for i, (a, b) in enumerate(folds):
                estimator = build_model(name, params[name])
                start = perf_counter(); estimator.fit(x.iloc[a], y[a]); fit_seconds = perf_counter()-start
                start = perf_counter(); predicted = estimator.predict(x.iloc[b]); predict_seconds = perf_counter()-start
                row = {'fold': i, 'metrics': metrics_from_matrix(confusion_matrix(y[b], predicted, labels=labels)),
                       'fit_seconds': fit_seconds, 'predict_seconds': predict_seconds,
                       'prediction_sha256': digest(predicted.tolist()),
                       'train_rows': len(a), 'validation_rows': len(b),
                       'train_groups': len(set(groups[a])), 'validation_groups': len(set(groups[b]))}
                if name == 'svm':
                    row['scaler_mean'] = estimator.named_steps['scaler'].mean_.tolist()
                    row['scaler_samples_seen'] = int(estimator.named_steps['scaler'].n_samples_seen_)
                rows.append(row)
            cross_validation[name] = {'folds': rows,
                'mean': {key: float(np.mean([r['metrics'][key] for r in rows])) for key in METRICS},
                'standard_deviation': {key: float(np.std([r['metrics'][key] for r in rows], ddof=1)) for key in METRICS},
                'note': 'Descriptive fold variability, not an independent-sample confidence interval.'}
        selected = select_model(cross_validation)
        for name in MODEL_NAMES:
            estimator = build_model(name, params[name])
            start = perf_counter(); estimator.fit(x.iloc[train], y[train]); fit_seconds = perf_counter()-start
            start = perf_counter(); predicted = estimator.predict(x.iloc[test]); predict_seconds = perf_counter()-start
            matrix = confusion_matrix(y[test], predicted, labels=labels)
            results[name] = {'parameters': params[name], 'preprocessing': 'StandardScaler fitted within each training partition' if name == 'svm' else 'None; raw common features',
                'metrics': metrics_from_matrix(matrix), 'class_order': labels, 'confusion_matrix': matrix.tolist(),
                'per_class': classification_report(y[test], predicted, labels=labels, output_dict=True, zero_division=0),
                'fit_seconds': fit_seconds, 'predict_seconds': predict_seconds,
                'predict_seconds_per_row': predict_seconds/len(test),
                'predictions': [{'record_key': keys[row], 'true': str(y[row]), 'predicted': str(pred)} for row, pred in zip(test, predicted)],
                'prediction_sha256': digest(predicted.tolist()),
                'uncertainty': cluster_intervals(y[test], predicted, groups[test], labels, config)}
            if name == 'svm':
                results[name]['scaler_mean'] = estimator.named_steps['scaler'].mean_.tolist()
                results[name]['scaler_scale'] = estimator.named_steps['scaler'].scale_.tolist()
                results[name]['scaler_samples_seen'] = int(estimator.named_steps['scaler'].n_samples_seen_)
    versions = {key: importlib.metadata.version(key) for key in ('scikit-learn', 'numpy', 'scipy', 'pandas', 'joblib', 'threadpoolctl')}
    basis = contract['purpose']
    report = {'version': VERSION, 'recorded_at_utc': datetime.now(timezone.utc).isoformat(),
        'purpose': basis, 'data_basis': contract['data_basis'], 'source': contract['source'],
        'dataset_sha256': data_hash, 'contract_sha256': digest(contract), 'runner_sha256': file_hash(__file__),
        'split_sha256': digest(split_manifest), 'config': asdict(config),
        'environment': {'python': platform.python_version(), 'platform': platform.platform(), 'versions': versions, 'threads': 1},
        'feature_order': FEATURES, 'feature_definitions': contract['features'], 'classes': labels,
        'support': {role: {'rows': len(idx), 'independent_groups': len(set(groups[idx])),
                          'per_class': {label: int(np.sum(y[idx] == label)) for label in labels}}
                    for role, idx in [('all', np.arange(len(y))), ('train', train), ('holdout', test)]},
        'grouping': {'declared_groups': int(frame[contract['group_column']].nunique()), 'connected_groups': len(set(groups)),
                     'basis': contract['group_basis'], 'duplicate_features_join_groups': True,
                     'identifiers': 'Observation and group keys hashed; no raw farm IDs or feature payloads exported.'},
        'cv': cross_validation, 'models': results,
        'selection': {'candidate': selected, 'basis': 'Highest training-only grouped CV macro F1, then CV accuracy; exact ties prefer DT, SVM, RF in that order.',
                      'holdout_used_for_selection': False, 'production_changed': False,
                      'compatibility_resolution_required': selected != 'random_forest',
                      'status': 'tooling_fixture_only' if basis == 'controlled_fixture' else 'research_candidate_for_review',
                      'next_gate': 'Phase 8 scientific data acceptance and explicit production compatibility/selection decision; no automatic publication.'},
        'limitations': ['Not a reproduction of manuscript Table 13 or the legacy model evaluation.',
                       'No tuning on holdout; hyperparameters/config are predeclared. Repeatedly choosing configurations after viewing holdout would invalidate its independence.',
                       'No synthetic GIS augmentation or resampling is performed by this runner; class weights are learned only from training partitions.',
                       'Evaluation unit is a record with grouped dependence protection; this is not crop yield, harvest probability or measured parcel suitability.',
                       'Contract compatibility is declared source/reviewer evidence, not independently certified by software.',
                       'No chronological/geographic transfer claim: grouped stratification alone is not a temporal or regional holdout.',
                       'Timing is measured wall-clock on this environment, not a universal latency benchmark.',
                       'Synthetic controlled fixtures establish implementation behavior only; no agricultural accuracy is established.' if basis == 'controlled_fixture' else 'Final field and nutrient validity remain subject to scientific acceptance.']}
    report['reproducibility_sha256'] = digest(reproducible_result(report))
    return report, split_manifest


def reproducible_result(report):
    """Recorded timings and capture time are deliberately not reproducible claims."""
    def strip(value):
        if isinstance(value, dict):
            return {k: strip(v) for k, v in value.items()
                    if k not in ('recorded_at_utc', 'reproducibility_sha256', 'replay_of') and 'seconds' not in k}
        if isinstance(value, list):
            return [strip(v) for v in value]
        return value
    return strip(report)


def safe_output(path):
    path = Path(path).resolve()
    if not any(path != root.resolve() and path.is_relative_to(root.resolve()) for root in OUTPUT_ROOTS):
        raise EvaluationError('Outputs must be a new child of research/model-evaluation or Phase 4 runs; production paths are forbidden.')
    if path.exists():
        raise EvaluationError('Run output already exists; historical results are never overwritten.')
    return path


def write_run(output, report, split_manifest, contract):
    output = safe_output(output)
    output.mkdir(parents=True, exist_ok=False)
    for name, value in [('results.json', report), ('splits.json', split_manifest), ('contract.json', contract)]:
        (output/name).write_text(json.dumps(value, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    with (output/'comparison.csv').open('w', newline='', encoding='utf-8') as stream:
        writer = csv.writer(stream)
        writer.writerow(['purpose', 'model', *METRICS, 'cv_f1_macro_mean', 'cv_f1_macro_std', 'fit_seconds', 'predict_seconds'])
        for name in MODEL_NAMES:
            row = report['models'][name]
            writer.writerow([report['purpose'], name, *(row['metrics'][m] for m in METRICS),
                             report['cv'][name]['mean']['f1_macro'], report['cv'][name]['standard_deviation']['f1_macro'],
                             row['fit_seconds'], row['predict_seconds']])
    lines = ['# Isolated model comparison', '',
             '**CONTROLLED SYNTHETIC TOOLING RESULTS - NOT AGRICULTURAL VALIDATION**' if report['purpose'] == 'controlled_fixture' else '**RESEARCH EVALUATION - SCIENTIFIC/PRODUCTION ACCEPTANCE SEPARATE**', '',
             'This is a new recorded run, not the recovered manuscript Table 13. All models use the same held-out records, common features and training-only grouped CV.', '',
             '| Model | Accuracy | Macro precision | Macro recall | Macro F1 | Weighted F1 | CV macro F1 mean (SD) |',
             '| --- | --- | --- | --- | --- | --- | --- |']
    for name in MODEL_NAMES:
        row = report['models'][name]; cv = report['cv'][name]
        lines.append('| '+name+' | '+' | '.join(f'{row["metrics"][key]*100:.2f}%' for key in METRICS)
                     +f' | {cv["mean"]["f1_macro"]*100:.2f}% ({cv["standard_deviation"]["f1_macro"]*100:.2f}) |')
    lines += ['', '## Held-out uncertainty', '',
              '95% percentile cluster-bootstrap intervals, conditional on this fitted model and partition. All class labels are retained. These do not establish field validity.', '',
              '| Model | Accuracy | Macro F1 | Weighted F1 |', '| --- | --- | --- | --- |']
    for name in MODEL_NAMES:
        intervals = report['models'][name]['uncertainty']['metrics']
        lines.append('| '+name+' | '+' | '.join(f'{intervals[k]["lower"]*100:.2f}-{intervals[k]["upper"]*100:.2f}%' for k in ('accuracy', 'f1_macro', 'f1_weighted'))+' |')
    lines += ['', f'Predeclared CV selection: **{report["selection"]["candidate"]}**. Production was not changed.',
              f'Dataset SHA-256: `{report["dataset_sha256"]}`', f'Split SHA-256: `{report["split_sha256"]}`', '',
              'Per-class support/results, fixed-label confusion matrices, timing, hyperparameters, environment and replay fingerprints are in results.json; split membership is in splits.json.', '',
              *('- '+line for line in report['limitations'])]
    (output/'comparison.md').write_text('\n'.join(lines)+'\n', encoding='utf-8')
    artifacts = {p.name: file_hash(p) for p in output.iterdir() if p.is_file()}
    (output/'files.json').write_text(json.dumps({'files': artifacts, 'model_files_written': False}, indent=2)+'\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dataset', type=Path, required=True)
    parser.add_argument('--contract', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--reproduce', type=Path, help='Compare with an existing results.json before saving a new independent replay directory.')
    parser.add_argument('--seed', type=int, default=42)
    parser.add_argument('--holdout-folds', type=int, default=5)
    parser.add_argument('--cv-folds', type=int, default=4)
    parser.add_argument('--bootstrap-replicates', type=int, default=1000)
    parser.add_argument('--forest-trees', type=int, default=500)
    args = parser.parse_args()
    before = {str(p): file_hash(p) for p in PROTECTED}
    try:
        safe_output(args.output)
        config = Config(args.seed, args.holdout_folds, args.cv_folds, args.bootstrap_replicates, args.forest_trees)
        contract = json.loads(args.contract.read_text(encoding='utf-8'))
        report, splits = evaluate(args.dataset, contract, config)
        if args.reproduce:
            prior = json.loads(args.reproduce.read_text(encoding='utf-8'))
            if report['reproducibility_sha256'] != prior.get('reproducibility_sha256'):
                raise EvaluationError('Replay differs in dataset, contract, environment, split, predictions or metrics; no success result written.')
            report['replay_of'] = file_hash(args.reproduce)
        write_run(args.output, report, splits, contract)
        print(f'PASS: isolated {report["purpose"]} run; CV candidate {report["selection"]["candidate"]}; no production publication.')
        if args.reproduce:
            print('PASS: recorded deterministic evidence reproduced; wall-clock timing excluded.')
        return 0
    except (EvaluationError, ValueError, OSError) as exc:
        print(f'EVALUATION NOT COMPLETED: {exc}', file=sys.stderr)
        return 2
    finally:
        if before != {str(p): file_hash(p) for p in PROTECTED}:
            raise RuntimeError('Protected production inputs changed during the research command.')


if __name__ == '__main__':
    raise SystemExit(main())
