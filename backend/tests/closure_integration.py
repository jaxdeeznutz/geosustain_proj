"""Real PostgreSQL acceptance in a fresh synthetic schema, never the configured project DB."""
import json
import os
import time
import statistics
import sys
import subprocess
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from defense_integration import isolated, db, api, TestClient
import qa_closure as closure
import analysis_jobs as jobs


def run():
    metrics={}
    with isolated() as connect:
        farmer=db.create_user('Closure Farmer','closure-farmer@example.com',api.hash_password('SyntheticOnly-2026!'))
        other=db.create_user('Other Farmer','closure-other@example.com','unused')
        admin=db.create_user('Closure Admin','closure-admin@example.com','unused',role='super_admin')
        uid=farmer['id']
        with connect() as conn:
            with conn.cursor() as cur:
                cur.execute("INSERT INTO analysis_sessions(user_id,center_lat,center_lon,verification_status) VALUES (%s,7.29,125.62,'pending') RETURNING id",(uid,))
                sid=cur.fetchone()['id']
        with patch.object(db,'audit_in_transaction',side_effect=RuntimeError('injected audit outage')):
            try:
                db.verify_analysis_session(sid,admin['id'],'verified')
            except RuntimeError:
                pass
        assert closure.inbox(uid)['unread_count']==0
        db.verify_analysis_session(sid,admin['id'],'verified','Synthetic review note')
        assert db.verify_analysis_session(sid,admin['id'],'verified') is None
        inbox=closure.inbox(uid)
        nid=inbox['notifications'][0]['id']
        assert len(inbox['notifications'])==inbox['unread_count']==1
        assert closure.read_notification(other['id'],nid) is None
        assert closure.inbox(other['id'])['notifications']==[]
        first=closure.read_notification(uid,nid)
        assert closure.read_notification(uid,nid)['read_at']==first['read_at']
        assert closure.inbox(uid)['unread_count']==0
        print('PASS inbox: atomic review event, rollback, duplicate suppression, ownership, persistent unread and idempotent read')
        with TestClient(api.app) as client:
            headers={'Authorization':'Bearer '+api.generate_mobile_token(farmer)}
            foreign={'Authorization':'Bearer '+api.generate_mobile_token(other)}
            assert client.post(f'/api/mobile/reviews/{sid}/read',headers=foreign).status_code==404
            assert client.get('/api/admin/messages',headers=headers).status_code==403
            assert client.get('/api/mobile/notifications',headers=headers).headers['cache-control']=='no-store'
            assert client.get('/api/mobile/notifications?limit=100000',headers=headers).status_code==422
            assert client.get('/api/does-not-exist',headers=headers).status_code==404
            attempts=[client.post('/api/mobile/login',json={'email':'nobody@example.com','password':'SyntheticInvalid!'}) for _ in range(24)]
            assert sum(r.status_code==401 for r in attempts)==20
            assert sum(r.status_code==429 for r in attempts)==4
            assert int(attempts[-1].headers['retry-after'])>0
        print('PASS authenticated API: cross-owner review read refused, operator log denied to farmer, bounded page and private headers')
        print('PASS actual HTTP authentication burst: 20 invalid attempts return 401, next four return 429 with Retry-After')
        idle_token=api.generate_mobile_token(farmer)
        live_token=api.generate_mobile_token(farmer)
        import hashlib
        idle_sid=api.token_serializer.loads(idle_token,salt='geosustain-mobile')['sid']
        with connect() as conn:
            with conn.cursor() as cur:
                cur.execute("UPDATE session_activity SET last_seen=NOW()-INTERVAL '31 minutes' WHERE session_hash=%s",(hashlib.sha256(idle_sid.encode()).hexdigest(),))
        with TestClient(api.app) as client:
            assert client.get('/api/mobile/me',headers={'Authorization':'Bearer '+idle_token}).status_code==401
            assert client.get('/api/mobile/me',headers={'Authorization':'Bearer '+live_token}).status_code==200
            assert client.get('/api/mobile/me',headers={'Authorization':'Bearer '+idle_token}).status_code==401
        print('PASS idle expiry: 31-minute inactive session remains rejected, independent active session works')

        with ThreadPoolExecutor(max_workers=8) as pool:
            quotas=list(pool.map(lambda _:closure.consume_quota('worker-shared','fixture',10),range(24)))
        assert quotas.count(0)==10 and sum(q>0 for q in quotas)==14
        with connect() as conn:
            with conn.cursor() as cur:
                cur.execute("UPDATE request_quotas SET window_start=NOW()-INTERVAL '301 seconds'")
        assert closure.consume_quota('worker-shared','fixture',10)==0
        print('PASS shared quotas: 24 concurrent separate connections admit exactly 10; 14 blocked, expired window recovers')
        with connect() as conn:
            with conn.cursor() as cur:
                cur.execute('SELECT current_schema() AS schema')
                schema=cur.fetchone()['schema']
        fixture=str(Path(__file__).with_name('closure_worker_fixture.py'))
        processes=[subprocess.Popen([sys.executable,fixture,'quota',schema],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True) for _ in range(2)]
        totals=[json.loads(p.communicate(timeout=30)[0]) for p in processes]
        assert all(p.returncode==0 for p in processes)
        assert sum(r['allowed'] for r in totals)==10 and sum(r['blocked'] for r in totals)==6
        print('PASS separate-process quota: two Python workers share exactly 10 admissions out of 16 calls')

        body=api.AnalysisBody(lat=7.29,lon=125.62)
        payload=body.model_dump(exclude_none=True)
        key,digest=api.request_identity('persistent-job-0001',payload)
        jobs.enqueue(farmer,key,digest,payload)
        jobs.enqueue(farmer,key,digest,payload)
        assert jobs.status(uid,key)['stage']=='queued'
        stopped=subprocess.Popen([sys.executable,fixture,'hold',schema,str(uid),key],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        try:
            assert stopped.stdout.readline().strip()=='LOCK_READY'
            assert db.analysis_request_status(uid,key)['status']=='processing'
        finally:
            stopped.terminate()  # only the exact test-owned subprocess, never a user server
            stopped.communicate(timeout=15)
        result={'lat':7.29,'lon':125.62,'predicted_crop':'cacao','crop_compatibility_pct':71}
        with patch.object(api,'build_analysis_result',return_value=(result,'synthetic-fixture')) as inference:
            with ThreadPoolExecutor(max_workers=2) as pool:
                list(pool.map(lambda _: jobs.run_batch(),range(2)))
            assert inference.call_count==1
        assert jobs.status(uid,key) is None
        assert db.analysis_request_status(uid,key)['status']=='completed'
        with connect() as conn:
            with conn.cursor() as cur:
                cur.execute('SELECT COUNT(*) AS n FROM analysis_sessions WHERE user_id=%s AND request_key=%s',(uid,key))
                assert cur.fetchone()['n']==1
        print('PASS durable job: actual test-worker termination releases PG lock, persisted running job recovered, two competing workers compute once, result retrievable')
        key2,digest2=api.request_identity('persistent-job-0002',payload)
        jobs.enqueue(farmer,key2,digest2,payload)
        with patch.object(api,'build_analysis_result',side_effect=RuntimeError('simulated provider outage')):
            jobs.run_batch()
        assert jobs.status(uid,key2)['status']=='failed'
        jobs.enqueue(farmer,key2,digest2,payload)
        with patch.object(api,'build_analysis_result',return_value=(result,'synthetic-fixture')):
            jobs.run_batch()
        assert db.analysis_request_status(uid,key2)['status']=='completed'
        print('PASS durable retry: provider failure exposes failed status; explicit retry reuses identity and completes')

        with connect() as conn:
            with conn.cursor() as cur:
                cur.execute("INSERT INTO analysis_sessions(user_id,center_lat,center_lon,verification_status,place_name) SELECT %s,7.29,125.62,'pending','Seeded fixture ' || n FROM generate_series(1,25020) n",(uid,))
                cur.execute('ANALYZE analysis_sessions')
                cur.execute('EXPLAIN (ANALYZE,BUFFERS,FORMAT JSON) SELECT id FROM analysis_sessions WHERE user_id=%s ORDER BY analyzed_at DESC,id DESC LIMIT 51',(uid,))
                metrics['history_query_plan']=cur.fetchone()['QUERY PLAN']
        def read_batch(i):
            started=time.perf_counter()
            rows=db.get_user_history(uid,limit=50,offset=(i%20)*50)
            assert len(rows)==50
            return (time.perf_counter()-started)*1000
        latencies=[]
        for workers in [1,4,8]:
            with ThreadPoolExecutor(max_workers=workers) as pool:
                samples=list(pool.map(read_batch,range(40)))
            latencies+=samples
            metrics[f'reads_concurrency_{workers}']={'count':len(samples),'p95_ms':round(sorted(samples)[37],2),'max_ms':round(max(samples),2)}
        # A bounded ten-minute soak can be selected explicitly; default 60 seconds.
        duration=max(5,int(os.getenv('CLOSURE_SOAK_SECONDS','60')))
        started=time.monotonic()
        reads=0
        while time.monotonic()-started<duration:
            read_batch(reads)
            reads+=1
            time.sleep(.05)
        metrics['soak']={'seconds':round(time.monotonic()-started,2),'reads':reads,'errors':0,'scope':'local PG reads, no external providers or compiled UI'}
        assert statistics.median(latencies)<1000
        assert max(latencies)<5000
        assert len(db.admin_list_users(q="' OR 1=1 --"))==0
        assert len(db.admin_list_analyses(q='<script>alert(1)</script>'))==0
        print('PASS 25,020-row local backend benchmark: concurrency 1/4/8; all 120 batches contain 50 rows; median <1s, worst <5s; bounded soak completed')
        print('PASS literal SQL/script-shaped search: no broadened results or SQL errors')

        db.delete_user(uid)
        assert closure.inbox(uid)['notifications']==[]
        with connect() as conn:
            with conn.cursor() as cur:
                cur.execute('SELECT COUNT(*) AS n FROM analysis_jobs WHERE user_id=%s',(uid,))
                assert cur.fetchone()['n']==0
        print('PASS account deletion: notification inbox and job payloads cascade away with owned analysis data')
    out=Path(__file__).resolve().parents[2]/'defense-evidence/2026-10-23/partial-closure-execution/metrics.json'
    out.write_text(json.dumps(metrics,indent=2,default=str),encoding='utf-8')
    print('PASS new closure checks; disposable schema removed; no live provider/device/deployment result claimed')


if __name__=='__main__':
    run()
