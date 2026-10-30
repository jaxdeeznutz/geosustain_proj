"""Local manual workflow lab; temporary schema and synthetic provider readings.

Run from repo root with .tools/python/python.exe. Never use this as deployment.
"""
import argparse
from contextlib import contextmanager, ExitStack
import os
from pathlib import Path
import secrets
import sys
from unittest.mock import patch

# Process-only test settings, established before config loads backend/.env.
# Test tokens cannot authenticate to the production service.
os.environ['DATABASE_URL'] = 'postgresql://defense_test@127.0.0.1:55439/postgres'
os.environ['SECRET_KEY'] = secrets.token_urlsafe(48)
os.environ['APP_ENV'] = 'development'
os.environ.pop('RENDER', None)
os.environ['FRONTEND_ORIGINS'] = 'http://localhost:18002,http://127.0.0.1:18002'
os.environ['ANALYSIS_JOBS_ENABLED'] = '0'
os.environ['CAGRO_REFERENCE_ENABLED'] = '0'

sys.path.insert(0, str(Path(__file__).resolve().parent))
from defense_integration import isolated, db, api, TestClient
import analysis_jobs
import push_delivery
import mail_delivery
import environmental_pipeline as pipeline
import rainfallDatasets as environment
import operator_workflow as workflow
import requests

PASSWORD = 'Phase1Only!2026'  # Disposable local accounts, never real credentials.
FARMER = 'phase1-farmer@example.com'
ANALYST = 'phase1-analyst@example.com'
OTHER = 'phase1-other@example.com'
RING = [{'lat': 7.29, 'lng': 125.62}, {'lat': 7.29, 'lng': 125.621},
        {'lat': 7.291, 'lng': 125.621}, {'lat': 7.291, 'lng': 125.62}]
NOTICE = 'MANUAL WORKFLOW TEST: synthetic observations, not field or provider validation.'


def deny_external_http(*args, **kwargs):
    raise RuntimeError('External HTTP is disabled in the local Phase 1 test lab.')


def deny_mail(*args, **kwargs):
    raise api.HTTPException(503, 'Email delivery is disabled in this local workflow test.')


def climate(*args):
    return {
        'temperature': {'value': 27, 'unit': 'C', 'period': 'annual_mean',
                        'quality': 'modelled', 'source': NOTICE},
        'rainfall': {'value': 2100, 'unit': 'mm/year', 'period': 'annual_mean_total',
                     'quality': 'modelled', 'source': NOTICE},
    }


def weather(*args):
    return {'temperature_c': 27, 'humidity_current_pct': 80, 'live_humidity': 80,
            'wind_speed_ms': 1, 'rainfall_30d_mm': 110,
            'weather_description': 'Local workflow fixture', 'weather_source': NOTICE}


@contextmanager
def workspace():
    # isolated() verifies the exact disposable server's data directory before
    # creating its random schema. It never uses a backend/.env database target.
    with isolated(), ExitStack() as stack:
        password_hash = api.hash_password(PASSWORD)
        farmer = db.create_user('Phase 1 Test Farmer', FARMER, password_hash, email_verified=True)
        analyst = db.create_user('Phase 1 Test Analyst', ANALYST, password_hash,
                                role='agricultural_planning_analyst', email_verified=True)
        db.create_user('Phase 1 Other Farmer', OTHER, password_hash, email_verified=True)
        farm = db.create_farm_parcel(farmer['id'], 'Phase 1 Test Farm', RING,
                                    location_name='Synthetic test parcel, Panabo')
        for target, name, replacement in [
            (api, 'init_db', lambda: None),
            (analysis_jobs, 'enabled', lambda: False),
            (analysis_jobs, 'start_worker', lambda: None),
            (push_delivery, 'start_worker', lambda: None),
            (mail_delivery, 'send', deny_mail),
            (requests.sessions.Session, 'request', deny_external_http),
            (api, 'screen_land_cover', lambda *a: {'allow_crops': False, 'status': 'unknown', 'source': NOTICE}),
            (api, 'reverse_geocode_place', lambda *a: 'Synthetic test location'),
            (api, 'fetch_open_meteo_weather', weather),
            (pipeline, 'retrieve', lambda key, fn, lat, lon, ttl: fn(lat, lon)),
            (pipeline, 'climate_normals', climate),
            (pipeline, 'terrain_slope', lambda *a: 3),
            (environment, 'get_soil_ph', lambda *a: (6, 'measured', NOTICE)),
            (environment, 'get_elevation', lambda *a: (100, 'measured', NOTICE)),
            (environment, 'get_ndvi', lambda *a: (.65, 'measured', NOTICE)),
            (environment, 'get_rainfall', lambda *a: (110, 'measured', NOTICE)),
            (environment, 'get_live_weather', lambda *a: (80, 'Cloudy', 1, 27, 'measured')),
            (environment, 'get_soil_nitrogen', lambda *a: (80, 'estimated_proxy', NOTICE)),
        ]:
            stack.enter_context(patch.object(target, name, replacement))
        real_build = api.build_analysis_result
        def fixture_analysis(*args, **kwargs):
            result, source = real_build(*args, **kwargs)
            result['preliminary_notice'] = NOTICE
            result.setdefault('data_quality_warnings', []).append(NOTICE)
            return result, source
        stack.enter_context(patch.object(api, 'build_analysis_result', fixture_analysis))
        yield farmer, analyst, farm


