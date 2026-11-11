import base64
import json
from pathlib import Path


HERE = Path(__file__).resolve().parent
TARGET = HERE / 'GeoSustain_Manuscript_Model_Comparison_10_Features.ipynb'
DATASET = HERE / 'data' / 'Crop_recommendation_with_gis.csv'
TRAINER = HERE / 'replay_training.py'


def markdown(identifier, source):
    return {'cell_type': 'markdown', 'id': identifier, 'metadata': {}, 'source': source.splitlines(keepends=True)}


def code(identifier, source):
    return {'cell_type': 'code', 'id': identifier, 'metadata': {}, 'execution_count': None, 'outputs': [], 'source': source.splitlines(keepends=True)}


trainer_source = TRAINER.read_text(encoding='utf-8').partition("\nif __name__ == '__main__':")[0]
encoded_dataset = base64.b64encode(DATASET.read_bytes()).decode('ascii')
notebook = {
    'nbformat': 4,
    'nbformat_minor': 5,
    'metadata': {
        'colab': {'name': TARGET.name, 'provenance': []},
        'kernelspec': {'display_name': 'Python 3', 'language': 'python', 'name': 'python3'},
        'language_info': {'name': 'python'},
    },
    'cells': [
        markdown('intro', '# GeoSustain manuscript model comparison\n\nThis notebook reproduces the ten-input Decision Tree, SVM, and Random Forest holdout comparison described in the November 11 manuscript and recorded for the installed backend model. Its input is the exact legacy 4,420-row CSV embedded below. The notebook has no output until you run it in Colab and save the executed copy. The results are not field-validated accuracy for Panabo farms.\n'),
        markdown('dataset', '## Load the recorded source CSV\n\nThe embedded bytes match the installed model metadata SHA-256. The training code retains only seven approved crops, removes exact duplicate inputs before splitting, and never creates or relabels rows. Other crop rows remain in the raw CSV for provenance.\n'),
        code('load-data', "import base64\nimport hashlib\nfrom pathlib import Path\n\nDATASET_BASE64 = '" + encoded_dataset + "'\nDATASET_PATH = Path('Crop_recommendation_with_gis.csv')\nDATASET_PATH.write_bytes(base64.b64decode(DATASET_BASE64))\nprint('Source SHA-256:', hashlib.sha256(DATASET_PATH.read_bytes()).hexdigest())\n"),
        markdown('method', '## Reproduce the ten-input experiment\n\nInputs are N, P, K, temperature, humidity, pH, rainfall, NDVI, elevation, and slope. The same seed 42 stratified 80/20 split and recorded model settings are used for all three candidates. Metrics are computed on the same 279 holdout rows. This recorded comparison has no cross-validation score; the previous seven-input notebook is a separate experiment.\n'),
        code('trainer', trainer_source + '\n'),
        code('run-training', "from IPython.display import display\n\nOUTPUT_DIR = Path('geosustain_10_feature_results')\nresult = replay(DATASET_PATH, OUTPUT_DIR)\nsummary = pd.DataFrame(result['comparison'])\ndisplay(summary.style.format({'holdout_accuracy': '{:.2%}', 'holdout_f1_macro': '{:.2%}'}))\nprint('Rows:', result['source_rows'], 'raw;', result['filtered_rows'], 'seven-crop;', result['unique_rows'], 'unique;', result['train_rows'], 'train;', result['holdout_rows'], 'holdout')\nprint('Versions:', result['versions'])\n"),
        markdown('results', '## Inspect model comparison and per-crop results\n\nThe manuscript rounds Decision Tree to 76.70% accuracy and 69.51% macro F1, SVM to 83.15% and 78.36%, and Random Forest to 86.02% and 80.00%. Small differences can occur if Colab has different library versions. Macro F1 gives each crop class equal weight. These holdout rows come from the same legacy augmented source, not independent farms.\n'),
        code('chart', "import matplotlib.pyplot as plt\n\nchart = summary.set_index('model')[['holdout_accuracy', 'holdout_f1_macro']] * 100\nax = chart.plot(kind='bar', figsize=(9, 5), color=['#087d43', '#69a6d3'])\nax.set_title('GeoSustain ten-input model comparison')\nax.set_ylabel('Holdout score (%)')\nax.set_ylim(0, 100)\nax.tick_params(axis='x', rotation=0)\nplt.tight_layout()\nplt.savefig(OUTPUT_DIR / 'model_comparison.png', dpi=160)\ndisplay(chart.round(2))\nplt.show()\nfor name, details in result['details'].items():\n    print(name)\n    display(pd.DataFrame(details['classification_report']).T.round(3))\n"),
        markdown('export', '## Save your own execution evidence\n\nAfter the cells finish, keep this executed notebook in your Drive. The final cell downloads a ZIP with the comparison CSV, chart, and replay report. The supplied recorded report identifies the earlier run, while this saved notebook documents your new Colab execution.\n'),
        code('download', "import shutil\nfrom google.colab import files\n\narchive = shutil.make_archive('geosustain_10_feature_results', 'zip', OUTPUT_DIR)\nfiles.download(archive)\n"),
    ],
}
TARGET.write_text(json.dumps(notebook, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
print(TARGET)
