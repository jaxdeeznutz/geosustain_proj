"""Defense fixes against real disposable PostgreSQL; never reads backend/.env target.

Run: .tools/python/python.exe backend/tests/defense_integration.py --phase 1
The database must be the workspace instance at 127.0.0.1:55439.
Each run creates and drops its own schema. External inference is stubbed.
"""
import argparse
import os
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
import secrets
import sys
import uuid
from pathlib import Path
from unittest.mock import patch

import psycopg2
from psycopg2 import sql
from psycopg2.extras import RealDictCursor
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import database as db
import fastapi_app as api
from bootstrap_admin import bootstrap

TARGET = 'postgresql://defense_test@127.0.0.1:55439/postgres'


@contextmanager
def isolated():
    schema = 'defense_' + uuid.uuid4().hex
    owner = psycopg2.connect(TARGET)
    owner.autocommit = True
    with owner.cursor() as cur:
        cur.execute('SHOW data_directory')
        if Path(cur.fetchone()[0]).resolve() != Path('D:/GeoSustain-defense-temp-2026-10-23/postgres-closure').resolve():
            owner.close()
            raise RuntimeError('Disposable integration target has an unexpected data directory.')
        cur.execute(sql.SQL('CREATE SCHEMA {}').format(sql.Identifier(schema)))

    def connect():
        return psycopg2.connect(TARGET, cursor_factory=RealDictCursor,
                               options=f'-c search_path={schema}', connect_timeout=3)
    try:
        with patch.object(db, 'get_conn', connect), patch.object(db, 'DATABASE_URL', TARGET):
            db.init_db()
            db.init_db()
            yield connect
    finally:
        with owner.cursor() as cur:
            cur.execute(sql.SQL('DROP SCHEMA {} CASCADE').format(sql.Identifier(schema)))
        owner.close()


def phase1(connect):
    password = 'Private!' + secrets.token_urlsafe(18)
    hashed = api.hash_password(password)
    admin = bootstrap('defense-owner@example.com', 'Defense Owner', hashed)
    assert admin['status'] == 'created'
    aid = admin['id']
    assert bootstrap('defense-owner@example.com', 'Defense Owner')['status'] == 'already_admin'
    assert db.get_user_by_id(aid)['password_hash'] == hashed
    print('PASS P-26: bootstrap and rerun preserve one account and its password; test-only account')
    for operation in [lambda: db.delete_user(aid), lambda: db.deactivate_user(aid),
                      lambda: db.admin_update_user(aid, role='farmer')]:
        try:
            operation()
            raise AssertionError('Last administrator was removed')
        except ValueError as exc:
            assert 'last active' in str(exc)
    second = db.create_user('Second Admin', 'second@example.com', hashed, role='super_admin')

    def demote(uid):
        try:
            db.admin_update_user(uid, role='farmer', actor_user_id=aid, actor_role='super_admin')
            return 'changed'
        except ValueError:
            return 'protected'
    with ThreadPoolExecutor(max_workers=2) as pool:
        outcomes = list(pool.map(demote, [aid, second['id']]))
    assert sorted(outcomes) == ['changed', 'protected'], outcomes
    print('PASS P-01: delete/deactivate/demote blocked; simultaneous demotions leave one active administrator')
    remaining = next(u for u in [db.get_user_by_id(aid), db.get_user_by_id(second['id'])] if u['role'] == 'super_admin')
    farmer = db.create_user('Test Farmer', 'farmer@example.com', hashed)
    farmer_id = farmer['id']
    with connect() as conn:
        with conn.cursor() as cur:
            cur.execute("INSERT INTO analysis_sessions (user_id,center_lat,center_lon) VALUES (%s,7.29,125.62) RETURNING id", (farmer_id,))
            session_id = cur.fetchone()['id']
            cur.execute('INSERT INTO crop_recommendations (session_id,predicted_crop,compatibility_pct) VALUES (%s,%s,%s)', (session_id,'cacao',71))
    rows = db.admin_list_analyses()
    assert rows[0]['crop_compatibility_pct'] == 71
    with TestClient(api.app) as client:
        token = api.generate_mobile_token(remaining)
        headers = {'Authorization': 'Bearer ' + token}
        assert client.get('/api/admin/dashboard', headers=headers).status_code == 200
        assert client.get('/api/admin/analyses', headers=headers).json()['analyses'][0]['session_id'] == session_id
        print('PASS P-15: actual administrator SQL and authenticated dashboard/analysis endpoints load')
        fheaders = {'Authorization': 'Bearer ' + api.generate_mobile_token(farmer)}
        for path in ['save-analysis', 'report']:
            assert client.post('/api/mobile/'+path, headers=headers, json={'session_id':session_id}).status_code == 404
            first = client.post('/api/mobile/'+path, headers=fheaders, json={'session_id':session_id})
            again = client.post('/api/mobile/'+path, headers=fheaders, json={'session_id':session_id})
            assert first.status_code == again.status_code == 200
            key = 'saved' if path == 'save-analysis' else 'report'
            assert first.json()[key]['id'] == again.json()[key]['id']
        print('PASS P-16: foreign save/report return 404; owned retries return the same saved row')
        for lat, lon in [('nan','125.6'), ('inf','125.6'), ('91','125.6'), ('7.3','181')]:
            for path in ['weather', 'reverse-geocode']:
                response = client.get(f'/api/mobile/{path}?lat={lat}&lon={lon}', headers=fheaders)
                assert response.status_code == 422, response.text
        for value in ['NaN', 'Infinity', '91']:
            response = client.post('/api/mobile/analysis', headers={**fheaders,'Content-Type':'application/json'},
                                   content='{"lat":'+value+',"lon":125.6}')
            assert response.status_code == 422, response.text
        print('PASS P-17: NaN/Infinity/out-of-range query and analysis inputs rejected before provider calls')
    return db.get_user_by_id(farmer_id), remaining, session_id


