"""Submitted-case workflow. Analysis snapshots and held soil calculations are unchanged."""
from contextlib import closing
import hashlib
import json

from fastapi import HTTPException
from psycopg2.extras import Json
import database as db

STATUSES = ('pending', 'needs_information', 'verified', 'rejected')
CHECKS = ('reference', 'geometry', 'coverage', 'limitations')


def migrate(cur):
    cur.execute('''CREATE TABLE IF NOT EXISTS review_cases (
        id BIGSERIAL PRIMARY KEY, owner_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        farm_id INTEGER REFERENCES farm_parcels(id) ON DELETE SET NULL,
        current_session_id INTEGER UNIQUE NOT NULL REFERENCES analysis_sessions(id) ON DELETE CASCADE,
        status VARCHAR(32) NOT NULL, version INTEGER NOT NULL DEFAULT 1,
        submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW())''')
    cur.execute('''CREATE TABLE IF NOT EXISTS review_case_revisions (
        case_id BIGINT REFERENCES review_cases(id) ON DELETE CASCADE,
        session_id INTEGER UNIQUE REFERENCES analysis_sessions(id) ON DELETE CASCADE,
        revision INTEGER NOT NULL, PRIMARY KEY(case_id,revision))''')
    cur.execute('''CREATE TABLE IF NOT EXISTS review_case_events (
        id BIGSERIAL PRIMARY KEY,case_id BIGINT NOT NULL REFERENCES review_cases(id) ON DELETE CASCADE,
        session_id INTEGER REFERENCES analysis_sessions(id) ON DELETE SET NULL,
        actor_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
        kind VARCHAR(40) NOT NULL,notes VARCHAR(500),reason VARCHAR(80),checklist JSONB,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW())''')
    cur.execute('''CREATE TABLE IF NOT EXISTS review_followups (
        id BIGSERIAL PRIMARY KEY,case_id BIGINT NOT NULL REFERENCES review_cases(id) ON DELETE CASCADE,
        created_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
        assigned_to INTEGER REFERENCES users(id) ON DELETE SET NULL,
        title VARCHAR(160) NOT NULL,due_on DATE NOT NULL,completed_at TIMESTAMPTZ,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW())''')
    cur.execute('CREATE INDEX IF NOT EXISTS review_cases_status_age ON review_cases(status,submitted_at,id)')
    cur.execute('CREATE INDEX IF NOT EXISTS review_events_case ON review_case_events(case_id,id)')
    cur.execute('ALTER TABLE activity_notifications ADD COLUMN IF NOT EXISTS case_id BIGINT REFERENCES review_cases(id) ON DELETE CASCADE')
    cur.execute('ALTER TABLE activity_notifications ALTER COLUMN decision TYPE VARCHAR(32)')
    cur.execute('''INSERT INTO review_cases(owner_id,farm_id,current_session_id,status,submitted_at,updated_at)
        SELECT user_id,farm_id,id,verification_status,COALESCE(submitted_at,analyzed_at),COALESCE(verified_at,submitted_at,analyzed_at)
        FROM analysis_sessions s WHERE verification_status IN ('pending','verified','rejected','needs_information')
        AND EXISTS(SELECT 1 FROM users u WHERE u.id=s.user_id AND u.role='farmer')
        AND NOT EXISTS(SELECT 1 FROM review_case_revisions r WHERE r.session_id=s.id)
        ON CONFLICT(current_session_id) DO NOTHING''')
    cur.execute('''INSERT INTO review_case_revisions(case_id,session_id,revision)
        SELECT id,current_session_id,1 FROM review_cases ON CONFLICT DO NOTHING''')
    cur.execute('''INSERT INTO review_case_events(case_id,session_id,actor_id,kind,notes,created_at)
        SELECT c.id,s.id,s.verified_by,'imported_'||c.status,left(s.planner_notes,500),c.updated_at
        FROM review_cases c JOIN analysis_sessions s ON s.id=c.current_session_id
        WHERE NOT EXISTS(SELECT 1 FROM review_case_events e WHERE e.case_id=c.id)''')


