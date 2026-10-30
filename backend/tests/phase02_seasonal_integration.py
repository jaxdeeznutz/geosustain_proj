"""Real disposable SQL/API snapshot parity; climate and model are fixtures."""
from copy import deepcopy
import json
from pathlib import Path
import sys
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from defense_integration import isolated, db, api, TestClient
from test_seasonal_assessment import payload
import seasonal_assessment as seasonal
import environmental_pipeline
import analysis_jobs
import push_delivery

RING = [{'lat': 7.29, 'lng': 125.62}, {'lat': 7.29, 'lng': 125.621},
        {'lat': 7.291, 'lng': 125.621}, {'lat': 7.291, 'lng': 125.62}]


def run():
    checks = []
    raw = {'scoring_version': 'controlled-model-fixture', 'is_crop_recommended': True,
           'predicted_crop': 'Banana', 'crop': 'Banana', 'crop_compatibility_pct': 41.123,
           'top_crop_recommendations': [{'crop': 'Banana', 'compatibility_pct': 41.123},
                                        {'crop': 'Rice', 'compatibility_pct': 16.2}],
           'temperature_c': 27, 'rainfall_mm': 110}
    with isolated():
        farmer = db.create_user('Phase02 fixture farmer', 'phase02-owner@example.com', api.hash_password('LocalOnly!Phase02'))
        analyst = db.create_user('Phase02 fixture analyst', 'phase02-analyst@example.com', api.hash_password('LocalOnly!Phase02'),
                                 role='agricultural_planning_analyst')
        farm = db.create_farm_parcel(farmer['id'], 'Phase02 fixture parcel', RING)
        fh = {'Authorization': 'Bearer '+api.generate_mobile_token(farmer)}
        ah = {'Authorization': 'Bearer '+api.generate_mobile_token(analyst)}
        with (patch.object(api, 'init_db', lambda: None),
              patch.object(analysis_jobs, 'enabled', lambda: False),
              patch.object(analysis_jobs, 'start_worker', lambda: None),
              patch.object(push_delivery, 'start_worker', lambda: None),
              patch.object(api, 'get_active_crop_keys', lambda: None),
              patch.object(api, 'reverse_geocode_place', lambda *_: 'Phase02 fixture location'),
              patch.object(api, 'screen_land_cover', lambda *_: {'allow_crops': True, 'status': 'eligible'}),
              patch.object(api, 'analyze_location', lambda *_: deepcopy(raw)),
              patch.object(environmental_pipeline, 'merge_results', lambda *_: deepcopy(raw)),
              patch.object(api, 'fetch_multi_year_monthly_baseline',
                           lambda lat, lon, month: seasonal.parse_baseline(payload(), lat, lon, month)),
              TestClient(api.app) as client):
            saved = []
            for month in (2, 8):
                response = client.post('/api/mobile/analysis', headers={**fh, 'Idempotency-Key': f'phase02-{month}'},
                                       json={'farm_id': farm['id'], 'boundary_version': 1, 'intended_planting_month': month})
                assert response.status_code == 200, response.text
                record = response.json()
                assert record['seasonal_assessment']['monthly_climate']['mean_temperature_c'] == month
                assert record['top_crop_recommendations'] == raw['top_crop_recommendations']
                assert record['formal_submission_eligible'] is True
                saved.append(record)
                reopened = client.get(f"/api/mobile/analyses/{record['session_id']}", headers=fh)
                assert reopened.status_code == 200, reopened.text
                assert reopened.json()['analysis']['seasonal_assessment'] == record['seasonal_assessment']
            checks.append('Saved formal analyses for February/August retain distinct monthly snapshots with identical ranks/scores')
            history = db.get_user_history(farmer['id'])
            for record in saved:
                row = next(r for r in history if r['session_id'] == record['session_id'])
                assert row['seasonal_assessment'] == record['seasonal_assessment']
            checks.append('Farmer detail and history round-trip exact saved seasonal JSON')
            assert client.post('/api/mobile/submit-to-planner', headers=fh,
                               json={'session_id': saved[0]['session_id']}).status_code == 200
            # Query the case through the same operator endpoint as the UI.
            response = client.get(f"/api/operator/cases/by-session/{saved[0]['session_id']}", headers=ah)
            assert response.status_code == 200, response.text
            assert response.json()['analysis']['seasonal_assessment'] == saved[0]['seasonal_assessment']
            checks.append('Analyst case receives the exact snapshot submitted by farmer')
            with patch.object(api, 'fetch_multi_year_monthly_baseline', seasonal.empty_baseline):
                response = client.post('/api/mobile/analysis', headers={**fh, 'Idempotency-Key': 'phase02-unavailable'},
                                       json={'farm_id': farm['id'], 'boundary_version': 1, 'intended_planting_month': 5})
                assert response.status_code == 200, response.text
                assert response.json()['seasonal_assessment']['status'] == 'unavailable'
                assert response.json()['top_crop_recommendations'] == raw['top_crop_recommendations']
            original = db.get_user_analysis(farmer['id'], saved[0]['session_id'])
            assert original['seasonal_assessment'] == saved[0]['seasonal_assessment']
            checks.append('Provider unavailability saves explicit state without blocking model result or rewriting historical snapshot')
    out = Path('defense-evidence/capstone-fix-execution/phase-02/sql-api-results.json')
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({'status': 'passed', 'checks': checks,
                              'basis': 'Temporary verified local SQL schema; synthetic climate/model; no production or live-provider validation'}, indent=2)+'\n')
    for check in checks:
        print('PASS:', check)


if __name__ == '__main__':
    run()
