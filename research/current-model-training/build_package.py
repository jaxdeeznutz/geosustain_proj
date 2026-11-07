"""Build a portable, self-contained Colab package from the installed model basis.

Does not merge unmatched observations, fabricate labels, train, or activate models.
"""
import ast
import base64
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[2]
STARTER = ROOT / 'research/colab-seven-crop'
NAME = 'GeoSustain_Current_Model_Training_2026-11-07'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def build():
    spec = importlib.util.spec_from_file_location('starter_builder', STARTER / 'make_notebook.py')
    maker = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(maker)
    original_notebook = maker.build()
    metadata = json.loads((ROOT / 'backend/crop_model_metadata.json').read_text())
    manifest = json.loads((STARTER / 'data/dataset_manifest.json').read_text())
    if metadata['training']['dataset_sha256'] != manifest['dataset_sha256']:
        raise ValueError('Starter dataset differs from the installed model training basis.')
    if sha((ROOT / 'backend/crop_model.pkl').read_bytes()) != metadata['model_version']:
        raise ValueError('Installed model bytes differ from their metadata.')
    if metadata['feature_names'] != maker.FEATURES or metadata['classes'] != maker.LABELS:
        raise ValueError('Current model inputs/classes differ from the package contract.')
    folder = ROOT / 'output' / NAME
    folder.mkdir(parents=True, exist_ok=True)

    def copy(source, relative):
        destination = folder / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)

    for relative in ['train_without_npk.py', 'requirements.txt', 'data/seven_crop_without_npk.csv', 'data/dataset_manifest.json']:
        copy(STARTER / relative, relative)
    # The notebook writes its embedded trainer with LF bytes on every platform.
    # Match those bytes in the portable archive instead of carrying Windows CRLF.
    for relative in ['train_without_npk.py', 'requirements.txt']:
        (folder / relative).write_bytes((STARTER / relative).read_text(encoding='utf-8').encode('utf-8'))
    variety_folder = folder / 'banana_varieties'
    variety_folder.mkdir(exist_ok=True)
    copy(Path(__file__).with_name('train_banana_varieties.py'), 'banana_varieties/train_banana_varieties.py')
    variety_spec = importlib.util.spec_from_file_location('variety_trainer', Path(__file__).with_name('train_banana_varieties.py'))
    variety_trainer = importlib.util.module_from_spec(variety_spec)
    variety_spec.loader.exec_module(variety_trainer)
    template = (','.join(variety_trainer.COLUMNS) + '\n').encode('utf-8')
    (variety_folder / 'matched_variety_observations.csv').write_bytes(template)
    (variety_folder / 'dataset_contract.json').write_text(json.dumps({
        'dataset_sha256': sha(template), 'target': 'observed_banana_variety',
        'data_basis': 'pending_matched_observations', 'units': variety_trainer.UNITS,
        'periods': variety_trainer.PERIODS, 'classes': variety_trainer.VARIETIES,
        'note': 'Requested schema only; no observations or cultivar labels have been invented.'}, indent=2), encoding='utf-8')
    old_source = subprocess.check_output(['git','show','7a5825e:backend/rainfallDatasets.py'], cwd=ROOT).decode('utf-8')
    old_metadata = json.loads(subprocess.check_output(['git','show','7a5825e:backend/crop_model_metadata.json'], cwd=ROOT))
    old_map = next(ast.literal_eval(node.value) for node in ast.parse(old_source).body
                   if isinstance(node, ast.Assign) and any(isinstance(n, ast.Name) and n.id == 'PANABO_CROP_MAP' for n in node.targets))
    audit = {
        'audited_commit': '7a5825e', 'old_trained_classes': old_metadata['classes'],
        'old_model_version': old_metadata['model_version'],
        'old_display_mapping': {key: old_map[key] for key in ['banana','muskmelon']},
        'separate_cavendish_lakatan_saba_trained_classes_present': False,
        'findings': [
            'The trained banana class was displayed as Banana (Cavendish/Lakatan); Cavendish and Lakatan were not separately learned.',
            'A legacy map also renamed muskmelon to Banana (Saba). This is not Saba training evidence; muskmelon was absent from the audited 17-class artifact.',
            'Old variety/profile names do not identify the cultivar in any generic Banana training row.',
            'The new notebook does not reuse these legacy substitutions as variety labels.'
        ]}
    (variety_folder / 'old_variety_handling_audit.json').write_text(json.dumps(audit, indent=2), encoding='utf-8')
    readiness = variety_trainer.readiness(variety_folder / 'matched_variety_observations.csv')
    readiness.update(training_ready=False, missing='Matched environmental observations labelled by banana variety and independent site IDs.')
    evidence_folder = ROOT / 'research/banana-variety-evidence'
    for name in ['published_requirements.json', 'published_trial_observations_partial.json', 'evidence_manifest.json']:
        copy(evidence_folder / name, 'banana_varieties/' + name)
    partial = json.loads((evidence_folder / 'published_trial_observations_partial.json').read_text(encoding='utf-8'))
    readiness['published_partial_trial_records'] = partial['record_count']
    readiness['partial_records_used_for_fitting'] = False
    (variety_folder / 'readiness.json').write_text(json.dumps(readiness, indent=2), encoding='utf-8')
    copy(ROOT / 'backend/crop_model_metadata.json', 'current_system/installed_model_metadata.json')
    copy(ROOT / 'assets/data/banana_varieties.json', 'current_system/banana_varieties.json')
    for name in ['crop_requirements.py', 'seasonal_planting.py', 'seasonal_assessment.py',
                 'environmental_pipeline.py', 'spatial_provider.py', 'climate_contract.py',
                 'model_ranking.py', 'model_explainability.py', 'crop_varieties.py']:
        copy(ROOT / 'backend' / name, 'current_system/source/' + name)

    # Pure reference constants, including the actual URLs and terrain criteria.
    spec = importlib.util.spec_from_file_location('reference_constants', ROOT / 'backend/crop_requirements.py')
    references = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(references)
    (folder / 'current_system/crop_reference_tables.json').write_text(json.dumps({
        'version': references.VERSION, 'factors': references.FACTORS,
        'requirements': references.REQUIREMENTS, 'sources': references.SOURCES,
        'used_as_training_rows': False}, indent=2), encoding='utf-8')
    contract = {
        'installed_model_version': metadata['model_version'], 'features': metadata['feature_names'],
        'classes': metadata['classes'], 'npk_used': False,
        'algorithms': ['Decision Tree', 'SVM', 'Random Forest'],
        'training_dataset_sha256': manifest['dataset_sha256'],
        'training_rows': manifest['selected_rows'],
        'runtime_inputs': {
            'temperature': 'ERA5-Land mean air temperature across five completed calendar years, C',
            'rainfall': 'CHIRPS mean of five completed annual rainfall totals, mm/year',
            'humidity': 'Current humidity, percent; not an annual mean',
            'ph': 'OpenLandMap pH in water, 0-cm surface model, divided by 10',
            'ndvi': 'Recent usable Sentinel-2 vegetation reading',
            'elevation': 'SRTM terrain reference, m', 'slope': 'SRTM-derived slope, percent'},
        'separate_reference_layers': ['crop requirements including rainfall/elevation/slope',
            'seasonal historical-month moisture screening', 'banana variety descriptions'],
        'seasonal_layer_changes_model_probabilities': False,
        'banana_variety_prediction_classes': False,
        'optional_variety_training': {'classes': variety_trainer.VARIETIES, 'labelled_rows': 0,
                                      'training_ready': False, 'trainer_included': True,
                                      'published_partial_trial_records': partial['record_count']},
        'legacy_training_climate_periods_resolved': False,
        'annual_input_farm_prediction_validated': False,
        'unmatched_psa_and_environmental_data_used_as_training': False,
        'automatic_model_activation': False,
    }
    (folder / 'current_system/model_and_input_contract.json').write_text(json.dumps(contract, indent=2), encoding='utf-8')
    research = ROOT.parent / 'GeoSustain-banana-variety-research-2026-11-07'
    supplemental = ['production-labelled-records.json', 'area-labelled-records.json',
        'source-manifest.json', 'verification-summary.json', 'environmental-pilot.json',
        'environmental-pilot-verification.json', 'ENVIRONMENTAL_INPUTS.txt',
        'fetch_environmental_pilot.py', 'fetch_psa_banana_varieties.py']
    for name in supplemental:
        if not (research / name).is_file():
            raise FileNotFoundError(research / name)
        copy(research / name, 'supplemental_NOT_TRAINING/' + name)
    for item in research.iterdir():
        if item.is_file() and item.suffix in ('.json', '.txt', '.py') and item.name not in supplemental:
            copy(item, 'supplemental_NOT_TRAINING/' + item.name)
    guide = '''START HERE

Upload GeoSustain_Current_Model_Training_2026-11-07.ipynb using Colab File > Open
notebook > Upload. Do not upload it into the runtime Files sidebar. Choose
Runtime > Run all (CPU is enough). Enter your name in the configuration cell.
Save the executed notebook with outputs, and download the generated results ZIP.

TRAINING DATA: the exact 1,820 source rows used for the installed seven-input
prototype, with 1,394 unique rows after duplicate removal. The notebook trains
Decision Tree, SVM and Random Forest with a common holdout and training-only CV.
No NPK predictors. Seven crop groups, including one generic Banana class.

BANANA VARIETY SECTION: Cavendish, Lakatan and Saba have a separate trainer,
CSV schema and readiness check. Three published aggregate trial records are
included separately, with missing inputs retained. There are currently ZERO
complete compatible variety training rows, so separate fitting remains pending.
Lakatan and Saba guide values have their original periods, units and citations.
Trial site conditions are observations, not optimum growing ranges. They do not
describe independent Panabo farms or complete seven-input model records.
The old Banana (Cavendish/Lakatan) name was a display mapping of generic Banana.
The legacy muskmelon-to-Saba mapping is not reused. See the audit JSON.
When reviewed variety/site observations exist, the optional trainer compares
DT, SVM and RF with sites separated between holdout and cross-validation.
Its target is the observed variety, not proof of the best variety for a farm.

CURRENT SYSTEM REFERENCE: annual climate input policy; crop-specific rainfall,
slope and elevation reference criteria and citations; seasonal moisture code;
banana variety profiles; model ranking and explanation code; installed metadata.
These describe the app. They are not additional labelled farm training rows.

SUPPLEMENTAL_NOT_TRAINING: PSA Cavendish/Lakatan/Saba provincial records and
the 2010-2025 Panabo environmental point pilot. They are not matched farm
records and are excluded from fitting. No variety suitability labels invented.

The original labelled rows have unresolved climate periods and generated GIS
features. This package does not convert their rainfall values to annual values.
References do not prove accuracy on real farms. The app's annual-input scores
remain experimental. Future matched annual-input observations require a new
versioned training dataset and consistent training/inference definitions.

Seasonal advice and environmental reference comparisons remain separate from
RF class scores. Banana variety profiles do not create separate trained classes.
Training here creates candidates and evidence; it does not automatically change
Render, Vercel or the APK. Use the new result ZIP for reviewed integration.
'''
    (folder / 'START_HERE.txt').write_text(guide, encoding='utf-8')
    # Embed the current-system material in the notebook as an inspectable ZIP.
    import io
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, 'w', zipfile.ZIP_DEFLATED) as archive:
        for item in sorted(folder.rglob('*')):
            if item.is_file() and item.suffix not in ('.ipynb', '.zip') and item.name != 'package_manifest.json':
                archive.writestr(item.relative_to(folder).as_posix(), item.read_bytes())
    notebook = json.loads(original_notebook.read_text(encoding='utf-8'))
    heading = {'cell_type': 'markdown', 'id': 'current-system-guide', 'metadata': {},
        'source': ['# Current GeoSustain model training package\n', guide]}
    code = ("import base64, io, zipfile\nfrom pathlib import Path\n"
            f"CURRENT_PACKAGE_BASE64 = {base64.b64encode(buffer.getvalue()).decode()!r}\n"
            "package_path = Path('/content/geosustain_current_system') if Path('/content').is_dir() else Path('geosustain_current_system')\n"
            "package_path.mkdir(parents=True, exist_ok=True)\n"
            "with zipfile.ZipFile(io.BytesIO(base64.b64decode(CURRENT_PACKAGE_BASE64))) as archive:\n"
            "    archive.extractall(package_path)\n"
            "print((package_path / 'START_HERE.txt').read_text())\n"
            "print('Reference and supplemental files:', package_path)\n")
    extra = {'cell_type': 'code', 'id': 'current-system-materials',
             'metadata': {'cellView': 'form'}, 'source': code.splitlines(keepends=True),
             'execution_count': None, 'outputs': []}
    notebook['cells'] = [heading, extra] + notebook['cells']
    notebook['cells'].append({'cell_type': 'markdown', 'id': 'banana-varieties-guide', 'metadata': {},
        'source': ['## Banana varieties: Cavendish, Lakatan and Saba\n\n',
                   '**Separate variety training is pending matched data.** The old combined name was a display mapping, not two trained classes. ',
                   'The bundled CSV is a header-only template. Keep `TRAIN_BANANA_VARIETIES=False` until reviewed cultivar-labelled observations and their source/period contract are available. ',
                   'Do not duplicate/relabel generic Banana rows or attach one Panabo point to provincial production totals.\n']})
    variety_code = (
        "import importlib.util\n"
        "variety_folder = package_path / 'banana_varieties'\n"
        "print((variety_folder / 'old_variety_handling_audit.json').read_text())\n"
        "print((variety_folder / 'readiness.json').read_text())\n"
        "print('Variety CSV template:', variety_folder / 'matched_variety_observations.csv')\n"
        "published = json.loads((variety_folder / 'published_trial_observations_partial.json').read_text())\n"
        "print('Published aggregate trial evidence (not complete training rows):')\n"
        "display(pd.DataFrame([{'variety':r['observed_variety'], 'site':r['site_context']['location'], 'bunch_weight_kg':r['reported_mean_bunch_weight_kg'], 'training_ready':r['model_training_ready']} for r in published['records']]))\n"
        "print('Growing guides:', variety_folder / 'published_requirements.json')\n"
        "TRAIN_BANANA_VARIETIES = False\n"
        "if TRAIN_BANANA_VARIETIES:\n"
        "    spec = importlib.util.spec_from_file_location('banana_variety_training', variety_folder / 'train_banana_varieties.py')\n"
        "    trainer = importlib.util.module_from_spec(spec)\n"
        "    spec.loader.exec_module(trainer)\n"
        "    variety_output, variety_run = trainer.train(variety_folder / 'matched_variety_observations.csv', variety_folder / 'dataset_contract.json', WORK / 'variety_runs')\n"
        "    print('Variety experiment:', variety_output)\n"
        "else:\n"
        "    print('Banana varieties NOT trained: matched variety-labelled observations are missing.')\n")
    notebook['cells'].append({'cell_type':'code', 'id':'banana-varieties-training', 'metadata':{},
                              'source':variety_code.splitlines(keepends=True), 'execution_count':None, 'outputs':[]})
    notebook['metadata']['colab']['name'] = NAME + '.ipynb'
    path = folder / (NAME + '.ipynb')
    path.write_text(json.dumps(notebook, indent=1, ensure_ascii=False), encoding='utf-8')
    for cell in notebook['cells']:
        if cell['cell_type'] == 'code':
            ast.parse(''.join(cell['source']))
    hashes = {p.relative_to(folder).as_posix(): sha(p.read_bytes()) for p in folder.rglob('*') if p.is_file() and p.name != 'package_manifest.json'}
    (folder / 'package_manifest.json').write_text(json.dumps({
        'created_utc': datetime.now(timezone.utc).isoformat(), 'contract': contract,
        'files_sha256': hashes}, indent=2), encoding='utf-8')
    target = ROOT.parent / (NAME + '.zip')
    with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as archive:
        for item in sorted(folder.rglob('*')):
            if item.is_file(): archive.write(item, NAME + '/' + item.relative_to(folder).as_posix())
    shutil.copyfile(path, ROOT.parent / path.name)
    print(json.dumps({'archive': str(target), 'notebook': str(ROOT.parent / path.name),
                      'training_rows': manifest['selected_rows'], 'npk_used': False,
                      'banana_variety_classes_trained': False, 'file_count': len(hashes)}, indent=2))
    return target, ROOT.parent / path.name


if __name__ == '__main__':
    build()