def smoke():
    with workspace() as (farmer, analyst, farm), TestClient(api.app) as client:
        def login(email):
            response = client.post('/api/mobile/login', json={'email': email, 'password': PASSWORD})
            assert response.status_code == 200, response.text
            return {'Authorization': 'Bearer ' + response.json()['token']}
        fh, ah = login(FARMER), login(ANALYST)
        preflight = client.options('/api/mobile/me', headers={
            'Origin': 'http://localhost:18002', 'Access-Control-Request-Method': 'GET'})
        assert preflight.headers['access-control-allow-origin'] == 'http://localhost:18002'
        assert client.get('/api/mobile/weather?lat=7.29&lon=125.62').status_code == 200
        response = client.post('/api/mobile/analysis', headers={**fh, 'Idempotency-Key': 'manual-lab-smoke'},
                               json={'farm_id': farm['id'], 'boundary_version': 1})
        assert response.status_code == 200, response.text
        record = response.json()
        assert record['formal_submission_eligible'] and record['nitrogen'] == 80
        assert client.post('/api/mobile/submit-to-planner', headers=fh,
                           json={'session_id': record['session_id']}).status_code == 200
        case = client.get('/api/operator/inbox', headers=ah).json()['queue'][0]
        decision = client.post(f"/api/operator/cases/{case['case_id']}/decision", headers=ah, json={
            'version': 1, 'status': 'verified', 'notes': 'Manual lab setup smoke check.',
            'checklist': {key: True for key in workflow.CHECKS}})
        assert decision.status_code == 200, decision.text
        saved = client.get(f"/api/mobile/analyses/{record['session_id']}", headers=fh).json()['analysis']
        assert saved['verification_status'] == 'verified'
        assert saved['planner_notes'] == 'Manual lab setup smoke check.'
        assert client.post('/api/mobile/analysis', headers=ah, json={'farm_id': farm['id']}).status_code == 403
    print('PASS: local manual host setup, login, CORS, fixture inference and farmer/analyst review. Temporary schema removed.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--smoke', action='store_true')
    args = parser.parse_args()
    if args.smoke:
        smoke()
        return
    import uvicorn
    with workspace():
        print('\nPHASE 1 LOCAL WORKFLOW TEST - NOT PRODUCTION')
        print('Backend: http://127.0.0.1:18001 | Chrome client: http://localhost:18002')
        print('Farmer:', FARMER, '| Analyst:', ANALYST)
        print('Disposable test password:', PASSWORD)
        print('Open the seeded Phase 1 Test Farm. Keep this terminal open while testing.')
        print('Synthetic readings only; email/push workers and external backend HTTP are disabled.')
        print('Ctrl+C ends the lab and removes its temporary records.\n', flush=True)
        uvicorn.run(api.app, host='127.0.0.1', port=18001, log_level='warning')


if __name__ == '__main__':
    main()
