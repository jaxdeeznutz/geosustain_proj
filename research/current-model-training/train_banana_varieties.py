"""Experimental observed-variety classifier, only for separately labelled records.

Never infer cultivar labels from a generic Banana row, a crop guide, or a PSA
province total. Predictions describe observed labels, not the best variety/yield.
"""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import uuid
import joblib
import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import classification_report, confusion_matrix
from sklearn.model_selection import StratifiedGroupKFold, cross_validate
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.svm import SVC
from sklearn.tree import DecisionTreeClassifier

FEATURES = ['temperature', 'humidity', 'ph', 'rainfall', 'ndvi', 'elevation', 'slope']
VARIETIES = ['cavendish', 'lakatan', 'saba']
COLUMNS = FEATURES + ['variety', 'site_id', 'record_id', 'observed_at', 'source']
PERIODS = {'temperature': 'annual_mean_5y', 'rainfall': 'annual_mean_total_5y',
           'humidity': 'current', 'ph': 'soil_surface_0cm', 'ndvi': 'latest_usable_scene',
           'elevation': 'static_terrain', 'slope': 'static_terrain'}
UNITS = dict(zip(FEATURES, ['C', '%', 'pH', 'mm/year', 'index', 'm', '%']))


def readiness(path):
    frame = pd.read_csv(path)
    if not set(COLUMNS) <= set(frame):
        raise ValueError('Missing required variety data columns.')
    counts = {name: int(frame.variety.astype(str).str.strip().str.lower().eq(name).sum()) for name in VARIETIES}
    return {'row_count': len(frame), 'variety_counts': counts,
            'has_rows_for_every_variety': all(counts.values()),
            'varieties_trained': False,
            'note': 'Readiness counts are not source or agricultural validation.'}


def prepare(path, contract_path):
    path = Path(path)
    info = readiness(path)
    if not info['has_rows_for_every_variety']:
        raise ValueError('No complete matched variety dataset: Cavendish, Lakatan and Saba need their own labelled observations. Generic Banana and PSA province rows are not substituted.')
    frame = pd.read_csv(path, dtype={'site_id': str, 'record_id': str})
    contract = json.loads(Path(contract_path).read_text(encoding='utf-8'))
    if hashlib.sha256(path.read_bytes()).hexdigest() != contract.get('dataset_sha256'):
        raise ValueError('Data hash differs from the reviewed contract.')
    if contract.get('target') != 'observed_banana_variety' or contract.get('periods') != PERIODS or contract.get('units') != UNITS:
        raise ValueError('Target, periods and units must match the documented environmental feature contract.')
    if contract.get('data_basis') not in ('matched_farm_or_trial_observations', 'synthetic_software_test_fixture'):
        raise ValueError('Declare the source basis; generic/PSA/reference-only rows cannot train this experiment.')
    if {'N', 'P', 'K'} & set(frame):
        raise ValueError('This experiment excludes NPK.')
    for column in COLUMNS:
        if frame[column].isna().any() or frame[column].astype(str).str.strip().eq('').any():
            raise ValueError(f'Missing {column}; values and labels are not filled.')
    frame.variety = frame.variety.astype(str).str.strip().str.lower()
    if set(frame.variety) != set(VARIETIES) or frame.record_id.duplicated().any():
        raise ValueError('Expected exactly three variety labels and unique record IDs.')
    frame[FEATURES] = frame[FEATURES].apply(pd.to_numeric, errors='raise')
    if not np.isfinite(frame[FEATURES].to_numpy(dtype=float)).all():
        raise ValueError('Environmental inputs must be finite observations.')
    for key, (low, high) in {'temperature':(-90,65),'humidity':(0,100),'ph':(0,14),
                            'rainfall':(0,np.inf),'ndvi':(-1,1),'elevation':(-500,9000),
                            'slope':(0,np.inf)}.items():
        if pd.api.types.is_bool_dtype(frame[key]) or not frame[key].between(low, high).all():
            raise ValueError(f'Invalid physical range for {key}.')
    pd.to_datetime(frame.observed_at, errors='raise', utc=True)
    if frame.groupby('variety').site_id.nunique().min() < 5:
        raise ValueError('At least five independent sites per variety are needed for the grouped holdout/CV experiment.')
    return frame, contract


