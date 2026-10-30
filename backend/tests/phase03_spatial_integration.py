"""Real disposable SQL/API parity with synthetic rasters and real existing RF."""
from copy import deepcopy
import json
import math
from pathlib import Path
import sys
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from phase03_manual_host import workspace, base
from spatial_analysis import build_spatial_assessment

api, db, TestClient = base.base.api, base.base.db, base.base.TestClient


def same_evidence(left, right, path=''):
    # A new inference has a new context UUID; hashes include its probability
    # floats. Parallel forest summation can differ in the last floating bit.
    # Compare actual inputs, probabilities, grades, periods and methods rather
    # than timestamps/generated IDs. The model artifact hash remains exact.
    volatile = {'observed_at', 'retrieved_at', 'captured_at', 'generated_at',
                'prediction_context_id', 'sample_id', 'input_snapshot_hash'}
    if isinstance(left, dict) and isinstance(right, dict):
        keys = set(left)-volatile
        assert keys == set(right)-volatile, path
        for key in keys:
            same_evidence(left[key], right[key], path+'/'+key)
    elif isinstance(left, list) and isinstance(right, list):
        assert len(left) == len(right), path
        for index, (a, b) in enumerate(zip(left, right)):
            same_evidence(a, b, path+'/'+str(index))
    elif type(left) in (int, float) and type(right) in (int, float):
        assert math.isclose(left, right, rel_tol=1e-12, abs_tol=1e-10), (path, left, right)
    else:
        assert left == right, (path, left, right)


def run():
    out = Path('defense-evidence/capstone-fix-execution/phase-03');out.mkdir(parents=True, exist_ok=True)
    checks = []
    with workspace() as (farmer, analyst, farm), TestClient(api.app) as client:
        fh = {'Authorization': 'Bearer '+api.generate_mobile_token(farmer)}
        ah = {'Authorization': 'Bearer '+api.generate_mobile_token(analyst)}
        body = {'farm_id': farm['id'], 'boundary_version': 1, 'intended_planting_month': 11}
        response = client.post('/api/mobile/analysis', headers={**fh, 'Idempotency-Key': 'phase03-first'}, json=body)
        assert response.status_code == 200, response.text
        record = response.json()
        spatial = record['spatial_assessment']
        assert spatial['status'] == 'partial' and record['formal_submission_eligible']
        layers = {layer['id']: layer for layer in spatial['layers']}
        assert layers['ndvi']['status'] == 'partial'
        assert layers['soil_ph']['statistics']['minimum'] == layers['soil_ph']['statistics']['maximum'] == 6
        assert layers['soil_ph']['statistics']['standard_deviation'] == 0
        assert layers['rainfall_30d']['status'] == 'unavailable'
        checks.append('Real forest inference produces formal concave-farm result with explicit partial, constant/coarse and unavailable raster layers')
        saved = deepcopy(spatial)
        detail = client.get(f"/api/mobile/analyses/{record['session_id']}", headers=fh).json()['analysis']
        history = next(r for r in db.get_user_history(farmer['id']) if r['session_id'] == record['session_id'])
        assert detail['spatial_assessment'] == history['spatial_assessment'] == saved
        assert client.post('/api/mobile/submit-to-planner', headers=fh, json={'session_id': record['session_id']}).status_code == 200
        case = client.get(f"/api/operator/cases/by-session/{record['session_id']}", headers=ah)
        assert case.status_code == 200, case.text
        assert case.json()['analysis']['spatial_assessment'] == saved
        checks.append('Farmer detail/history and analyst submitted case retain the exact raster cells, masks, metadata and statistics')
        with patch.object(api, 'build_spatial_assessment', lambda polygon: build_spatial_assessment(polygon, provider=lambda _: {})):
            response = client.post('/api/mobile/analysis', headers={**fh, 'Idempotency-Key': 'phase03-unavailable'}, json=body)
            assert response.status_code == 200, response.text
            other = response.json()
        for key in ['top_crop_recommendations', 'crop_compatibility_pct', 'environmental_measurements',
                    'crop_assessments', 'model_explanation', 'nitrogen', 'phosphorus', 'potassium']:
            same_evidence(other.get(key), record.get(key), key)
        assert other['spatial_assessment']['status'] == 'unavailable'
        assert db.get_user_analysis(farmer['id'], record['session_id'])['spatial_assessment'] == saved
        checks.append('All-raster failure leaves actual model scores/order, inputs, annual grades and estimated NPK unchanged; earlier snapshot is immutable')
        fixture = {'session_id': 303, 'farm_id': 3, 'boundary_version': 1, 'farm_name': 'Phase 3 synthetic test farm',
                   'selected_polygon': record['selected_polygon'], 'spatial_assessment': saved}
        fixture_path = Path('test/fixtures/spatial_analysis.json');fixture_path.parent.mkdir(parents=True, exist_ok=True)
        fixture_path.write_text(json.dumps(fixture, indent=2)+'\n')
    (out/'sql-api-results.json').write_text(json.dumps({'status': 'passed', 'checks': checks,
        'basis': 'Verified disposable PostgreSQL schema; synthetic source rasters and environmental inputs; actual unchanged forest. Temporary schema dropped.'}, indent=2)+'\n')
    for check in checks:
        print('PASS:', check)


if __name__ == '__main__':
    run()
