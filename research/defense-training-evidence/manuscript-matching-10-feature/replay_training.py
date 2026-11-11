import csv
import hashlib
import json
from pathlib import Path

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


FEATURES = ['N', 'P', 'K', 'temperature', 'humidity', 'ph', 'rainfall', 'ndvi', 'elevation', 'slope']
CROPS = {'banana', 'cacao', 'coconut', 'durian', 'mango', 'rice', 'rubber'}
SOURCE_SHA256 = '1a6dcf3b22c20ff51c0ef7eee310df3ad5d359263d78d1a93e2dbaa7245ec03a'


def replay(dataset, output):
    dataset = Path(dataset)
    output = Path(output)
    if hashlib.sha256(dataset.read_bytes()).hexdigest() != SOURCE_SHA256:
        raise ValueError('The CSV does not match the recorded source hash.')

    frame = pd.read_csv(dataset)
    if not set(FEATURES + ['label']) <= set(frame):
        raise ValueError('The CSV is missing model features or labels.')
    original_rows = len(frame)
    frame['label'] = frame['label'].astype(str).str.strip().str.lower()
    frame = frame.loc[frame.label.isin(CROPS), FEATURES + ['label']].copy()
    filtered_rows = len(frame)
    frame[FEATURES] = frame[FEATURES].apply(pd.to_numeric, errors='raise')
    if not np.isfinite(frame[FEATURES].to_numpy(dtype=float)).all():
        raise ValueError('The CSV contains nonfinite feature values.')
    if frame.groupby(FEATURES, dropna=False).label.nunique().gt(1).any():
        raise ValueError('Identical inputs have conflicting labels.')
    frame = frame.drop_duplicates(FEATURES + ['label']).reset_index(drop=True)
    if set(frame.label) != CROPS:
        raise ValueError('The filtered dataset must cover all seven crops.')

    train, holdout = train_test_split(np.arange(len(frame)), test_size=.20, stratify=frame.label, random_state=42)
    keys = pd.util.hash_pandas_object(frame[FEATURES], index=False).astype(str)
    if set(keys.iloc[train]) & set(keys.iloc[holdout]):
        raise ValueError('Duplicate inputs cross the train and holdout split.')
    x_train, y_train = frame.iloc[train][FEATURES], frame.iloc[train].label
    x_holdout, y_holdout = frame.iloc[holdout][FEATURES], frame.iloc[holdout].label

    models = {
        'decision_tree': DecisionTreeClassifier(max_depth=14, min_samples_leaf=6, min_samples_split=12, class_weight='balanced', random_state=42),
        'svm': make_pipeline(StandardScaler(), SVC(C=10, kernel='rbf', gamma='scale', class_weight='balanced', random_state=42)),
        'random_forest': RandomForestClassifier(n_estimators=500, max_depth=14, min_samples_leaf=6, min_samples_split=12, max_features='sqrt', class_weight='balanced_subsample', random_state=42, n_jobs=2),
    }
    output.mkdir(parents=True, exist_ok=True)
    rows = []
    reports = {}
    labels = sorted(CROPS)
    for name, model in models.items():
        model.fit(x_train, y_train)
        predicted = model.predict(x_holdout)
        rows.append({
            'model': name,
            'holdout_accuracy': float(accuracy_score(y_holdout, predicted)),
            'holdout_f1_macro': float(f1_score(y_holdout, predicted, average='macro', zero_division=0)),
        })
        reports[name] = {
            'classification_report': classification_report(y_holdout, predicted, labels=labels, output_dict=True, zero_division=0),
            'confusion_matrix': confusion_matrix(y_holdout, predicted, labels=labels).tolist(),
        }

    with (output / 'comparison.csv').open('w', newline='', encoding='utf-8') as handle:
        writer = csv.DictWriter(handle, fieldnames=['model', 'holdout_accuracy', 'holdout_f1_macro'])
        writer.writeheader()
        writer.writerows(rows)
    result = {
        'source_sha256': SOURCE_SHA256,
        'source_rows': original_rows,
        'filtered_rows': filtered_rows,
        'duplicate_rows_removed_before_split': filtered_rows - len(frame),
        'unique_rows': len(frame),
        'train_rows': len(train),
        'holdout_rows': len(holdout),
        'feature_order': FEATURES,
        'versions': {'scikit_learn': sklearn.__version__, 'numpy': np.__version__, 'pandas': pd.__version__},
        'comparison': rows,
        'details': reports,
    }
    (output / 'replay_report.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    return result


if __name__ == '__main__':
    here = Path(__file__).resolve().parent
    result = replay(here / 'data' / 'Crop_recommendation_with_gis.csv', here / 'local_replay_results')
    print(json.dumps({key: result[key] for key in ('source_rows', 'filtered_rows', 'unique_rows', 'train_rows', 'holdout_rows', 'comparison')}, indent=2))