def phase2(connect, identities):
    farmer, admin, session_id = identities
    uid = farmer['id']
    ring = [{'lat':7.29,'lng':125.62}, {'lat':7.29,'lng':125.621},
            {'lat':7.291,'lng':125.621}, {'lat':7.291,'lng':125.62}]
    farm = db.create_farm_parcel(uid, 'One physical farm', ring)
    stats_before = db.admin_dashboard_stats()
    with connect() as conn:
        with conn.cursor() as cur:
            cur.execute("""INSERT INTO analysis_sessions (user_id,farm_id,center_lat,center_lon,analyzed_at,verification_status)
                SELECT %s,%s,7.29,125.62,'2026-10-23T00:00:00Z','pending' FROM generate_series(1,2501) RETURNING id""", (uid,farm['id']))
            ids = [r['id'] for r in cur.fetchall()]
            cur.execute('INSERT INTO saved_analyses(user_id,session_id) SELECT user_id,id FROM analysis_sessions WHERE user_id=%s ON CONFLICT DO NOTHING', (uid,))
            cur.execute('INSERT INTO reports(user_id,session_id) SELECT user_id,id FROM analysis_sessions WHERE user_id=%s ON CONFLICT DO NOTHING', (uid,))
    history = []
    for offset in range(0, 2600, 100):
        history.extend(row['session_id'] for row in db.get_user_history(uid,limit=100,offset=offset))
    assert len(history) == len(set(history)) == 2502
    assert set(ids) | {session_id} == set(history)
    print('PASS P-22: 2502 history rows (2501 tied timestamps) occur exactly once across 100-row pages')
    stats_after = db.admin_dashboard_stats()
    assert stats_after['registered_parcels'] == stats_before['registered_parcels'] == 1
    assert stats_after['total_area_hectares'] == stats_before['total_area_hectares']
    assert stats_after['total_analyses'] == stats_before['total_analyses'] + 2501
    print('PASS P-07: 2501 repeat analyses increase activity; one saved parcel and its area remain unchanged')
    updated = db.update_farm_parcel(uid,farm['id'],farm_name='Edited',expected_boundary_version=farm['boundary_version'])
    assert updated['boundary_version'] == farm['boundary_version'] + 1
    try:
        db.update_farm_parcel(uid,farm['id'],farm_name='Stale overwrite',expected_boundary_version=farm['boundary_version'])
        raise AssertionError('stale edit overwrote current record')
    except ValueError:
        pass
    assert db.get_farm_parcel(uid, farm['id'])['farm_name'] == 'Edited'
    print('PASS P-08: stale edit is rejected without overwriting the successful version')
    archived=db.update_farm_parcel(uid,farm['id'],is_archived=True,expected_boundary_version=updated['boundary_version'])
    archived_stats=db.admin_dashboard_stats()
    assert archived_stats['registered_parcels']==0 and archived_stats['archived_parcels']==1
    assert archived_stats['total_area_hectares']==0
    db.update_farm_parcel(uid,farm['id'],is_archived=False,expected_boundary_version=archived['boundary_version'])
    print('PASS P-07 archive: active inventory/area exclude archived farms; archived inventory is reported separately')
    with TestClient(api.app, raise_server_exceptions=False) as client:
        admin_headers = {'Authorization':'Bearer '+api.generate_mobile_token(admin)}
        farmer_headers = {'Authorization':'Bearer '+api.generate_mobile_token(farmer)}
        analyst = db.create_user('Review Analyst','analyst@example.com',farmer['password_hash'], role='agricultural_planning_analyst')
        analyst_headers = {'Authorization':'Bearer '+api.generate_mobile_token(analyst)}
        for path, key, headers, expected in [('/api/mobile/saved','saved',farmer_headers,2502),
            ('/api/mobile/reports','reports',farmer_headers,2502),
            ('/api/planner/queue','queue',analyst_headers,2501),
            ('/api/admin/analyses','analyses',admin_headers,2502)]:
            found=[]
            offset=0
            while True:
                response=client.get(path,params={'limit':100,'offset':offset},headers=headers)
                assert response.status_code == 200, response.text
                data=response.json()
                found.extend(row['session_id'] for row in data[key])
                if not data['has_more']:
                    break
                offset += 100
            assert len(found) == len(set(found)) == expected, (path,len(found))
        assert client.get('/api/admin/analyses',params={'limit':101},headers=admin_headers).status_code == 422
        assert client.get('/api/admin/users',params={'q':'Review Analyst'},headers=admin_headers).json()['users'][0]['id'] == analyst['id']
        print('PASS P-06: saved/reports/admin/queue traverse >200 rows, bounded limits and server search work')
        assert client.patch(f'/api/mobile/farms/{farm["id"]}',headers=farmer_headers,json={'farm_name':'No version'}).status_code == 422
        assert client.patch(f'/api/mobile/farms/{farm["id"]}',headers=farmer_headers,json={'farm_name':'Stale','expected_boundary_version':1}).status_code == 409
        import base64
        import io
        from PIL import Image
        image=io.BytesIO()
        Image.new('RGB',(4,4),'green').save(image,format='PNG')
        valid='data:image/png;base64,'+base64.b64encode(image.getvalue()).decode()
        for photo in ['not-an-image','data:image/png;base64,SGVsbG8=', 'data:image/png;base64,%%%']:
            assert client.put('/api/mobile/me',headers=farmer_headers,json={'profile_photo':photo}).status_code == 422
        assert client.put('/api/mobile/me',headers=farmer_headers,json={'profile_photo':valid}).status_code == 200
        assert client.put('/api/mobile/me',headers=farmer_headers,json={'profile_photo':''}).status_code == 200
        print('PASS P-21: invalid image bytes/encoding rejected; valid PNG and explicit clearing preserved')
        assert client.get('/api/analysis').status_code == 405
        result={'lat':7.29,'lon':125.62,'predicted_crop':'cacao','crop_compatibility_pct':71}
        with patch.object(api,'current_user',return_value=farmer), patch.object(api,'build_analysis_result',return_value=(result,'fixture')):
            headers={'Idempotency-Key':'retained-test-key'}
            first=client.post('/api/analysis',headers=headers,json={'lat':7.29,'lon':125.62})
            again=client.post('/api/analysis',headers=headers,json={'lat':7.29,'lon':125.62})
            assert first.status_code == again.status_code == 200, first.text
            assert first.json()['session_id'] == again.json()['session_id']
            with patch.object(api,'save_analysis_session',side_effect=psycopg2.OperationalError('fixture save failure')):
                failed=client.post('/api/analysis',headers={'Idempotency-Key':'failed-key'},json={'lat':7.29,'lon':125.62})
                assert failed.status_code == 503, failed.text
        print('PASS P-02: retained GET is 405; POST retries share one row; DB save failure returns 503')
    doomed=db.create_user('Delete Me','delete@example.com',farmer['password_hash'])
    db.create_farm_parcel(doomed['id'],'Private farm',ring)
    with connect() as conn:
        with conn.cursor() as cur:
            cur.execute('INSERT INTO analysis_sessions(user_id,center_lat,center_lon) VALUES (%s,7.29,125.62)',(doomed['id'],))
    db.delete_user(doomed['id'])
    with connect() as conn:
        with conn.cursor() as cur:
            for table,column in [('users','id'),('farm_parcels','farmer_id'),('analysis_sessions','user_id')]:
                cur.execute(f'SELECT COUNT(*) AS count FROM {table} WHERE {column}=%s',(doomed['id'],))
                assert cur.fetchone()['count']==0
            cur.execute("SELECT actor_user_id,actor_reference FROM audit_logs WHERE action='account_delete' AND target_id=%s",(doomed['id'],))
            audit=cur.fetchone()
            assert audit['actor_user_id'] is None and audit['actor_reference']==f'account:{doomed["id"]}'
    print('PASS P-03: owned account/farms/coordinates removed; pseudonymous audit attribution survives')


