"""FCM HTTP v1 delivery from a transactional outbox. Never logs device tokens."""
import json
import os
import threading
import re
from contextlib import closing

import requests
from google.auth.transport.requests import AuthorizedSession
from google.oauth2.service_account import Credentials

import database as db

_started = False


def configured():
    try:
        credentials()
        return True
    except (ValueError, TypeError, KeyError):
        return False


def credentials():
    project=os.getenv('FCM_PROJECT_ID','')
    if not re.fullmatch(r'[a-z][a-z0-9-]{4,28}[a-z0-9]',project):
        raise ValueError('Invalid FCM project configuration')
    info=json.loads(os.getenv('FCM_SERVICE_ACCOUNT_JSON',''))
    if (not isinstance(info,dict) or info.get('type')!='service_account'
            or info.get('token_uri')!='https://oauth2.googleapis.com/token'):
        raise ValueError('Invalid FCM service identity configuration')
    return Credentials.from_service_account_info(info,
        scopes=['https://www.googleapis.com/auth/firebase.messaging'])


def register(user_id, session_id, password_version, token, platform, enabled):
    import hashlib
    conn = db.get_conn()
    try:
        with conn.cursor() as cur:
            if enabled:
                # Registering the same browser/device on another account removes
                # its previous owner's pending deliveries in the same transaction.
                cur.execute('DELETE FROM push_subscriptions WHERE token=%s', (token,))
                cur.execute("""INSERT INTO push_subscriptions
                    (token,user_id,session_hash,password_version,platform)
                    VALUES (%s,%s,%s,%s,%s)""",
                    (token,user_id,hashlib.sha256(session_id.encode()).hexdigest(),password_version,platform))
            else:
                cur.execute('DELETE FROM push_subscriptions WHERE token=%s AND user_id=%s', (token,user_id))
        conn.commit()
    finally:
        conn.close()


def queue_review(cur, session_id):
    cur.execute("""INSERT INTO push_deliveries (token,session_id)
        SELECT p.token,s.id FROM push_subscriptions p
        JOIN analysis_sessions s ON s.user_id=p.user_id
        JOIN users u ON u.id=p.user_id
        WHERE s.id=%s AND u.is_active AND u.password_version=p.password_version
        ON CONFLICT (token,session_id) DO NOTHING""", (session_id,))


def send(token, session_id, http):
    project = os.environ['FCM_PROJECT_ID']
    from urllib.parse import urlsplit
    web_app = os.getenv('PUBLIC_WEB_APP_URL', '').rstrip('/')
    webpush = {'notification': {'tag':f'review-{session_id}'}}
    if web_app and urlsplit(web_app).scheme == 'https' and not urlsplit(web_app).query and not urlsplit(web_app).fragment:
        webpush['fcm_options'] = {'link': f'{web_app}/?review={session_id}'}
    response = http.post(f'https://fcm.googleapis.com/v1/projects/{project}/messages:send',
        json={'message': {'token': token,
            'notification': {'title':'GeoSustain review update',
                'body':'Your land analysis has been reviewed. Open GeoSustain to view the decision.'},
            'data': {'session_id':str(session_id)},
            'android': {'notification': {'tag':f'review-{session_id}'}},
            'webpush': webpush}}, timeout=10)
    if response.status_code == 200:
        return 'sent'
    try:
        detail = response.json().get('error', {})
        codes = [item.get('errorCode') for item in detail.get('details', [])]
    except (ValueError, AttributeError, TypeError):
        codes = []
    if 'UNREGISTERED' in codes:
        return 'unregistered'
    # HTTP 400 can be a project/payload defect; never silently discard those tokens.
    raise requests.RequestException(f'FCM HTTP {response.status_code}')


