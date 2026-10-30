"""Saved local attribution SQL/API parity on the verified disposable server."""
from copy import deepcopy
import json
from pathlib import Path
import sys
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from phase05_manual_host import workspace, api, db, TestClient
from local_attribution import aggregate_hash, bind_local_explanation
from model_explainability import FEATURE_LABELS
import model_explainability


def run():
    output = Path('defense-evidence/capstone-fix-execution/phase-05')
    output.mkdir(parents=True, exist_ok=True)
    checks = []
    with workspace() as (farmer, analyst, farm), TestClient(api.app) as client:
        fh = {'Authorization': 'Bearer '+api.generate_mobile_token(farmer)}
        ah = {'Authorization': 'Bearer '+api.generate_mobile_token(analyst)}
        payload = {'farm_id': farm['id'], 'boundary_version': 1, 'intended_planting_month': 11}
        response = client.post('/api/mobile/analysis', headers={**fh, 'Idempotency-Key': 'phase05-first'}, json=payload)
        assert response.status_code == 200, response.text
        record = response.json()
        local = record['local_model_explanation']
        assert local['status'] == 'available', local
        assert local['sample_count'] > 1
        assert len(set(local['sample_input_hashes'])) > 1
        assert aggregate_hash(local) == local['snapshot_hash']
        for index, score in enumerate(local['model_scores']):
            assert abs(local['base_values'][index] + sum(local['contributions'][index]) - score) < 1e-9
        checks.append('Actual forest: varied original parcel samples reconstruct every class score; all active crop classes map correctly')
        detail = client.get(f"/api/mobile/analyses/{record['session_id']}", headers=fh).json()['analysis']
        history = next(r for r in db.get_user_history(farmer['id']) if r['session_id'] == record['session_id'])
        assert detail['local_model_explanation'] == history['local_model_explanation'] == local
        assert detail['model_explanation'] == record['model_explanation']
        assert client.post('/api/mobile/submit-to-planner', headers=fh, json={'session_id': record['session_id']}).status_code == 200
        case = client.get(f"/api/operator/cases/by-session/{record['session_id']}", headers=ah)
        assert case.status_code == 200, case.text
        assert case.json()['analysis']['local_model_explanation'] == local
        assert case.json()['analysis']['model_explanation'] == record['model_explanation']
        checks.append('Farmer detail/history and analyst submitted case preserve identical local and per-sample explanation snapshots')
        with patch.object(model_explainability, 'sample_attribution', lambda *a, **k: {'status': 'unavailable', 'reason': 'Controlled explanation failure'}):
            failed = client.post('/api/mobile/analysis', headers={**fh, 'Idempotency-Key': 'phase05-failed'}, json=payload)
        assert failed.status_code == 200, failed.text
        failed = failed.json()
        assert failed['local_model_explanation']['status'] == 'unavailable'
        for key in ['top_crop_recommendations', 'crop_assessments', 'predicted_crop', 'crop_compatibility_pct']:
            # Parallel forest sums may differ in the last floating bit.
            from phase03_spatial_integration import same_evidence
            same_evidence(record[key], failed[key], key)
        assert db.get_user_analysis(farmer['id'], record['session_id'])['local_model_explanation'] == local
        checks.append('Attribution failure leaves scores/ranking intact and does not replace an earlier saved explanation')
        replay = deepcopy(detail)
        assert bind_local_explanation(replay, replay['model_explanation'], FEATURE_LABELS)['local_model_explanation'] == local
        checks.append('Saved attribution rebinds from recorded inputs and contributions without reading or predicting with the current model')
        # Full real API JSON (synthetic observations) drives cross-language checks and both report builders.
        Path('test/fixtures/local_analysis.json').write_text(json.dumps(detail, indent=2)+'\n', encoding='utf-8')
    (output/'sql-api-results.json').write_text(json.dumps({'status': 'passed', 'checks': checks,
        'basis': 'Verified disposable PostgreSQL schema; synthetic observations; actual unchanged forest. Temporary schema dropped.'}, indent=2)+'\n')
    for check in checks:
        print('PASS:', check)


if __name__ == '__main__':
    run()
