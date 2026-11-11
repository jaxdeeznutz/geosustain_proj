import ast
import base64
import hashlib
import io
import json
from pathlib import Path
import tokenize


HERE = Path(__file__).resolve().parent
DATASET = HERE / 'data' / 'Crop_recommendation_with_gis.csv'
REPORT = json.loads((HERE / 'recorded' / 'training_report.json').read_text(encoding='utf-8'))
METADATA = json.loads((HERE / 'recorded' / 'installed_model_metadata.json').read_text(encoding='utf-8'))
REPLAY = json.loads((HERE / 'local_replay_results' / 'replay_report.json').read_text(encoding='utf-8'))
NOTEBOOK = json.loads((HERE / 'GeoSustain_Manuscript_Model_Comparison_10_Features.ipynb').read_text(encoding='utf-8'))

source_hash = hashlib.sha256(DATASET.read_bytes()).hexdigest()
assert source_hash == REPORT['data_audit']['source_sha256']
assert source_hash == METADATA['training']['dataset_sha256']
assert REPORT['feature_order'] == METADATA['feature_names'] == REPLAY['feature_order']
assert REPORT['data_audit']['unique_rows'] == REPLAY['unique_rows'] == 1394
assert REPORT['split']['holdout_rows'] == REPLAY['holdout_rows'] == 279

for row in REPLAY['comparison']:
    recorded = REPORT['comparison'][row['model']]
    assert abs(row['holdout_accuracy'] - recorded['accuracy']) < 1e-12
    assert abs(row['holdout_f1_macro'] - recorded['f1_macro']) < 1e-12

assert NOTEBOOK['nbformat'] == 4
code_cells = [cell for cell in NOTEBOOK['cells'] if cell['cell_type'] == 'code']
assert len(code_cells) == 5
for cell in code_cells:
    source = ''.join(cell['source'])
    ast.parse(source)
    assert cell['execution_count'] is None and not cell['outputs']
    assert not any(token.type == tokenize.COMMENT for token in tokenize.generate_tokens(io.StringIO(source).readline))

load_cell = ''.join(next(cell['source'] for cell in code_cells if cell['id'] == 'load-data'))
assignment = next(node for node in ast.parse(load_cell).body if isinstance(node, ast.Assign) and isinstance(node.targets[0], ast.Name) and node.targets[0].id == 'DATASET_BASE64')
assert base64.b64decode(ast.literal_eval(assignment.value)) == DATASET.read_bytes()

print('Verified: ten-feature dataset, installed metadata, exact recorded metrics, local replay, and clean Colab notebook.')