def phase3(connect, identities):
    # Synthetic project ID with mocked HTTP; no live Google/Firebase calls.
    os.environ['FCM_PROJECT_ID'] = 'defense-offline-fixture'
    farmer, admin, session_id = identities
    uid = farmer['id']
    with TestClient(api.app, raise_server_exceptions=False) as client:
        first = api.generate_mobile_token(db.get_user_by_id(uid))
        second = api.generate_mobile_token(db.get_user_by_id(uid))
        headers = lambda token: {'Authorization':'Bearer '+token}
        assert client.post('/api/mobile/logout',headers=headers(first)).status_code == 200
        assert client.get('/api/mobile/me',headers=headers(first)).status_code == 401
        assert client.get('/api/mobile/me',headers=headers(second)).status_code == 200
        print('PASS P-04: replay of signed-out bearer returns 401; independent second session remains valid')
        admin_headers=headers(api.generate_mobile_token(admin))
        assert client.post(f'/api/admin/users/{uid}/recovery',headers=headers(second),json={'identity_verified':True}).status_code == 403
        issued=client.post(f'/api/admin/users/{uid}/recovery',headers=admin_headers,json={'identity_verified':True})
        assert issued.status_code == 200, issued.text
        handoff=issued.json()['recovery_token']
        assert issued.headers['cache-control'] == 'no-store'
        fresh_password='Replacement!'+secrets.token_urlsafe(16)
        body={'recovery_token':handoff,'new_password':fresh_password}
        response=client.post('/api/mobile/recover-password',json=body)
        assert response.status_code == 200, response.text
        assert client.post('/api/mobile/recover-password',json=body).status_code == 400
        assert client.get('/api/mobile/me',headers=headers(second)).status_code == 401
        assert api.verify_password(fresh_password,db.get_user_by_id(uid)['password_hash'])
        expired=db.issue_password_recovery(uid,admin['id'])
        with connect() as conn:
            with conn.cursor() as cur:
                cur.execute("UPDATE password_recovery SET expires_at=NOW()-INTERVAL '1 second' WHERE user_id=%s",(uid,))
        assert not db.redeem_password_recovery(expired,api.hash_password('Unused!1234'))
        print('PASS P-09: admin-only issuance, private no-store handoff, expiry, single use, new password, and old-session invalidation')
        ready_conn=connect()
        with patch.object(psycopg2,'connect',return_value=ready_conn):
            assert client.get('/ready').status_code==200
        with patch.object(psycopg2,'connect',side_effect=psycopg2.OperationalError('fixture dependency outage')):
            assert client.get('/ready').status_code==503
            assert client.get('/health').status_code==200
        recovered_conn=connect()
        with patch.object(psycopg2,'connect',return_value=recovered_conn):
            assert client.get('/ready').status_code==200
        print('PASS P-20: real migrated database/model readiness 200, injected DB outage 503 with live process 200, recovery 200')
    before=db.get_user_by_id(uid)['role']
    with patch.object(db,'audit_in_transaction',side_effect=RuntimeError('fixture audit unavailable')):
        try:
            db.admin_update_user(uid,role='agricultural_planning_analyst',actor_user_id=admin['id'],actor_role='super_admin')
            raise AssertionError('privileged change committed without its audit')
        except RuntimeError:
            pass
    assert db.get_user_by_id(uid)['role'] == before
    with connect() as conn:
        with conn.cursor() as cur:
            cur.execute("UPDATE analysis_sessions SET verification_status='pending' WHERE id=%s",(session_id,))
    with patch.object(db,'audit_in_transaction',side_effect=RuntimeError('fixture audit unavailable')):
        try:
            db.verify_analysis_session(session_id,admin['id'],'verified')
            raise AssertionError('review committed without its audit')
        except RuntimeError:
            pass
    assert db.get_user_analysis(uid,session_id)['verification_status']=='pending'
    print('PASS P-05: injected audit failure rolls back role changes and review decisions')
    from push_delivery import register, deliver_batch
    from unittest.mock import Mock
    current=db.get_user_by_id(uid)
    token='synthetic-device-registration-token-not-real'
    register(uid,'push-fixture-session',current['password_version'],token,'android',True)
    db.verify_analysis_session(session_id,admin['id'],'verified')
    failing=Mock()
    failing.post.return_value.status_code=503
    failing.post.return_value.json.return_value={}
    assert deliver_batch(failing) == 1
    with connect() as conn:
        with conn.cursor() as cur:
            cur.execute('SELECT attempts,sent_at FROM push_deliveries WHERE token=%s',(token,))
            row=cur.fetchone()
            assert row['attempts']==1 and row['sent_at'] is None
            cur.execute('UPDATE push_deliveries SET next_attempt_at=NOW() WHERE token=%s',(token,))
    success=Mock()
    success.post.return_value.status_code=200
    assert deliver_batch(success)==1
    assert success.post.call_args.kwargs['timeout']==10
    register(uid,'push-fixture-session',current['password_version'],token,'android',False)
    assert deliver_batch(success)==0
    print('PASS P-10 transport: review enqueues atomically; simulated provider failure persists retry; success and opt-out work (no live push claimed)')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--phase', type=int, default=1)
    args = parser.parse_args()
    with isolated() as connect:
        identities = phase1(connect)
        if args.phase >= 2:
            phase2(connect, identities)
        if args.phase >= 3:
            phase3(connect, identities)
    print('PASS: disposable schema removed; configured project/production database was not accessed')


if __name__ == '__main__':
    main()
