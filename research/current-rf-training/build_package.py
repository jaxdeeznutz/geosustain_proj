"""Build an unexecuted RF-only Colab starter from the verified active baseline."""
import ast
import base64
import hashlib
import json
from pathlib import Path
import shutil
import zipfile

import joblib

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
LEGACY = ROOT / 'research/colab-seven-crop'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build():
    metadata = json.loads((ROOT / 'backend/crop_model_metadata.json').read_text())
    artifact = ROOT / 'backend/crop_model.pkl'
    dataset = LEGACY / 'data/seven_crop_without_npk.csv'
    assert digest(artifact) == metadata['model_version']
    assert digest(dataset) == metadata['training']['dataset_sha256']
    model = joblib.load(artifact)
    assert type(model).__name__ == 'RandomForestClassifier'
    assert list(model.classes_) == metadata['classes']
    keys = ['n_estimators', 'max_depth', 'min_samples_leaf', 'min_samples_split',
            'max_features', 'class_weight', 'random_state', 'n_jobs']
    reference = {
        'algorithm': 'Random Forest', 'estimator': type(model).__name__,
        'crop_classes': metadata['classes'], 'feature_order': metadata['feature_names'],
        'baseline_parameters': {key: model.get_params()[key] for key in keys},
        'installed_artifact_sha256': digest(artifact), 'dataset_sha256': digest(dataset),
        'original_run_id': metadata['training']['provenance']['colab_run_id'],
        'original_training_timestamp_utc': metadata['training']['timestamp_utc'],
        'npk_used': False,
        'scope': 'Reference identity of the existing artifact, not results from this notebook.',
    }
    # Reuse the same audited validation/deduplication and split implementation.
    # Only these functions are copied; no alternative estimators are imported.
    original = (LEGACY / 'train_without_npk.py').read_text(encoding='utf-8')
    syntax = ast.parse(original)
    pieces = []
    for node in syntax.body:
        if isinstance(node, ast.FunctionDef) and node.name in {
            'file_hash', 'write_json', 'prepare_data', 'make_partitions'
        }:
            pieces.append(ast.get_source_segment(original, node))
    header = '''"""Random Forest only, seven crop classes, no NPK. Research outputs only."""
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
'''
    source = header + '\n\n' + '\n\n\n'.join(pieces) + '\n\n\n' + (HERE / 'rf_runner_source.txt').read_text(encoding='utf-8')
    ast.parse(source)
    (HERE / 'train_random_forest.py').write_text(source, encoding='utf-8')
    shutil.copyfile(dataset, HERE / 'seven_crop_without_npk.csv')
    shutil.copyfile(LEGACY / 'data/dataset_manifest.json', HERE / 'dataset_manifest.json')
    shutil.copyfile(LEGACY / 'requirements.txt', HERE / 'requirements.txt')
    (HERE / 'current_model_reference.json').write_text(json.dumps(reference, indent=2), encoding='utf-8')
    manifest = json.loads((HERE / 'dataset_manifest.json').read_text())
    cells = []

    def cell(kind, text):
        item = {'cell_type': kind, 'id': f'rf-seven-{len(cells):02}', 'metadata': {},
                'source': text.splitlines(keepends=True)}
        if kind == 'code':
            item.update(execution_count=None, outputs=[])
        cells.append(item)

    cell('markdown', '# GeoSustain: Random Forest for seven crops\n\n'
         'One classifier: **Random Forest**. Crop classes: Banana, Cacao, Coconut, Durian, Mango, Rice and Rubber. '
         'Seven inputs: temperature, humidity, soil pH, rainfall, NDVI, elevation and slope. **NPK excluded.**\n\n'
         '**Chapter 2 default:** results remain **N/A**. Training is disabled until you set `RUN_TRAINING = True`. '
         'This starter contains no executed outputs or previously computed performance scores. '
         'The existing-artifact reference is kept separate from any new run.\n')
    cell('markdown', '## 1. Prepare the runtime\n\nA CPU runtime is sufficient. The source CSV and Python code are embedded below.\n')
    dependencies = (HERE / 'requirements.txt').read_text().splitlines()
    cell('code', 'import sys, subprocess, json, base64\nfrom pathlib import Path\n'
         'try:\n    import google.colab\n    IN_COLAB = True\nexcept ImportError:\n    IN_COLAB = False\n'
         f'DEPENDENCIES = {dependencies!r}\n'
         'if IN_COLAB:\n    subprocess.check_call([sys.executable, "-m", "pip", "install", "--quiet", *DEPENDENCIES])\n'
         'PLATFORM = "google_colab" if IN_COLAB else "local"\n')
    cell('markdown', '## 2. Set the experiment\n\nKeep training disabled for the Chapter 2 N/A table. '
         'Only enable it when you intend to conduct and report an actual run. No algorithm selection or comparison is performed.\n')
    cell('code', 'RUN_TRAINING = False\nRESEARCHER_NAME = ""\nSEED = 42\nCV_FOLDS = 5\nFOREST_TREES = 500\n'
         'WORK = Path("/content/geosustain_rf_seven") if IN_COLAB else Path("geosustain_rf_seven")\n'
         'WORK.mkdir(parents=True, exist_ok=True)\n')
    cell('markdown', '## 3. Restore the exact dataset and training code\n\nThe CSV matches the dataset hash recorded for the installed seven-input Random Forest. '
         'The reference JSON identifies that existing artifact; a new run is recorded separately.\n')
    cell('code', f'DATASET_BASE64 = {base64.b64encode(dataset.read_bytes()).decode()!r}\n'
         f'TRAINER_SOURCE = {source!r}\nMANIFEST = json.loads({json.dumps(json.dumps(manifest))})\n'
         f'CURRENT_REFERENCE = json.loads({json.dumps(json.dumps(reference))})\n'
         'DATASET_PATH = WORK / "seven_crop_without_npk.csv"\nMANIFEST_PATH = WORK / "dataset_manifest.json"\n'
         'REFERENCE_PATH = WORK / "current_model_reference.json"\nTRAINER_PATH = WORK / "train_random_forest.py"\n'
         'DATASET_PATH.write_bytes(base64.b64decode(DATASET_BASE64))\n'
         'MANIFEST_PATH.write_text(json.dumps(MANIFEST, indent=2), encoding="utf-8")\n'
         'REFERENCE_PATH.write_text(json.dumps(CURRENT_REFERENCE, indent=2), encoding="utf-8")\n'
         'TRAINER_PATH.write_bytes(TRAINER_SOURCE.encode("utf-8"))\n'
         'namespace = {"__name__": "rf_colab_trainer", "__file__": str(TRAINER_PATH.resolve())}\n'
         'exec(compile(TRAINER_SOURCE, str(TRAINER_PATH), "exec"), namespace)\n')
    cell('markdown', '## 4. Inspect the preparation\n\nThese are dataset counts, not performance results. '
         'Exact duplicates are removed before the 80/20 stratified split. Five-fold cross-validation uses only training rows; the test set stays separate.\n')
    cell('code', 'import pandas as pd\nfrom IPython.display import display, Image\n'
         'frame, manifest, audit = namespace["prepare_data"](DATASET_PATH, MANIFEST_PATH)\n'
         'print("Algorithm: Random Forest")\nprint("Inputs:", namespace["FEATURES"])\n'
         'print("Crop classes:", namespace["LABELS"])\nprint("Dataset SHA-256:", audit["dataset_sha256"])\n'
         'print("Source rows:", audit["input_rows"], "Unique rows:", audit["unique_rows"])\n'
         'display(frame.head())\ndisplay(frame.groupby("label").size().rename("unique_rows").to_frame())\n')
    cell('markdown', '## 5. Results or actual training\n\nWith `RUN_TRAINING = False`, only the N/A table is shown. '
         'When enabled, this fits only Random Forest and computes results from this run. The model configuration follows the existing baseline; '
         'this notebook does not claim to compare or select algorithms.\n')
    cell('code', 'output_dir = results_zip = run = None\n'
         'if RUN_TRAINING:\n'
         '    output_dir, results_zip, run = namespace["run_training"](\n'
         '        DATASET_PATH, MANIFEST_PATH, REFERENCE_PATH, WORK / "runs",\n'
         '        seed=SEED, trees=FOREST_TREES, cv_folds=CV_FOLDS,\n'
         '        execution_platform=PLATFORM, researcher=RESEARCHER_NAME.strip() or "Not supplied")\n'
         '    display(pd.read_csv(output_dir / "metrics.csv"))\n'
         '    display(pd.read_csv(output_dir / "classification_report.csv", index_col=0))\n'
         '    display(Image(filename=str(output_dir / "confusion_matrix.png")))\n'
         'else:\n'
         '    display(pd.DataFrame([{ "Algorithm": "Random Forest", "Accuracy": "N/A",\n'
         '        "Precision": "N/A", "Recall": "N/A", "F1-score": "N/A" }]))\n'
         '    print("Training disabled. No evaluation was performed by this notebook.")\n')
    cell('markdown', '## 6. Save the evidence\n\nFor Chapter 2, save the preparation code and N/A table. '
         'After actual training, save the executed notebook **with outputs** and the downloaded ZIP. '
         'That ZIP includes the metrics, confusion matrix, fold scores, train/test assignments, predictions, model, settings and hashes. '
         'Run metadata supports replay but does not independently prove where execution occurred.\n')
    cell('code', 'if results_zip is not None:\n'
         '    print("Fresh run:", run["run_id"])\n    print("Evidence:", results_zip)\n'
         '    if IN_COLAB:\n        from google.colab import files\n        files.download(str(results_zip))\n'
         'else:\n    print("No completed training evidence yet; results remain N/A.")\n')
    cell('markdown', '## Data limits\n\nThe unchanged CSV mixes original Kaggle-based rows with generated crop profiles and GIS predictors. '
         'Cacao, durian and rubber use generated profiles. Independent farm grouping and consistent labelled climate periods are unavailable. '
         'Any computed scores describe this dataset experiment, not verified field or annual-input accuracy. '
         'Banana is one crop class; these labels do not distinguish varieties. '
         'A newly trained artifact does not automatically replace the installed application model.\n')
    notebook = {'nbformat': 4, 'nbformat_minor': 5, 'metadata': {
        'colab': {'name': 'GeoSustain_Random_Forest_Seven_Crops.ipynb', 'provenance': []},
        'kernelspec': {'display_name': 'Python 3', 'language': 'python', 'name': 'python3'},
        'language_info': {'name': 'python', 'version': '3.11'}}, 'cells': cells}
    (HERE / 'GeoSustain_Random_Forest_Seven_Crops.ipynb').write_text(json.dumps(notebook, indent=1), encoding='utf-8')
    package_files = ['GeoSustain_Random_Forest_Seven_Crops.ipynb', 'train_random_forest.py',
                     'seven_crop_without_npk.csv', 'dataset_manifest.json', 'current_model_reference.json',
                     'requirements.txt', 'README.txt']
    destination = Path.home() / 'Downloads/GeoSustain_Random_Forest_Seven_Crops'
    destination.mkdir(exist_ok=True)
    for name in package_files:
        shutil.copyfile(HERE / name, destination / name)
    archive = destination.with_suffix('.zip')
    with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED) as zipped:
        for name in package_files:
            zipped.write(destination / name, arcname=destination.name + '/' + name)
    print(json.dumps({'folder': str(destination), 'zip': str(archive), 'default_training': False}, indent=2))
    return destination


if __name__ == '__main__':
    build()
