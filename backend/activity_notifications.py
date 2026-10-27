"""Versioned, account-owned activity inbox; legacy review inbox stays compatible."""
import database as db
from contextlib import closing

EVENT_TYPES = ('analysis_ready', 'analysis_partial', 'analysis_failed', 'submitted', 'review', 'submission_received', 'needs_information', 'resubmitted', 'advisory_note', 'followup_created', 'followup_completed', 'followup_due')

def migrate(cur):
    cur.execute('''CREATE TABLE IF NOT EXISTS activity_notifications (
        id BIGSERIAL PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        event_key VARCHAR(240) NOT NULL, event_type VARCHAR(32) NOT NULL,
        session_id INTEGER REFERENCES analysis_sessions(id) ON DELETE CASCADE,
        farm_id INTEGER REFERENCES farm_parcels(id) ON DELETE SET NULL,
        message TEXT NOT NULL, decision VARCHAR(16),
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), read_at TIMESTAMPTZ,
        UNIQUE(user_id,event_key))''')
    cur.execute('CREATE INDEX IF NOT EXISTS idx_activity_owner ON activity_notifications(user_id,id DESC)')
    cur.execute('''CREATE TABLE IF NOT EXISTS activity_push_deliveries (
        id BIGSERIAL PRIMARY KEY,token TEXT NOT NULL REFERENCES push_subscriptions(token) ON DELETE CASCADE,
        activity_id BIGINT NOT NULL REFERENCES activity_notifications(id) ON DELETE CASCADE,
        attempts INTEGER NOT NULL DEFAULT 0,next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        accepted_at TIMESTAMPTZ,last_error VARCHAR(80),UNIQUE(token,activity_id))''')
    cur.execute('''CREATE INDEX IF NOT EXISTS idx_activity_push_pending ON activity_push_deliveries(next_attempt_at,id)
        WHERE accepted_at IS NULL''')
    cur.execute('''INSERT INTO activity_notifications(user_id,event_key,event_type,session_id,message,decision,created_at,read_at)
        SELECT user_id,'review:'||session_id,'review',session_id,'An analyst reviewed your analysis.',decision,created_at,read_at
        FROM review_notifications WHERE session_id IS NOT NULL ON CONFLICT(user_id,event_key) DO NOTHING''')

def analysis_saved(cur, user_id, session_id, partial):
    cur.execute('''INSERT INTO activity_notifications(user_id,event_key,event_type,session_id,farm_id,message)
        SELECT user_id,'analysis:'||id,%s,id,farm_id,%s FROM analysis_sessions WHERE id=%s AND user_id=%s
        ON CONFLICT(user_id,event_key) DO NOTHING''',
        ('analysis_partial' if partial else 'analysis_ready',
         'A partial assessment was saved. Check missing observations before making a decision.' if partial else 'Your analysis is saved and ready to view.', session_id,user_id))
    cur.execute('''INSERT INTO activity_push_deliveries(token,activity_id)
        SELECT p.token,n.id FROM activity_notifications n JOIN push_subscriptions p ON p.user_id=n.user_id
        JOIN users u ON u.id=n.user_id WHERE n.user_id=%s AND n.event_key='analysis:'||%s
        AND u.is_active=TRUE AND u.password_version=p.password_version ON CONFLICT(token,activity_id) DO NOTHING''',
        (user_id,session_id))

def submitted(cur, user_id, session_id):
    cur.execute('''INSERT INTO activity_notifications(user_id,event_key,event_type,session_id,farm_id,message)
        SELECT user_id,'submitted:'||id,'submitted',id,farm_id,'Your assessment is awaiting analyst review.'
        FROM analysis_sessions WHERE id=%s AND user_id=%s AND verification_status='pending'
        ON CONFLICT(user_id,event_key) DO NOTHING''', (session_id,user_id))
    cur.execute('''INSERT INTO activity_notifications(user_id,event_key,event_type,session_id,message)
        SELECT u.id,'submission:'||s.id,'submission_received',s.id,'A new assessment is available in the authorized review queue.'
        FROM users u CROSS JOIN analysis_sessions s WHERE s.id=%s AND s.user_id=%s
        AND s.verification_status='pending' AND u.is_active=TRUE AND u.role='agricultural_planning_analyst'
        ON CONFLICT(user_id,event_key) DO NOTHING''', (session_id,user_id))

def reviewed(cur, session_id):
    cur.execute('''INSERT INTO activity_notifications(user_id,event_key,event_type,session_id,farm_id,message,decision,case_id)
        SELECT s.user_id,'review:'||s.id,'review',s.id,s.farm_id,'An analyst reviewed your analysis.',s.verification_status,c.id
        FROM analysis_sessions s LEFT JOIN review_cases c ON c.current_session_id=s.id WHERE s.id=%s AND s.verification_status IN ('verified','rejected')
        ON CONFLICT(user_id,event_key) DO NOTHING''', (session_id,))

def failed(cur, user_id, request_key, farm_id, code):
    message = 'Analysis could not complete. Check data coverage and the farm boundary, then retry online.' if code in (400,404,409,422) else 'Analysis could not complete. Reconnect or try again later; your farm is retained.'
    cur.execute('''INSERT INTO activity_notifications(user_id,event_key,event_type,farm_id,message)
        SELECT u.id,%s,'analysis_failed',f.id,%s FROM users u
        LEFT JOIN farm_parcels f ON f.id=%s AND f.farmer_id=u.id WHERE u.id=%s AND u.is_active=TRUE
        ON CONFLICT(user_id,event_key) DO NOTHING''', ('failed:'+request_key,message,farm_id,user_id))

