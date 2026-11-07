"""Execute a COPY for software QA; keep the owner's starter notebook blank."""
import json
from pathlib import Path
import sys
import nbformat
from nbclient import NotebookClient
from jupyter_client import KernelManager

ROOT = Path(__file__).resolve().parents[2]
NAME = 'GeoSustain_Current_Model_Training_2026-11-07'
folder = ROOT / 'output/current-model-notebook-local-qa'
folder.mkdir(parents=True, exist_ok=True)
notebook = nbformat.read(ROOT.parent / (NAME + '.ipynb'), as_version=4)
manager = KernelManager(kernel_name='python3')
manager.kernel_spec.argv = [sys.executable, '-m', 'ipykernel_launcher', '-f', '{connection_file}']
client = NotebookClient(notebook, timeout=300, km=manager,
                        resources={'metadata': {'path': str(folder)}})
client.execute(cwd=str(folder))
target = folder / 'LOCAL_QA_EXECUTED_NOT_COLAB.ipynb'
nbformat.write(notebook, target)
assert all(c.execution_count is not None for c in notebook.cells if c.cell_type == 'code')
assert not any(o.output_type == 'error' for c in notebook.cells if c.cell_type == 'code' for o in c.outputs)
runs = list(folder.rglob('training_run.json'))
assert runs
run = json.loads(max(runs, key=lambda p: p.stat().st_mtime).read_text())
assert run['execution_platform'] == 'local' and run['npk_used'] is False
assert {r['model'] for r in run['comparison']} == {'decision_tree','svm','random_forest'}
assert run['data_audit']['unique_rows'] == 1394
print(json.dumps({'status': 'passed', 'execution_platform': 'local_not_colab',
                  'code_cells_executed': sum(c.cell_type == 'code' for c in notebook.cells),
                  'models_trained': [r['model'] for r in run['comparison']],
                  'trees': 500, 'cv_folds': 5, 'notebook': str(target)}, indent=2))
