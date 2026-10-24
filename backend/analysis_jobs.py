"""Optional durable analysis queue; PostgreSQL locks release on worker termination.

Enable ANALYSIS_JOBS_ENABLED=1 on every API worker. The payload and retry key
survive restarts; completed results still use the existing unique request key.
"""
import os
import threading

from psycopg2.extras import Json
from fastapi import HTTPException
import database as db


def enabled():
    return os.getenv('ANALYSIS_JOBS_ENABLED', '0') == '1'


def migrate(cur):
    cur.execute("""CREATE TABLE IF NOT EXISTS analysis_jobs (
        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        request_key VARCHAR(160) NOT NULL, request_hash CHAR(64) NOT NULL,
        payload JSONB NOT NULL, status VARCHAR(16) NOT NULL DEFAULT 'queued',
        password_version INTEGER NOT NULL, attempts INTEGER NOT NULL DEFAULT 0,
        error_code INTEGER, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), PRIMARY KEY(user_id,request_key))""")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_analysis_jobs_pending ON analysis_jobs(created_at) WHERE status IN ('queued','running')")


def enqueue(user, key, digest, payload):
    conn = db.get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute('SELECT pg_advisory_xact_lock(hashtextextended(%s,0))', (f'enqueue:{user["id"]}',))
            cur.execute('SELECT request_hash,status FROM analysis_jobs WHERE user_id=%s AND request_key=%s', (user['id'],key))
            old = cur.fetchone()
            if old and old['request_hash'] != digest:
                raise HTTPException(409, 'This request identity already belongs to different inputs.')
            if old and old['status'] in ('queued','running','completed'):
                return
            cur.execute("SELECT COUNT(*) AS count FROM analysis_jobs WHERE user_id=%s AND status IN ('queued','running')", (user['id'],))
            if cur.fetchone()['count'] >= 2:
                raise HTTPException(429, 'Two analyses are already waiting. Check their results before starting another.', headers={'Retry-After':'30'})
            from qa_closure import enforce_quota
            enforce_quota(user['id'], 'analysis', 10)
            enforce_quota('all', 'provider_analysis', 60)
            cur.execute("""INSERT INTO analysis_jobs(user_id,request_key,request_hash,payload,password_version)
                VALUES (%s,%s,%s,%s,%s) ON CONFLICT (user_id,request_key)
                DO UPDATE SET status='queued',error_code=NULL,attempts=0,password_version=EXCLUDED.password_version,updated_at=NOW()""",
                (user['id'],key,digest,Json(payload),user.get('password_version',0)))
        conn.commit()
    finally:
        conn.close()


def status(user_id, key):
    conn = db.get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute('SELECT status,error_code FROM analysis_jobs WHERE user_id=%s AND request_key=%s', (user_id,key))
            row = cur.fetchone()
        if row and row['status'] in ('queued','running'):
            return {'status':'processing','stage':row['status'],'request_id':key}
        if row and row['status'] == 'failed':
            return {'status':'failed','error_code':row['error_code'], 'message':'Analysis could not complete. Check the farm and retry.'}
        return None
    finally:
        conn.close()


def _update(uid, key, state, error=None):
    conn = db.get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute("UPDATE analysis_jobs SET status=%s,error_code=%s,updated_at=NOW(),attempts=attempts+CASE WHEN %s='running' THEN 1 ELSE 0 END WHERE user_id=%s AND request_key=%s", (state,error,state,uid,key))
            if state == 'failed':
                cur.execute('SELECT payload FROM analysis_jobs WHERE user_id=%s AND request_key=%s', (uid,key))
                row=cur.fetchone()
                if row:
                    from activity_notifications import failed
                    failed(cur,uid,key,row['payload'].get('farm_id'),error)
        conn.commit()
    finally:
        conn.close()


def run_batch(limit=2):
    import fastapi_app as api
    conn = db.get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM analysis_jobs WHERE status IN ('queued','running') ORDER BY created_at LIMIT %s", (limit,))
            rows = cur.fetchall()
    finally:
        conn.close()
    for row in rows:
        uid, key = row['user_id'], row['request_key']
        with db.analysis_request_lock(uid,key) as acquired:
            if not acquired:
                continue
            # A competing worker may have completed since the candidate scan.
            current = status(uid,key)
            if not current or current['status'] != 'processing':
                continue
            try:
                user = db.get_user_by_id(uid)
                if not user or not user['is_active'] or user.get('password_version',0) != row['password_version']:
                    raise HTTPException(401, 'Account access changed.')
                if row['attempts'] >= 3:
                    raise HTTPException(503, 'Repeated interruption; retry explicitly.')
                _update(uid,key,'running')
                api._perform_mobile_analysis(api.AnalysisBody.model_validate(row['payload']), user, key, charge_quota=False)
                _update(uid,key,'completed')
            except Exception as exc:
                _update(uid,key,'failed',exc.status_code if isinstance(exc,HTTPException) else 503)


def start_worker():
    if not enabled():
        return
    def run():
        import logging
        while not threading.Event().wait(2):
            try:
                run_batch()
            except Exception:
                logging.getLogger('uvicorn.error').warning('Analysis queue unavailable; next worker poll will retry.')
    threading.Thread(target=run, name='geosustain-analysis-jobs', daemon=True).start()