def record_failure(user_id, request_key, farm_id, code):
    with closing(db.get_conn()) as conn, conn:
        with conn.cursor() as cur: failed(cur,user_id,request_key,farm_id,code)

def inbox(user_id, offset=0, limit=50, unread_only=False, event_type=None):
    where = 'n.user_id=%s'; params = [user_id]
    if unread_only: where += ' AND n.read_at IS NULL'
    if event_type: where += ' AND n.event_type=%s'; params.append(event_type)
    conn = db.get_conn()
    try:
        with conn.cursor() as cur:
            due_followups(cur,user_id)
            conn.commit()
            cur.execute('SELECT COUNT(*) AS unread FROM activity_notifications WHERE user_id=%s AND read_at IS NULL', (user_id,))
            unread = cur.fetchone()['unread']
            cur.execute(f'''SELECT n.*,f.farm_name FROM activity_notifications n
                LEFT JOIN farm_parcels f ON f.id=n.farm_id AND f.farmer_id=n.user_id
                WHERE {where} ORDER BY n.id DESC LIMIT %s OFFSET %s''', (*params,limit+1,offset))
            rows = [dict(row) for row in cur.fetchall()]
        return {'notifications':rows[:limit], 'unread_count':unread, 'has_more':len(rows)>limit, 'offset':offset}
    finally: conn.close()

def mark_read(user_id, event_id):
    with closing(db.get_conn()) as conn, conn:
        with conn.cursor() as cur:
            cur.execute('''UPDATE activity_notifications SET read_at=COALESCE(read_at,NOW())
                WHERE user_id=%s AND id=%s RETURNING id,read_at''', (user_id,event_id))
            row = cur.fetchone()
            if row:
                # Maintain read compatibility for already installed older clients.
                cur.execute('''UPDATE review_notifications r SET read_at=COALESCE(r.read_at,NOW())
                    FROM activity_notifications n WHERE n.id=%s AND n.user_id=%s AND n.event_type='review'
                    AND r.user_id=n.user_id AND r.session_id=n.session_id''', (event_id,user_id))
        return dict(row) if row else None

def mark_all(user_id):
    with closing(db.get_conn()) as conn, conn:
        with conn.cursor() as cur:
            cur.execute('UPDATE activity_notifications SET read_at=COALESCE(read_at,NOW()) WHERE user_id=%s AND read_at IS NULL', (user_id,))
            count = cur.rowcount
            cur.execute('UPDATE review_notifications SET read_at=COALESCE(read_at,NOW()) WHERE user_id=%s AND read_at IS NULL', (user_id,))
        return {'marked_read':count}


def case_event(cur, case, event_id, kind):
    if kind in ('verified','rejected'):
        return  # The legacy-compatible review event is already queued transactionally.
    messages={
        'needs_information':'Your reviewer requested information. Open the case to see correction items.',
        'resubmitted':'A corrected analysis revision is ready for review.',
        'advisory_note':'An analyst added a note to your review case.',
        'followup_created':'A follow-up task was assigned to you.',
        'followup_completed':'Your follow-up task was completed.'}
    if kind not in messages:return
    if kind=='resubmitted':
        cur.execute("SELECT id FROM users WHERE is_active=TRUE AND role='agricultural_planning_analyst'")
        recipients=[r['id'] for r in cur.fetchall()]
    elif kind.startswith('followup_'):
        cur.execute('SELECT actor_id FROM review_case_events WHERE id=%s',(event_id,))
        recipients=[cur.fetchone()['actor_id']]
    else:recipients=[case['owner_id']]
    for uid in recipients:
        if uid is None:continue
        cur.execute("""INSERT INTO activity_notifications(user_id,event_key,event_type,session_id,farm_id,case_id,message)
            VALUES(%s,%s,%s,%s,%s,%s,%s) ON CONFLICT(user_id,event_key) DO NOTHING""",
            (uid,'case-event:'+str(event_id),kind,case['current_session_id'],case['farm_id'],case['id'],messages[kind]))
    queue_activity_push(cur)


def queue_activity_push(cur):
    cur.execute("""INSERT INTO activity_push_deliveries(token,activity_id)
        SELECT p.token,n.id FROM activity_notifications n JOIN push_subscriptions p ON p.user_id=n.user_id
        JOIN users u ON u.id=n.user_id WHERE n.created_at>=NOW()-INTERVAL '1 day'
        AND n.case_id IS NOT NULL AND u.is_active=TRUE AND u.password_version=p.password_version
        ON CONFLICT(token,activity_id) DO NOTHING""")


def due_followups(cur,user_id):
    cur.execute("""INSERT INTO activity_notifications(user_id,event_key,event_type,session_id,farm_id,case_id,message)
        SELECT f.assigned_to,'followup-due:'||f.id,'followup_due',c.current_session_id,c.farm_id,c.id,
          'A review follow-up is due. Open the case to complete it.' FROM review_followups f
        JOIN review_cases c ON c.id=f.case_id WHERE f.assigned_to=%s AND f.completed_at IS NULL
        AND f.due_on<=CURRENT_DATE ON CONFLICT(user_id,event_key) DO NOTHING""",(user_id,))
    queue_activity_push(cur)
