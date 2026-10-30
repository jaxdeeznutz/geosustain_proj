"""Matched workflow, durable queue and restore on the verified disposable server.

No production configuration or existing manual-lab schema is used. Providers,
mail and push are disabled by the inherited isolated fixture workspace.
"""
from copy import deepcopy
from pathlib import Path
from time import perf_counter
from unittest.mock import patch
import hashlib
import json
import subprocess
import sys
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parent))
from phase06_manual_host import workspace, api, db, TestClient
import analysis_jobs as jobs
import operator_workflow as workflow
from defense_integration import TARGET
from local_attribution import aggregate_hash
import psycopg2
from psycopg2 import sql


def run():
    output = Path('defense-evidence/capstone-fix-execution/phase-07')
    checks, timings = [], {}
    with workspace() as (farmer, analyst, farm, admin), TestClient(api.app) as client:
        fh = {'Authorization': 'Bearer ' + api.generate_mobile_token(farmer)}
        ah = {'Authorization': 'Bearer ' + api.generate_mobile_token(analyst)}
        other = db.get_user_by_email('phase1-other@example.com')
        oh = {'Authorization': 'Bearer ' + api.generate_mobile_token(other)}
        payload = {'farm_id': farm['id'], 'boundary_version': 1, 'intended_planting_month': 2}
        started = perf_counter()
        response = client.post('/api/mobile/analysis', headers={**fh, 'Idempotency-Key': 'phase07-parcel'}, json=payload)
        assert response.status_code == 200, response.text
        record = response.json()
        timings['nine_sample_polygon_seconds'] = perf_counter() - started
        local = record['local_model_explanation']
        assert local['sample_count'] == 9 and aggregate_hash(local) == local['snapshot_hash']
        frozen = deepcopy(local)
        repeated = client.post('/api/mobile/analysis', headers={**fh, 'Idempotency-Key': 'phase07-parcel'}, json=payload)
        assert repeated.status_code == 200 and repeated.json()['session_id'] == record['session_id']
        checks.append('Actual unchanged forest and nine saved polygon samples produce an additive signed explanation; retry returns the same persisted analysis')
        for headers in (ah, oh):
            assert client.get(f"/api/mobile/analyses/{record['session_id']}", headers=headers).status_code == 404
        assert client.post('/api/mobile/submit-to-planner', headers=fh, json={'session_id': record['session_id']}).status_code == 200
        detail = client.get(f"/api/operator/cases/by-session/{record['session_id']}", headers=ah).json()
        case = detail['case']
        assert detail['analysis']['local_model_explanation'] == frozen
        decision = client.post(f"/api/operator/cases/{case['id']}/decision", headers=ah, json={
            'version': case['version'], 'status': 'verified',
            'notes': 'Phase 7 isolated integration check.', 'checklist': {key: True for key in workflow.CHECKS}})
        assert decision.status_code == 200, decision.text
        saved = client.get(f"/api/mobile/analyses/{record['session_id']}", headers=fh).json()['analysis']
        assert saved['verification_status'] == 'verified'
        assert saved['planner_notes'] == 'Phase 7 isolated integration check.'
        assert saved['local_model_explanation'] == frozen
        checks.append('Farmer submit -> analyst decision -> farmer status/notes preserves original evidence; other-account detail access is denied')

        independent = {'polygon': farm['polygon'], 'intended_planting_month': 2}
        with patch.object(jobs, 'enabled', lambda: True):
            queued = client.post('/api/web/analysis', headers={**ah, 'Idempotency-Key': 'phase07-queued'}, json=independent)
            assert queued.status_code == 202, queued.text
            # Persist a running job and close its connection to model the durable
            # state left after interruption. This is not an OS process-kill test.
            with db.get_conn() as conn, conn.cursor() as cur:
                cur.execute("UPDATE analysis_jobs SET status='running',attempts=1 WHERE user_id=%s AND request_key=%s", (analyst['id'], 'phase07-queued'))
                conn.commit()
            started = perf_counter()
            jobs.run_batch()
            timings['queued_nine_sample_recovery_seconds'] = perf_counter() - started
            with db.get_conn() as conn, conn.cursor() as cur:
                cur.execute('SELECT status,attempts FROM analysis_jobs WHERE user_id=%s AND request_key=%s', (analyst['id'], 'phase07-queued'))
                recovered = cur.fetchone()
                assert recovered['status'] == 'completed' and recovered['attempts'] == 2
            retry = client.post('/api/web/analysis', headers={**ah, 'Idempotency-Key': 'phase07-queued'}, json=independent)
            assert retry.status_code == 200, retry.text
            own = retry.json()
            assert own['formal_submission_eligible'] is False and own.get('farm_id') is None
            assert db.get_user_analysis(analyst['id'], own['session_id']) is not None
            assert db.get_user_analysis(farmer['id'], own['session_id']) is None
            assert client.post('/api/web/analysis', headers=ah, json=payload).status_code == 403
            checks.append('Real queued independent analyst assessment recovers a persisted running state, remains owner-only and cannot attach a farmer parcel')
            queued = client.post('/api/web/analysis', headers={**ah, 'Idempotency-Key': 'phase07-provider-failure'}, json=independent)
            assert queued.status_code == 202
            started = perf_counter()
            with patch.object(api, 'build_analysis_result', side_effect=RuntimeError('Controlled provider outage')):
                jobs.run_batch()
            timings['injected_provider_failure_seconds'] = perf_counter() - started
            assert jobs.status(analyst['id'], 'phase07-provider-failure')['status'] == 'failed'
            assert client.post('/api/web/analysis', headers={**ah, 'Idempotency-Key': 'phase07-provider-failure'}, json=independent).status_code == 202
            jobs.run_batch()
            assert client.post('/api/web/analysis', headers={**ah, 'Idempotency-Key': 'phase07-provider-failure'}, json=independent).status_code == 200
            checks.append('Injected provider failure persists a failed job; explicit same-key retry completes without duplicate saved results')

        with db.get_conn() as conn, conn.cursor() as cur:
            cur.execute('SELECT current_schema() AS schema')
            schema = cur.fetchone()['schema']
            assert schema.startswith('defense_') and schema.isidentifier()
            cur.execute('SELECT COUNT(*) AS count FROM analysis_sessions')
            assert cur.fetchone()['count'] == 3
            cur.execute("SELECT COUNT(*) AS count FROM audit_logs WHERE action='review_verified'")
            assert cur.fetchone()['count'] == 1

        destination = 'phase07_restore_' + uuid.uuid4().hex
        dump = Path('.tools') / (destination + '.dump')
        pg = Path('C:/Program Files/PostgreSQL/16/bin')
        owner = psycopg2.connect(TARGET)
        owner.autocommit = True
        created = False
        try:
            with owner.cursor() as cur:
                cur.execute('SHOW data_directory')
                assert Path(cur.fetchone()[0]).resolve() == Path('D:/GeoSustain-defense-temp-2026-10-23/postgres-closure').resolve()
                assert destination.startswith('phase07_restore_') and destination.isidentifier()
                cur.execute(sql.SQL('CREATE DATABASE {}').format(sql.Identifier(destination)))
                created = True
            started = perf_counter()
            subprocess.run([str(pg/'pg_dump.exe'), '--dbname', TARGET, '--format=custom', '--schema', schema, '--no-owner', '--file', str(dump)], check=True, capture_output=True)
            restored_target = TARGET.rsplit('/', 1)[0] + '/' + destination
            subprocess.run([str(pg/'pg_restore.exe'), '--dbname', restored_target, '--no-owner', str(dump)], check=True, capture_output=True)
            with psycopg2.connect(restored_target, options=f'-c search_path={schema}') as conn, conn.cursor() as cur:
                cur.execute('SELECT COUNT(*) FROM analysis_sessions')
                assert cur.fetchone()[0] == 3
                cur.execute("SELECT COUNT(*) FROM analysis_jobs WHERE status='completed'")
                assert cur.fetchone()[0] == 2
                cur.execute("SELECT COUNT(*) FROM audit_logs WHERE action='review_verified'")
                assert cur.fetchone()[0] == 1
                cur.execute('SELECT result_snapshot FROM analysis_sessions WHERE id=%s', (record['session_id'],))
                restored = cur.fetchone()[0]
                if isinstance(restored, str):
                    restored = json.loads(restored)
                assert restored['local_model_explanation'] == frozen
            timings['dump_restore_seconds'] = perf_counter() - started
            checks.append('pg_dump/pg_restore to a separate disposable database retains all saved analyses, completed jobs, audit event and exact explanation snapshot')
            dump_hash = hashlib.sha256(dump.read_bytes()).hexdigest()
        finally:
            if created:
                with owner.cursor() as cur:
                    cur.execute(sql.SQL('DROP DATABASE {} WITH (FORCE)').format(sql.Identifier(destination)))
            owner.close()
    result = {'status': 'passed', 'checks': checks, 'timings': timings, 'backup_sha256': dump_hash,
              'backup_file': str(dump), 'scope': 'Verified disposable PostgreSQL; synthetic observations and unchanged actual forest; new schema and restore database removed.',
              'limits': ['Bounded fixture workload, not production performance or live provider validation.', 'Recovery uses persisted interrupted state, not an OS worker-kill test.', 'Production backup/restore and real provider/device acceptance remain release gates.']}
    (output/'runtime-sql-restore.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({'status': result['status'], 'checks': len(checks), 'timings': timings}))


if __name__ == '__main__':
    run()
