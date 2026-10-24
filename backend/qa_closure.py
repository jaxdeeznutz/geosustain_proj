"""Persistent review inbox and shared provider quotas. No provider secrets in output."""
import hashlib
import os

import database as db
from fastapi import HTTPException


def migrate(cur):
    cur.execute("""CREATE TABLE IF NOT EXISTS session_activity (
        session_hash CHAR(64) PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        last_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(), expires_at TIMESTAMPTZ NOT NULL)""")
    cur.execute('CREATE INDEX IF NOT EXISTS idx_session_activity_expiry ON session_activity(expires_at)')
    cur.execute("""CREATE TABLE IF NOT EXISTS review_notifications (
        id BIGSERIAL PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        session_id INTEGER UNIQUE REFERENCES analysis_sessions(id) ON DELETE CASCADE,
        decision VARCHAR(16) NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), read_at TIMESTAMPTZ)""")
    cur.execute('CREATE INDEX IF NOT EXISTS idx_notification_owner ON review_notifications(user_id,id DESC)')
    from activity_notifications import migrate as migrate_activity
    migrate_activity(cur)
    cur.execute("""CREATE TABLE IF NOT EXISTS request_quotas (
        bucket CHAR(64) PRIMARY KEY, window_start TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        calls INTEGER NOT NULL DEFAULT 1)""")
    cur.execute('CREATE INDEX IF NOT EXISTS idx_quota_expiry ON request_quotas(window_start)')


def queue_notification(cur, session_id):
    cur.execute("""INSERT INTO review_notifications (user_id,session_id,decision)
        SELECT user_id,id,verification_status FROM analysis_sessions
        WHERE id=%s AND verification_status IN ('verified','rejected')
        ON CONFLICT (session_id) DO NOTHING""", (session_id,))
    from activity_notifications import reviewed
    reviewed(cur,session_id)


def inbox(user_id, offset=0, limit=50):
    conn = db.get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute('SELECT COUNT(*) AS unread FROM review_notifications WHERE user_id=%s AND read_at IS NULL', (user_id,))
            unread = cur.fetchone()['unread']
            cur.execute('SELECT id,session_id,decision,created_at,read_at FROM review_notifications WHERE user_id=%s ORDER BY id DESC LIMIT %s OFFSET %s', (user_id, limit+1, offset))
            rows = [dict(r) for r in cur.fetchall()]
            return {'notifications': rows[:limit], 'unread_count': unread, 'has_more': len(rows)>limit, 'offset': offset}
    finally:
        conn.close()


def read_notification(user_id, notification_id, by_session=False):
    conn = db.get_conn()
    try:
        with conn.cursor() as cur:
            column = 'session_id' if by_session else 'id'
            cur.execute(f'UPDATE review_notifications SET read_at=COALESCE(read_at,NOW()) WHERE user_id=%s AND {column}=%s RETURNING id,session_id,read_at', (user_id, notification_id))
            row = cur.fetchone()
            if row:
                cur.execute("""UPDATE activity_notifications SET read_at=COALESCE(read_at,%s)
                    WHERE user_id=%s AND session_id=%s AND event_type='review'""",
                    (row['read_at'],user_id,row['session_id']))
        conn.commit()
        return dict(row) if row else None
    finally:
        conn.close()


def message_log(offset=0, limit=50):
    conn = db.get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute("""SELECT d.id,d.session_id,p.platform,d.attempts,
                d.next_attempt_at,d.sent_at AS provider_accepted_at,d.last_error,
                CASE WHEN d.sent_at IS NOT NULL THEN 'provider_accepted'
                     WHEN d.attempts>=10 THEN 'exhausted'
                     WHEN d.attempts>0 THEN 'retry_pending' ELSE 'queued' END AS status
                FROM push_deliveries d JOIN push_subscriptions p ON p.token=d.token
                ORDER BY d.id DESC LIMIT %s OFFSET %s""", (limit+1, offset))
            rows = [dict(r) for r in cur.fetchall()]
            return {'messages': rows[:limit], 'has_more': len(rows)>limit,
                    'scope': 'Current subscriptions only; opt-out/account deletion removes their deliveries. Provider acceptance does not prove device receipt.'}
    finally:
        conn.close()


def consume_quota(subject, category, maximum, seconds=300):
    """Atomic fixed window shared by all processes using this database; returns retry seconds."""
    bucket = hashlib.sha256(f'{category}:{subject}'.encode()).hexdigest()
    conn = db.get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM request_quotas WHERE window_start < NOW() - INTERVAL '1 day'")
            cur.execute("""INSERT INTO request_quotas(bucket) VALUES (%s)
                ON CONFLICT (bucket) DO UPDATE SET
                  calls=CASE WHEN request_quotas.window_start<=NOW()-%s*INTERVAL '1 second' THEN 1 ELSE request_quotas.calls+1 END,
                  window_start=CASE WHEN request_quotas.window_start<=NOW()-%s*INTERVAL '1 second' THEN NOW() ELSE request_quotas.window_start END
                RETURNING calls,GREATEST(1,CEIL(%s-EXTRACT(EPOCH FROM (NOW()-window_start)))) AS retry""", (bucket, seconds, seconds, seconds))
            row = cur.fetchone()
        conn.commit()
        return int(row['retry']) if row['calls']>maximum else 0
    finally:
        conn.close()


def enforce_quota(subject, category, default_limit):
    maximum = max(1, int(os.getenv('QUOTA_'+category.upper(), str(default_limit))))
    retry = consume_quota(subject, category, maximum)
    if retry:
        raise HTTPException(429, 'Request limit reached. Wait before retrying.', headers={'Retry-After':str(retry)})