def ensure_case(cur, session_id, lock=False):
    cur.execute('''INSERT INTO review_cases(owner_id,farm_id,current_session_id,status,submitted_at)
        SELECT s.user_id,s.farm_id,s.id,s.verification_status,COALESCE(s.submitted_at,s.analyzed_at)
        FROM analysis_sessions s WHERE s.id=%s AND s.verification_status IN ('pending','verified','rejected','needs_information')
        AND EXISTS(SELECT 1 FROM users u WHERE u.id=s.user_id AND u.role='farmer')
        AND NOT EXISTS(SELECT 1 FROM review_case_revisions r WHERE r.session_id=s.id)
        ON CONFLICT(current_session_id) DO NOTHING''', (session_id,))
    cur.execute('''SELECT c.* FROM review_cases c WHERE c.current_session_id=%s'''+(' FOR UPDATE' if lock else ''), (session_id,))
    row=cur.fetchone()
    if row:
        cur.execute('INSERT INTO review_case_revisions(case_id,session_id,revision) VALUES(%s,%s,1) ON CONFLICT DO NOTHING', (row['id'],session_id))
        cur.execute('UPDATE activity_notifications SET case_id=%s WHERE session_id=%s AND case_id IS NULL',(row['id'],session_id))
        cur.execute('''INSERT INTO review_case_events(case_id,session_id,actor_id,kind,created_at)
            SELECT id,current_session_id,owner_id,'submitted',submitted_at FROM review_cases c
            WHERE c.id=%s AND NOT EXISTS(SELECT 1 FROM review_case_events e WHERE e.case_id=c.id)''',(row['id'],))
    return row


def event(cur, case, actor, kind, notes=None, reason=None, checklist=None):
    cur.execute('''INSERT INTO review_case_events(case_id,session_id,actor_id,kind,notes,reason,checklist)
        VALUES(%s,%s,%s,%s,%s,%s,%s) RETURNING id''',
        (case['id'],case['current_session_id'],actor,kind,notes,reason,Json(checklist or {})))
    event_id=cur.fetchone()['id']
    from activity_notifications import case_event
    case_event(cur,case,event_id,kind)
    db.audit_in_transaction(cur,actor,'agricultural_planning_analyst' if kind!='resubmitted' else 'farmer',
        'review_'+kind,'review_case',case['id'],{'session_id':case['current_session_id'],'has_notes':bool(notes)})


def legacy_decided(cur, session_id, actor, status, notes):
    case=ensure_case(cur,session_id,lock=True)
    if case:
        cur.execute('UPDATE review_cases SET status=%s,version=version+1,updated_at=NOW() WHERE id=%s RETURNING *', (status,case['id']))
        event(cur,cur.fetchone(),actor,status,notes,reason='legacy_review')


def conditions(status='all', q='', place='', start=None, end=None, view='all'):
    where='TRUE';values=[]
    if status!='all':
        if status not in STATUSES: raise HTTPException(422,'Unknown review status.')
        where+=' AND c.status=%s';values.append(status)
    if q:
        where+=" AND concat_ws(' ',c.id,s.place_name,u.username,s.farm_name_snapshot) ILIKE %s";values.append('%'+q+'%')
    if place:
        where+=' AND s.place_name ILIKE %s';values.append('%'+place+'%')
    if start: where+=' AND c.submitted_at>=%s::date';values.append(start)
    if end: where+=" AND c.submitted_at<%s::date+INTERVAL '1 day'";values.append(end)
    if view=='preliminary':where+=" AND s.result_snapshot->>'analysis_mode'='preliminary_environmental'"
    elif view=='reviewed_week':where+=" AND c.status IN ('verified','rejected') AND c.updated_at>=NOW()-INTERVAL '7 days'"
    elif view=='followups_due':where+=" AND EXISTS(SELECT 1 FROM review_followups f WHERE f.case_id=c.id AND f.completed_at IS NULL AND f.due_on<=CURRENT_DATE)"
    elif view!='all':raise HTTPException(422,'Unknown workload view.')
    return where,values


FROM = ''' FROM review_cases c JOIN analysis_sessions s ON s.id=c.current_session_id
    JOIN users u ON u.id=c.owner_id LEFT JOIN LATERAL (
      SELECT predicted_crop,compatibility_pct,is_crop_recommended,land_type FROM crop_recommendations
      WHERE session_id=s.id ORDER BY id DESC LIMIT 1) crop ON TRUE '''