def train(path, contract_path, output_parent, *, trees=500, seed=42):
    frame, contract = prepare(path, contract_path)
    output = Path(output_parent).resolve()
    if any(part.lower() == 'backend' for part in output.parts):
        raise ValueError('Variety candidates cannot be written into backend.')
    output = output / ('banana-varieties-' + uuid.uuid4().hex[:10])
    x, y, groups = frame[FEATURES], frame.variety, frame.site_id
    all_labels = set(VARIETIES)
    folds = StratifiedGroupKFold(5, shuffle=True, random_state=seed)
    split = next(((a,b) for a,b in folds.split(x,y,groups)
                  if set(y.iloc[a]) == set(y.iloc[b]) == all_labels), None)
    if split is None:
        raise ValueError('More independent sites are needed to cover every variety in the grouped holdout.')
    train_ids, test_ids = split
    cv = list(StratifiedGroupKFold(3, shuffle=True, random_state=seed+1)
              .split(x.iloc[train_ids], y.iloc[train_ids], groups.iloc[train_ids]))
    for a,b in cv:
        if set(y.iloc[train_ids[a]]) != all_labels or set(y.iloc[train_ids[b]]) != all_labels:
            raise ValueError('More independent sites are needed to cover all varieties in each CV fold.')
    assert not set(groups.iloc[train_ids]) & set(groups.iloc[test_ids])
    models = {
        'decision_tree': DecisionTreeClassifier(max_depth=14, min_samples_leaf=2, random_state=seed),
        'svm': make_pipeline(StandardScaler(), SVC(C=10, class_weight='balanced', random_state=seed)),
        'random_forest': RandomForestClassifier(n_estimators=trees, max_depth=14, min_samples_leaf=2,
                                               class_weight='balanced_subsample', n_jobs=1, random_state=seed)}
    comparisons = []
    for name, model in models.items():
        scores = cross_validate(model, x.iloc[train_ids], y.iloc[train_ids], cv=cv,
                                scoring={'accuracy': 'accuracy', 'f1_macro': 'f1_macro'})
        comparisons.append({'model': name, 'cv_accuracy': float(scores['test_accuracy'].mean()),
                            'cv_f1_macro': float(scores['test_f1_macro'].mean())})
    winner = sorted(comparisons, key=lambda r: (-r['cv_f1_macro'], r['model']))[0]['model']
    output.mkdir(parents=True, exist_ok=False)
    for result in comparisons:
        model = models[result['model']]
        model.fit(x.iloc[train_ids], y.iloc[train_ids])
        predicted = model.predict(x.iloc[test_ids])
        result['holdout_report'] = classification_report(y.iloc[test_ids], predicted, labels=VARIETIES, output_dict=True, zero_division=0)
        result['confusion_matrix'] = confusion_matrix(y.iloc[test_ids], predicted, labels=VARIETIES).tolist()
        joblib.dump(model, output / (result['model'] + '.joblib'))
    partitions = frame[['record_id','site_id','variety']].copy()
    partitions['partition'] = ['holdout' if i in set(test_ids) else 'train' for i in range(len(frame))]
    partitions.to_csv(output / 'split_assignments.csv', index=False)
    (output / 'input_dataset.csv').write_bytes(Path(path).read_bytes())
    report = {'created_utc': datetime.now(timezone.utc).isoformat(), 'classes': VARIETIES, 'features': FEATURES,
              'contract': contract, 'comparisons': comparisons, 'selected_using_training_cv': winner,
              'grouped_holdout': True, 'holdout_site_overlap': 0, 'npk_used': False,
              'production_model_changed': False, 'application_integration_ready': False,
              'limitation': 'Experimental classification of recorded varieties; not a validated best-variety or crop-yield predictor. Source declarations require independent review.'}
    (output / 'training_run.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    return output, report
