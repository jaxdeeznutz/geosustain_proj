"""Real persistence checks in the guarded disposable PostgreSQL schema only."""
import sys
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from fastapi.testclient import TestClient
from defense_integration import isolated
import database as db
import fastapi_app as api
import operator_workflow as workflow


def run():
    with isolated() as connect:
        farmer = db.create_user('Fixture Farmer', 'delete-owner@example.com', 'unused-test-only')
        other = db.create_user('Other Farmer', 'delete-other@example.com', 'unused-test-only')
        analyst = db.create_user('Fixture Analyst', 'inbox-analyst@example.com', 'unused-test-only', role='agricultural_planning_analyst')
        admin = db.create_user('Fixture Admin', 'page-admin@example.com', 'unused-test-only', role='super_admin')
        polygon = [{'lat': 7.29, 'lng': 125.62}, {'lat': 7.291, 'lng': 125.62}, {'lat': 7.29, 'lng': 125.621}]
        farm = db.create_farm_parcel(farmer['id'], 'Deletion fixture', polygon)

        def save(score, *, allow=True, mode='environmental_model_no_npk', recommended=True, basis='model_probability', land='Vegetation observation only'):
            snapshot = dict(lat=7.29, lon=125.62, farm_id=farm['id'], farm_name=farm['farm_name'],
                            boundary_version=farm['boundary_version'], selected_polygon=polygon,
                            analysis_mode=mode, recommendation_basis=basis, predicted_crop='Rice',
                            crop_compatibility_pct=score, is_crop_recommended=recommended, land_type=land,
                            land_cover={'allow_crops': allow})
            sid = db.save_analysis_session(farmer['id'], snapshot, 'synthetic-inbox-regression')
            with connect() as conn, conn.cursor() as cur:
                cur.execute("UPDATE analysis_sessions SET verification_status='pending',submitted_at=NOW() WHERE id=%s", (sid,))
                case = workflow.ensure_case(cur, sid)
            return sid, case['id']

        saved = [save(score) for score in [47.26, 0, 40, 50, 60, 70, 80]]
        blocked = [save(100, allow=False), save(100, mode='preliminary_environmental'),
                   save(100, recommended=False), save(100, basis='legacy', land='water')]
        legacy = save(84.9, basis='legacy', land='arable')
        rows = {row['session_id']: row for row in workflow.inbox(limit=30)['queue']}
        assert float(rows[saved[0][0]]['compatibility_pct']) == 47.26
        assert float(rows[saved[1][0]]['compatibility_pct']) == 0
        assert float(rows[legacy[0]]['compatibility_pct']) == 84.9
        assert all(rows[sid]['compatibility_pct'] is None for sid, _ in blocked)

        headers = lambda u: {'Authorization': 'Bearer ' + api.generate_mobile_token(u)}
        with patch.object(api, 'init_db', lambda: None), TestClient(api.app) as client:
            path = f"/api/mobile/farms/{farm['id']}"
            assert client.delete(path, headers=headers(other)).status_code == 404
            assert db.get_farm_parcel(farmer['id'], farm['id'])
            assert client.delete(path).status_code == 401
            first = client.get('/api/admin/analyses?limit=6', headers=headers(admin)).json()
            second = client.get('/api/admin/analyses?limit=6&offset=6', headers=headers(admin)).json()
            assert len(first['analyses']) == 6 and first['has_more']
            assert len(second['analyses']) == 6 and not second['has_more']
            assert not ({row['session_id'] for row in first['analyses']} & {row['session_id'] for row in second['analyses']})
            with connect() as conn, conn.cursor() as cur:
                cur.execute('SELECT result_snapshot FROM analysis_sessions WHERE id=%s', (saved[0][0],))
                snapshot_before = cur.fetchone()['result_snapshot']
            assert client.delete(path, headers=headers(farmer)).status_code == 200
            assert client.get(path, headers=headers(farmer)).status_code == 404
            assert db.list_farm_parcels(farmer['id'], include_archived=True) == []
            detail = client.get(f'/api/operator/cases/{saved[0][1]}', headers=headers(analyst))
            assert detail.status_code == 200, detail.text
            assert detail.json()['case']['farm_id'] is None
            with connect() as conn, conn.cursor() as cur:
                cur.execute('SELECT farm_id,result_snapshot FROM analysis_sessions WHERE id=%s', (saved[0][0],))
                retained = cur.fetchone()
                assert retained['farm_id'] is None and retained['result_snapshot'] == snapshot_before
                cur.execute("SELECT actor_user_id,actor_role FROM audit_logs WHERE action='farm_deleted'")
                event = cur.fetchone()
                assert event['actor_user_id'] == farmer['id'] and event['actor_role'] == 'farmer'
            assert client.delete(path, headers=headers(farmer)).status_code == 404
        print('PASS: current/legacy/zero inbox scores, blocked/preliminary exclusions, six-row API pagination, owner-only deletion, immutable retained snapshots/reviews, audit event.')


if __name__ == '__main__':
    run()
