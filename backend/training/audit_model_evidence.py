"""Read-only local model/data audit; writes research evidence, never model assets."""
import argparse
import ast
from datetime import datetime, timezone
import hashlib
import importlib.metadata
import json
from pathlib import Path
import platform
import sys

import pandas as pd
from sklearn.model_selection import train_test_split

BACKEND = Path(__file__).resolve().parents[1]
REPO = BACKEND.parent
sys.path.insert(0, str(BACKEND))
from crop_requirements import REQUIREMENTS
from model_artifacts import APPROVED_LABELS, FEATURES, load_model_artifact
from training.climate_training_contract import TRAINING_SOURCES, INFERENCE_PERIODS, validate_training_periods


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def row_keys(frame, features):
    return [hashlib.sha256(json.dumps([float(v) for v in row], separators=(',', ':')).encode()).hexdigest()
            for row in frame[features].to_numpy()]


def dataset_inventory(path):
    frame = pd.read_csv(path)
    features = [f for f in FEATURES if f in frame]
    return {'path': str(path.relative_to(REPO)), 'sha256': sha(path), 'bytes': path.stat().st_size,
            'rows': len(frame), 'classes': frame['label'].value_counts().sort_index().to_dict(),
            'columns': list(frame), 'nulls': frame.isna().sum().to_dict(),
            'duplicate_full_rows_beyond_first': int(frame.duplicated().sum()),
            'duplicate_feature_rows_beyond_first': len(frame)-len(set(row_keys(frame, features))),
            'numeric_ranges': {f: {'minimum': float(frame[f].min()), 'maximum': float(frame[f].max())} for f in features},
            'independent_observation_ids_present': False,
            'scientific_provenance': 'No row-level independent farm/observation IDs, measurement dates, nutrient units/methods or verified climate periods in CSV.'}


def probe_deployed_health(url):
    import requests
    result = {'url': url, 'operation': 'read-only bounded unauthenticated GET /health', 'verified': False}
    try:
        with requests.get(url, timeout=(3, 12), stream=True) as response:
            result['http_status'] = response.status_code
            response.raise_for_status()
            data = bytearray()
            for chunk in response.iter_content(8192):
                data.extend(chunk)
                if len(data) > 1024*1024:
                    raise ValueError('Oversized health response')
        payload = json.loads(data)
        model = payload.get('model', {})
        result['model_version'] = model.get('model_version')
        result['artifact_version_on_disk'] = model.get('artifact_version_on_disk')
        result['metadata_status'] = model.get('metadata_status')
        result['verified'] = bool(result['model_version'] and result['model_version'] == result['artifact_version_on_disk'])
    except Exception as exc:
        result['reason'] = f'{type(exc).__name__}; deployed model identity not established by this attempt.'
    return result