FIELDS = '''c.id AS case_id,c.current_session_id AS session_id,c.status AS verification_status,c.version AS review_version,
    c.farm_id,c.submitted_at,c.updated_at,s.farm_name_snapshot AS farm_name,s.place_name,s.analyzed_at,
    s.area_hectares,s.center_lat,s.center_lon,u.username AS farmer_name,
    s.result_snapshot->>'analysis_mode' AS analysis_mode,crop.predicted_crop,crop.is_crop_recommended,crop.land_type,
    CASE WHEN COALESCE(s.result_snapshot->>'analysis_mode','')<>'preliminary_environmental'
      AND crop.is_crop_recommended IS TRUE AND COALESCE(crop.land_type,'arable')='arable'
      AND crop.compatibility_pct BETWEEN 0 AND 100 THEN crop.compatibility_pct END AS compatibility_pct'''


def inbox(status='pending',q='',place='',start=None,end=None,offset=0,limit=20,sort='oldest',map_view=False,bounds=None,view='all'):
    where,values=conditions(status,q,place,start,end,view)
    if bounds:
        west,south,east,north=bounds
        if west>east or south>north: raise HTTPException(422,'Invalid map bounds.')
        where+=' AND s.center_lon BETWEEN %s AND %s AND s.center_lat BETWEEN %s AND %s';values += [west,east,south,north]
    order='c.submitted_at '+('DESC' if sort=='newest' else 'ASC')+',c.id '+('DESC' if sort=='newest' else 'ASC')
    with closing(db.get_conn()) as conn,conn.cursor() as cur:
        cur.execute('SELECT '+FIELDS+(',s.selected_polygon' if map_view else '')+FROM+' WHERE '+where+' ORDER BY '+order+' LIMIT %s OFFSET %s',(*values,limit+1,offset))
        rows=[dict(r) for r in cur.fetchall()]
    return {'queue':rows[:limit],'has_more':len(rows)>limit,'scope':'Submitted review cases; authorized project records only. Map bounds filter parcel centers.'}


def overview(q='',place='',start=None,end=None):
    where,values=conditions('all',q,place,start,end)
    with closing(db.get_conn()) as conn,conn.cursor() as cur:
        cur.execute('''SELECT COUNT(*) AS cases,COUNT(*) FILTER(WHERE c.status='pending') AS pending_count,
            COUNT(*) FILTER(WHERE c.status='needs_information') AS information_count,
            COUNT(*) FILTER(WHERE c.status='verified') AS verified_count,
            COUNT(*) FILTER(WHERE c.status='rejected') AS rejected_count,
            COUNT(*) FILTER(WHERE c.status IN ('verified','rejected') AND c.updated_at>=NOW()-INTERVAL '7 days') AS reviewed_week,
            COUNT(*) FILTER(WHERE s.result_snapshot->>'analysis_mode'='preliminary_environmental') AS preliminary_count,
            COUNT(DISTINCT c.farm_id) AS distinct_farms,
            MIN(c.submitted_at) FILTER(WHERE c.status='pending') AS oldest_pending'''+FROM+' WHERE '+where,values)
        result=dict(cur.fetchone())
        cur.execute('''SELECT CASE WHEN COUNT(*)=0 THEN 0 ELSE SUM(area_hectares) END AS parcel_area_sum_ha,
            COUNT(area_hectares) AS farms_with_area,COUNT(*)-COUNT(area_hectares) AS farms_without_area FROM (
            SELECT DISTINCT ON(c.farm_id) c.farm_id,s.area_hectares'''+FROM+' WHERE '+where+''' AND c.farm_id IS NOT NULL
            ORDER BY c.farm_id,s.analyzed_at DESC,s.id DESC) latest''',values)
        result.update(cur.fetchone())
        cur.execute('SELECT COUNT(*) AS followups_due'+FROM+' JOIN review_followups f ON f.case_id=c.id WHERE '+where+' AND f.completed_at IS NULL AND f.due_on<=CURRENT_DATE',values)
        result.update(cur.fetchone())
    return dict(result,scope='Submitted project cases; date filters use submission date. Latest analyzed parcel per distinct farm; parcel area sum may overlap. Recommendation counts are not planting/production statistics.')


