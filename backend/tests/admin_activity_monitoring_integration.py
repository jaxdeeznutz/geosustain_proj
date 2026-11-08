"""Sign-in audit and read-only health checks in the guarded disposable database."""
import json
import sys
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parent))
from defense_integration import isolated, db, api, TestClient


def run():
    with isolated() as connect:
        password = 'Synthetic!234'
        farmer = db.create_user('Synthetic audit farmer', 'audit-farmer@example.com', api.hash_password(password))
        admin = db.create_user('Synthetic audit admin', 'audit-admin@example.com', api.hash_password(password), role='super_admin')
        with connect() as conn, conn.cursor() as cur:
            db.audit_in_transaction(cur, None, 'system_migration', 'test_system_migration', details={'kind': 'synthetic-only'})
        with patch.object(api, 'init_db', lambda: None), TestClient(api.app) as client:
            response = client.post('/api/mobile/login', json={'email': farmer['email'], 'password': password})
            assert response.status_code == 200
            headers = {'Authorization': 'Bearer ' + response.json()['token']}
            assert client.get('/api/mobile/me', headers=headers).status_code == 200
            assert client.post('/api/mobile/login', json={'email': farmer['email'], 'password': 'incorrect'}).status_code == 401
            logs = [r for r in db.get_audit_logs() if r['action'] == 'sign_in']
            assert len(logs) == 1
            assert logs[0]['actor_username'] == 'Synthetic audit farmer'
            assert logs[0]['actor_role'] == 'farmer'
            assert logs[0]['actor_reference'] == f"account:{farmer['id']}"
            assert logs[0]['details'] == {'method': 'password', 'channel': 'api'}
            assert password not in json.dumps(logs, default=str)
            cookie = client.post('/login', data={'email': farmer['email'], 'password': password}, follow_redirects=False)
            assert cookie.status_code == 302
            assert len([r for r in db.get_audit_logs() if r['action'] == 'sign_in']) == 2
            system_logs = [r for r in db.get_audit_logs() if r['actor_role'] == 'system_migration']
            assert system_logs and all(r['actor_reference'] == 'system' for r in system_logs)
            assert client.get('/api/admin/system-status', headers=headers).status_code == 403
            admin_headers = {'Authorization': 'Bearer ' + api.generate_mobile_token(admin)}
            health = client.get('/api/admin/system-status', headers=admin_headers)
            assert health.status_code == 200 and health.headers['cache-control'] == 'no-store'
            checks = {c['key']: c for c in health.json()['checks']}
            assert checks['database']['status'] == checks['reports']['status'] == 'healthy'
            assert checks['maps']['status'] == 'client_side'
            assert health.json()['checked_at']
        print('PASS: real password and cookie sign-ins persist correct actor/role, session restore and failed sign-in add no success events, maintenance keeps a system identity, authorized monitoring reads the actual database/report schema, and farmer monitoring access is denied. Disposable schema removed.')


if __name__ == '__main__':
    run()