def audit(output, manuscript=None, live_health=False):
    output = Path(output).resolve()
    evidence_root = (REPO/'defense-evidence/capstone-fix-execution/phase-04').resolve()
    if output != evidence_root and not output.is_relative_to(evidence_root):
        raise ValueError('Audit evidence must remain inside Phase 4 evidence; model directories are forbidden.')
    before = {name: sha(BACKEND/name) for name in ('crop_model.pkl', 'crop_model_features.pkl', 'crop_model_metadata.json',
                                                    'Crop_recommendation.csv', 'Crop_recommendation_with_gis.csv',
                                                    'training/train_model.py', 'training/climate_training_contract.py')}
    loaded = load_model_artifact()
    classes = [str(c) for c in loaded.model.classes_]
    catalog = [str(c).lower() for c in REQUIREMENTS]
    base = pd.read_csv(BACKEND/'Crop_recommendation.csv')
    augmented = pd.read_csv(BACKEND/'Crop_recommendation_with_gis.csv')
    common = list(base.drop(columns='label').columns)
    base_keys = set(row_keys(base, common))
    matched = [key for key in row_keys(augmented, common) if key in base_keys]
    a, b = train_test_split(augmented.index, test_size=.2, stratify=augmented.label, random_state=42)
    keys = row_keys(augmented, FEATURES)
    overlap = set(keys[i] for i in a) & set(keys[i] for i in b)
    tree = ast.parse((BACKEND/'training/train_model.py').read_text(encoding='utf-8'))
    literals = {}
    for node in tree.body:
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name) and target.id in ('CROP_GIS_RANGES', 'LOCAL_CROP_PROFILES'):
                    literals[target.id] = ast.literal_eval(node.value)
    try:
        validate_training_periods()
        guard = {'blocked': False}
    except ValueError as exc:
        guard = {'blocked': True, 'reason': str(exc)}
    comparison = BACKEND/'model_comparison_report.json'
    report = {'recorded_at_utc': datetime.now(timezone.utc).isoformat(),
              'scope': 'Read-only exact local artifact/data/code inventory; no retraining, publication or new agricultural accuracy claim.',
              'local_model': {'sha256': loaded.version, 'bytes': (BACKEND/'crop_model.pkl').stat().st_size,
                              'classes': classes, 'features': list(loaded.model.feature_names_in_),
                              'parameters': loaded.model.get_params(), 'metadata': loaded.metadata,
                              'feature_sidecar_sha256': sha(BACKEND/'crop_model_features.pkl')},
              'class_contracts': {'artifact_classes': classes, 'current_training_approved': sorted(APPROVED_LABELS),
                                  'current_ranking_catalog': catalog,
                                  'artifact_outside_training_approved': sorted(set(classes)-APPROVED_LABELS),
                                  'ranking_catalog_outside_training_approved': sorted(set(catalog)-APPROVED_LABELS),
                                  'ranking_supported_exact_artifact_labels': sorted(set(catalog)&set(classes)),
                                  'note': 'Training approved labels and current ranking catalog are distinct. Mango is present in the runtime catalog despite being outside the 13-label training set. Phase 4 does not change either behavior.'},
              'runtime_environment': {'python': platform.python_version(), 'versions': {key: importlib.metadata.version(key)
                  for key in ('scikit-learn', 'numpy', 'scipy', 'pandas', 'joblib', 'threadpoolctl')},
                                      'historical_training_environment': 'Unverified; these installed versions do not recover the original training environment.'},
              'datasets': [dataset_inventory(BACKEND/name) for name in ('Crop_recommendation.csv', 'Crop_recommendation_with_gis.csv')],
              'base_row_link_diagnostic': {'augmented_rows_matching_all_seven_base_numeric_fields': len(matched),
                                          'unique_base_numeric_rows_matched': len(set(matched)),
                                          'limitation': 'Exact numeric matches only; unmatched rows are not proven independent field observations and exact artifact lineage remains unverified.'},
              'hypothetical_row_split_diagnostic': {'basis': 'Current augmented CSV only, 80/20 stratified random row split with seed 42. NOT a recovered historical/Table 13 split.',
                                                    'train_rows': len(a), 'test_rows': len(b),
                                                    'distinct_feature_rows_on_both_sides': len(overlap),
                                                    'holdout_rows_with_an_exact_training_feature_duplicate': sum(keys[i] in overlap for i in b)},
              'documented_training_code': {'sha256': sha(BACKEND/'training/train_model.py'),
                                          'synthetic_local_profile_labels': sorted(literals['LOCAL_CROP_PROFILES']),
                                          'synthetic_local_rows_declared': sum(v['count'] for v in literals['LOCAL_CROP_PROFILES'].values()),
                                          'gis_proxy_labels': sorted(literals['CROP_GIS_RANGES']),
                                          'processing_order': ['Guard compatible climate periods before reading or training', 'Synthetic local crop rows',
                                                               'Approved label filter', 'Per-class replacement sampling before split',
                                                               'Label-conditioned synthetic GIS features', 'Stratified row split', 'Model comparison and publication'],
                                          'risk': 'Duplicate resampling before partition can leak exact observations. Label-conditioned synthetic GIS and local profiles make held-out synthetic classification unsuitable as independent field validation.'},
              'measurement_contract': {'training_sources': TRAINING_SOURCES, 'inference_periods': INFERENCE_PERIODS, 'guard': guard,
                                       'nutrients': 'N/P/K physical units, measurement methods, provenance and compatibility unresolved; no conversions invented.',
                                       'independent_real_records': 'No verified independently grouped Panabo crop outcome records identified in these CSVs.'},
              'table13_trace': {'pdf_page': 91, 'status': 'unresolved_original_experiment',
                               'reported_percentages_only': {
                                   'decision_tree': {'accuracy': 79.86, 'precision_macro': 80.56, 'recall_macro': 79.86, 'f1_macro': 79.80, 'f1_weighted': 79.80},
                                   'svm': {'accuracy': 84.39, 'precision_macro': 84.62, 'recall_macro': 84.39, 'f1_macro': 84.32, 'f1_weighted': 84.32},
                                   'random_forest': {'accuracy': 87.78, 'precision_macro': 88.15, 'recall_macro': 87.78, 'f1_macro': 87.57, 'f1_weighted': 87.57}},
                               'comparison_file_present': comparison.exists(),
                               'missing_links': ['Original exact dataset/version and independent record lineage', 'Original train/test membership and preprocessing/resampling records',
                                                 'Original machine-readable per-class metrics/predictions/weighted F1 and confusion matrices',
                                                 'Experiment environment, timestamp and artifact hash binding Table 13 to shipped pickle'],
                               'note': 'Transcribed manuscript claims, not newly measured or reproduced results. Do not substitute a controlled tooling run for Table 13.'},
              'deployed_identity': probe_deployed_health('https://geosustain.onrender.com/health') if live_health
                  else {'verified': False, 'reason': 'Live identity not probed by this audit invocation; local bytes are not proof of deployed parity.'}}
    if manuscript and Path(manuscript).exists():
        import pymupdf as fitz
        path = Path(manuscript)
        document = fitz.open(path)
        page = document[90]
        text = page.get_text()
        assert all(value in text for value in ('79.86%', '84.39%', '87.78%', 'Table 13'))
        report['table13_trace']['manuscript'] = {'filename': path.name, 'sha256': sha(path), 'pages': len(document), 'page': 91}
        output.mkdir(parents=True, exist_ok=True)
        page.get_pixmap(matrix=fitz.Matrix(1.4, 1.4)).save(output/'manuscript-table13-page91.png')
        (output/'manuscript-table13-page91.txt').write_text(text, encoding='utf-8')
    output.mkdir(parents=True, exist_ok=True)
    (output/'model-data-audit.json').write_text(json.dumps(report, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    assert before == {name: sha(BACKEND/name) for name in before}, 'Audit changed protected production inputs'
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=REPO/'defense-evidence/capstone-fix-execution/phase-04/audit')
    parser.add_argument('--manuscript', type=Path, default=REPO.parent/'GEOSUSTAIN_MANUSCRIPT.pdf')
    parser.add_argument('--live-health', action='store_true')
    args = parser.parse_args()
    result = audit(args.output, args.manuscript, args.live_health)
    print(f'Audit saved; local model {result["local_model"]["sha256"]}; Table 13 original experiment unresolved; no production assets changed.')


if __name__ == '__main__':
    main()