def detail(case_id,owner_id=None):
    with closing(db.get_conn()) as conn,conn.cursor() as cur:
        cur.execute('SELECT c.* FROM review_cases c WHERE c.id=%s'+(' AND c.owner_id=%s' if owner_id is not None else ''), (case_id,owner_id) if owner_id is not None else (case_id,))
        case=cur.fetchone()
        if not case: raise HTTPException(404,'Review case not found.')
        cur.execute('''SELECT e.id,e.kind,e.notes,e.reason,e.checklist,e.session_id,e.created_at,u.username AS actor_name
            FROM review_case_events e LEFT JOIN users u ON u.id=e.actor_id WHERE case_id=%s ORDER BY e.id''',(case_id,))
        events=[dict(r) for r in cur.fetchall()]
        cur.execute('''SELECT r.revision,r.session_id,s.analyzed_at,s.boundary_version FROM review_case_revisions r
            JOIN analysis_sessions s ON s.id=r.session_id WHERE r.case_id=%s ORDER BY revision''',(case_id,))
        revisions=[dict(r) for r in cur.fetchall()]
        cur.execute('''SELECT f.*,u.username AS assigned_name FROM review_followups f LEFT JOIN users u ON u.id=f.assigned_to
            WHERE f.case_id=%s ORDER BY f.due_on,f.id''',(case_id,))
        followups=[dict(r) for r in cur.fetchall()]
    record=db.get_user_analysis(case['owner_id'],case['current_session_id'])
    if not record: raise HTTPException(404,'The recorded analysis is unavailable.')
    farm=db.get_farm_parcel(case['owner_id'],case['farm_id']) if case['farm_id'] else None
    def geometry_hash(value):
        if isinstance(value,str): value=json.loads(value)
        return hashlib.sha256(json.dumps(value or [],sort_keys=True,separators=(',',':')).encode()).hexdigest()
    # Coordinate-object normalization handles JSON number and key representation.
    def ring(value):
        if isinstance(value,str):value=json.loads(value)
        if not value:return []
        return db.normalize_polygon(value)
    recorded_ring=ring(record.get('selected_polygon'))
    current_ring=ring(farm.get('polygon')) if farm else []
    same_geometry=recorded_ring==current_ring if len(recorded_ring)>=3 and len(current_ring)>=3 else None
    return {'case':dict(case),'analysis':record,'events':events,'revisions':revisions,'followups':followups,
        'geometry_matches_current':same_geometry,'current_farm_version':farm.get('boundary_version') if farm else None,
        'recorded_geometry_hash':geometry_hash(ring(record.get('selected_polygon')))}


def decide(case_id,actor,status,version,notes='',reason='',checklist=None):
    notes=(notes or '').strip();reason=(reason or '').strip();checklist=checklist or {}
    if status not in ('verified','rejected','needs_information'): raise HTTPException(422,'Unknown decision.')
    if len(notes)>500 or (status!='verified' and not notes): raise HTTPException(422,'Add an explanation of at most 500 characters.')
    if status!='verified' and not reason: raise HTTPException(422,'Choose a reason for this decision.')
    if status=='verified' and not all(checklist.get(k) is True for k in CHECKS): raise HTTPException(422,'Review each evidence checklist item first.')
    with closing(db.get_conn()) as conn,conn:
        with conn.cursor() as cur:
            cur.execute('SELECT * FROM review_cases WHERE id=%s FOR UPDATE',(case_id,));case=cur.fetchone()
            if not case: raise HTTPException(404,'Review case not found.')
            if case['owner_id']==actor: raise HTTPException(403,'You cannot review your own submission.')
            if case['version']!=version or case['status']!='pending': raise HTTPException(409,'This case changed or was already reviewed. Reload the current decision.')
            cur.execute('''UPDATE analysis_sessions SET verification_status=%s,verified_by=%s,verified_at=NOW(),planner_notes=%s
                WHERE id=%s AND verification_status='pending' RETURNING id''',(status,actor,notes,case['current_session_id']))
            if not cur.fetchone():raise HTTPException(409,'This analysis changed. Reload before reviewing.')
            cur.execute('UPDATE review_cases SET status=%s,version=version+1,updated_at=NOW() WHERE id=%s RETURNING *',(status,case_id));case=cur.fetchone()
            event(cur,case,actor,status,notes,reason,checklist)
            if status in ('verified','rejected'):
                from push_delivery import queue_review
                from qa_closure import queue_notification
                queue_review(cur,case['current_session_id']);queue_notification(cur,case['current_session_id'])
    return detail(case_id)


