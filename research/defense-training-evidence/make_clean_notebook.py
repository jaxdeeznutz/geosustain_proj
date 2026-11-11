import io
import json
from pathlib import Path
import tokenize


HERE = Path(__file__).resolve().parent
SOURCE = HERE.parent / 'colab-seven-crop' / 'GeoSustain_Seven_Crops_No_NPK.ipynb'
TARGET = HERE / 'GeoSustain_Colab_Training_Comparison.ipynb'


def clean_code(source):
    tokens = tokenize.generate_tokens(io.StringIO(source).readline)
    return tokenize.untokenize(token for token in tokens if token.type != tokenize.COMMENT)


notebook = json.loads(SOURCE.read_text(encoding='utf-8'))
notebook['cells'].insert(0, {
    'cell_type': 'markdown',
    'metadata': {},
    'source': [
        '# GeoSustain training and model comparison\n',
        '\n',
        'Run this notebook in Google Colab and save your executed copy with its outputs. '
        'The `results/` folder contains an earlier recorded run; the blank notebook itself is a reproducible procedure, not proof that a new run occurred.\n',
        '\n',
        'The exact input CSV is also provided in `data/`. Code cells are kept free of inline comments; each markdown cell explains the following code.\n',
    ],
})
for cell in notebook['cells']:
    if cell['cell_type'] == 'code':
        cell['source'] = clean_code(''.join(cell['source'])).splitlines(keepends=True)
        cell['outputs'] = []
        cell['execution_count'] = None
notebook['metadata']['colab']['name'] = TARGET.name
TARGET.write_text(json.dumps(notebook, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
print(TARGET)