def send_activity(token, activity, http):
    """Generic notification content; owned details are fetched after app auth."""
    from urllib.parse import urlsplit
    event_id, session_id = int(activity['activity_id']), int(activity['session_id'])
    partial = activity['event_type'] == 'analysis_partial'
    webpush = {'notification': {'tag': f'activity-{event_id}'}}
    origin = os.getenv('PUBLIC_WEB_APP_URL', '').rstrip('/')
    parsed = urlsplit(origin)
    if origin and parsed.scheme == 'https' and parsed.netloc and not parsed.query and not parsed.fragment and not parsed.username:
        webpush['fcm_options'] = {'link': f'{origin}/?review={session_id}'}
    response = http.post(f'https://fcm.googleapis.com/v1/projects/{os.environ["FCM_PROJECT_ID"]}/messages:send',
        json={'message': {'token': token,
            'notification': {'title': 'GeoSustain assessment update',
                'body': 'A partial assessment is available. Check missing observations.' if partial else 'Your analysis is ready to view.'},
            'data': {'session_id': str(session_id), 'event_id': str(event_id), 'event_type': activity['event_type']},
            'android': {'notification': {'tag': f'activity-{event_id}'}}, 'webpush': webpush}}, timeout=10)
    if response.status_code == 200:
        return 'accepted'
    try:
        codes = [entry.get('errorCode') for entry in response.json().get('error', {}).get('details', [])]
    except (ValueError, AttributeError, TypeError):
        codes = []
    if 'UNREGISTERED' in codes:
        return 'unregistered'
    raise requests.RequestException(f'FCM HTTP {response.status_code}')


def deliver_activity_batch(http, limit=20):
    processed = 0
    for _ in range(limit):
        with closing(db.get_conn()) as conn, conn:
            with conn.cursor() as cur:
                cur.execute('''SELECT d.id,d.token,n.id AS activity_id,n.session_id,n.event_type
                    FROM activity_push_deliveries d JOIN activity_notifications n ON n.id=d.activity_id
                    JOIN push_subscriptions p ON p.token=d.token AND p.user_id=n.user_id
                    JOIN users u ON u.id=n.user_id JOIN analysis_sessions s ON s.id=n.session_id AND s.user_id=n.user_id
                    WHERE d.accepted_at IS NULL AND d.attempts<10 AND d.next_attempt_at<=NOW()
                    AND u.is_active=TRUE AND u.password_version=p.password_version
                    ORDER BY d.id FOR UPDATE OF d,p SKIP LOCKED LIMIT 1''')
                row = cur.fetchone()
                if not row:
                    break
                try:
                    result = send_activity(row['token'], row, http)
                    if result == 'unregistered':
                        cur.execute('DELETE FROM push_subscriptions WHERE token=%s', (row['token'],))
                    else:
                        cur.execute('UPDATE activity_push_deliveries SET accepted_at=NOW(),last_error=NULL WHERE id=%s', (row['id'],))
                except requests.RequestException:
                    cur.execute('''UPDATE activity_push_deliveries SET attempts=attempts+1,last_error='provider_delivery_failed',
                        next_attempt_at=NOW()+LEAST(3600,30*POWER(2,attempts))*INTERVAL '1 second' WHERE id=%s''', (row['id'],))
                processed += 1
    return processed


def deliver_batch(http, limit=20):
    processed = 0
    for _ in range(limit):
        conn = db.get_conn()
        try:
            with conn.cursor() as cur:
                cur.execute("""SELECT d.id,d.token,d.session_id FROM push_deliveries d
                    JOIN push_subscriptions p ON p.token=d.token
                    JOIN users u ON u.id=p.user_id
                    WHERE d.sent_at IS NULL AND d.attempts<10 AND d.next_attempt_at<=NOW()
                    AND u.is_active AND u.password_version=p.password_version
                    ORDER BY d.id FOR UPDATE OF d,p SKIP LOCKED LIMIT 1""")
                row = cur.fetchone()
                if not row:
                    break
                try:
                    outcome = send(row['token'], row['session_id'], http)
                    if outcome == 'unregistered':
                        cur.execute('DELETE FROM push_subscriptions WHERE token=%s', (row['token'],))
                    else:
                        cur.execute('UPDATE push_deliveries SET sent_at=NOW(), last_error=NULL WHERE id=%s', (row['id'],))
                except requests.RequestException:
                    cur.execute("""UPDATE push_deliveries SET attempts=attempts+1,
                        last_error='provider_delivery_failed',
                        next_attempt_at=NOW()+LEAST(3600,30*POWER(2,attempts)) * INTERVAL '1 second'
                        WHERE id=%s""", (row['id'],))
                processed += 1
            conn.commit()
        finally:
            conn.close()
    return processed


def start_worker():
    global _started
    if _started or not configured():
        return
    _started = True

    def run():
        import logging
        stop = threading.Event()
        while not stop.wait(30):
            try:
                with AuthorizedSession(credentials()) as http:
                    deliver_batch(http)
                    deliver_activity_batch(http)
            except Exception:
                logging.getLogger('uvicorn.error').warning('Push worker retry pending; check provider/database configuration.')
    threading.Thread(target=run, name='geosustain-push-outbox', daemon=True).start()