def candidates(case_id,owner):
    case=detail(case_id,owner)['case']
    with closing(db.get_conn()) as conn,conn.cursor() as cur:
        cur.execute('''SELECT id AS session_id,analyzed_at,farm_name_snapshot,area_hectares FROM analysis_sessions s
            WHERE s.user_id=%s AND s.farm_id IS NOT DISTINCT FROM %s AND s.verification_status='draft'
            AND s.analyzed_at>(SELECT analyzed_at FROM analysis_sessions WHERE id=%s)
            AND NOT EXISTS(SELECT 1 FROM review_case_revisions r WHERE r.session_id=s.id)
            ORDER BY s.id DESC LIMIT 50''',(owner,case['farm_id'],case['current_session_id']))
        return [dict(r) for r in cur.fetchall()]


def resubmit(case_id,owner,session_id,version,notes):
    notes=notes.strip()
    if not notes or len(notes)>500:raise HTTPException(422,'Describe the correction in at most 500 characters.')
    with closing(db.get_conn()) as conn,conn:
        with conn.cursor() as cur:
            cur.execute('SELECT * FROM review_cases WHERE id=%s AND owner_id=%s FOR UPDATE',(case_id,owner));case=cur.fetchone()
            if not case:raise HTTPException(404,'Review case not found.')
            if case['status']!='needs_information' or case['version']!=version:raise HTTPException(409,'This case changed. Reload before responding.')
            cur.execute('''SELECT id FROM analysis_sessions s WHERE id=%s AND user_id=%s AND farm_id IS NOT DISTINCT FROM %s
                AND s.analyzed_at>(SELECT analyzed_at FROM analysis_sessions WHERE id=%s)
                AND verification_status='draft' AND NOT EXISTS(SELECT 1 FROM review_case_revisions r WHERE r.session_id=s.id) FOR UPDATE''',(session_id,owner,case['farm_id'],case['current_session_id']))
            if not cur.fetchone():raise HTTPException(409,'Choose a new, unsubmitted analysis of this same farm.')
            cur.execute('''UPDATE analysis_sessions SET verification_status='pending',submitted_at=NOW() WHERE id=%s''',(session_id,))
            cur.execute('SELECT COALESCE(MAX(revision),0)+1 AS next FROM review_case_revisions WHERE case_id=%s',(case_id,));revision=cur.fetchone()['next']
            cur.execute('INSERT INTO review_case_revisions VALUES(%s,%s,%s)',(case_id,session_id,revision))
            cur.execute("UPDATE review_cases SET current_session_id=%s,status='pending',version=version+1,submitted_at=NOW(),updated_at=NOW() WHERE id=%s RETURNING *",(session_id,case_id));case=cur.fetchone()
            event(cur,case,owner,'resubmitted',notes)
    return detail(case_id,owner)


def add_note(case_id,actor,notes):
    if not notes.strip() or len(notes)>500:raise HTTPException(422,'Add a note of at most 500 characters.')
    with closing(db.get_conn()) as conn,conn:
        with conn.cursor() as cur:
            cur.execute('SELECT * FROM review_cases WHERE id=%s FOR UPDATE',(case_id,));case=cur.fetchone()
            if not case:raise HTTPException(404,'Review case not found.')
            event(cur,case,actor,'advisory_note',notes.strip())
    return detail(case_id)


def followup(case_id,actor,title,due_on,followup_id=None):
    with closing(db.get_conn()) as conn,conn:
        with conn.cursor() as cur:
            cur.execute('SELECT * FROM review_cases WHERE id=%s FOR UPDATE',(case_id,));case=cur.fetchone()
            if not case:raise HTTPException(404,'Review case not found.')
            if followup_id is None:
                cur.execute('INSERT INTO review_followups(case_id,created_by,assigned_to,title,due_on) VALUES(%s,%s,%s,%s,%s)',(case_id,actor,actor,title.strip(),due_on))
                event(cur,case,actor,'followup_created',title.strip())
            else:
                cur.execute('''UPDATE review_followups SET completed_at=NOW() WHERE id=%s AND case_id=%s
                    AND assigned_to=%s AND completed_at IS NULL RETURNING id''',(followup_id,case_id,actor))
                if not cur.fetchone():raise HTTPException(409,'This task changed or is assigned to another analyst.')
                event(cur,case,actor,'followup_completed')
    return detail(case_id)
