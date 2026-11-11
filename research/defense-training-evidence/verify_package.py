import ast
import csv
import hashlib
import io
import json
from pathlib import Path
import tokenize


HERE = Path(__file__).resolve().parent


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


manifest = json.loads((HERE / 'data/dataset_manifest.json').read_text(encoding='utf-8'))
assert sha256(HERE / 'data/seven_crop_without_npk.csv') == manifest['dataset_sha256']

with (HERE / 'data/seven_crop_without_npk.csv').open(newline='', encoding='utf-8') as handle:
    input_rows = list(csv.DictReader(handle))
assert len(input_rows) == 1820

with (HERE / 'data/training_rows_deduplicated.csv').open(newline='', encoding='utf-8') as handle:
    unique_rows = list(csv.DictReader(handle))
assert len(unique_rows) == 1394

notebook = json.loads((HERE / 'GeoSustain_Colab_Training_Comparison.ipynb').read_text(encoding='utf-8'))
assert notebook['nbformat'] == 4
code_cells = [cell for cell in notebook['cells'] if cell['cell_type'] == 'code']
assert code_cells
for cell in code_cells:
    source = ''.join(cell['source'])
    ast.parse(source)
    assert cell['execution_count'] is None and not cell['outputs']
    assert not any(token.type == tokenize.COMMENT for token in tokenize.generate_tokens(io.StringIO(source).readline))

with (HERE / 'results/comparison.csv').open(newline='', encoding='utf-8') as handle:
    comparison = list(csv.DictReader(handle))
assert {row['model'] for row in comparison} == {'decision_tree', 'svm', 'random_forest'}
assert max(comparison, key=lambda row: float(row['cv_f1_macro_mean']))['model'] == 'random_forest'

record = json.loads((HERE / 'results/training_run.json').read_text(encoding='utf-8'))
assert record['npk_used'] is False
assert record['selection']['selected_model'] == 'random_forest'

for name, expected in json.loads((HERE / 'results/artifact_hashes.json').read_text(encoding='utf-8')).items():
    copied = HERE / 'results' / name
    if copied.is_file():
        assert sha256(copied) == expected, name

print('Verified: dataset, 1,394 unique rows, clean notebook, comparison, and copied run artifacts.')
