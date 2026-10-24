"""Synthetic SQL integration, restricted to the verified local QA cluster.

Provider proofs/mail/FCM are doubles; PostgreSQL transactions are real.
Never prints challenges, tokens, addresses or provider payloads.
"""
import re
import time
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from unittest.mock import patch, Mock
from defense_integration import isolated, db, api, TestClient
import password_reset as reset
import federated_identity as identity
import activity_notifications as activity
import push_delivery as push
from fastapi import HTTPException


def denied(operation, status):
    try:
        operation()
    except HTTPException as exc:
        assert exc.status_code == status, exc.status_code
    else:
        raise AssertionError('Expected rejection')


def run():
    with isolated() as connect:
        hashed=api.hash_password('SyntheticOnly!2026')
        user=db.create_user('Identity fixture','identity@example.com',hashed)
        other=db.create_user('Foreign fixture','foreign@example.com',hashed)
        user=db.get_user_by_id(user['id'])
        other=db.get_user_by_id(other['id'])
        uid=user['id']
        captured=[]
        def mail(_recipient,_subject,body,**_kwargs):
            captured.append(body)
        def challenge():
            answer=reset.start(user['email'],'synthetic-test-secret')
            return answer['verification_ticket'],re.search(r'code is (\d{6})',captured[-1])[1]
        with patch.object(reset.mail_delivery,'configured',return_value=True),patch.object(reset.mail_delivery,'send',side_effect=mail):
            ticket,code=challenge()
            unknown=reset.start('missing@example.com','synthetic-test-secret')
            assert set(unknown)=={'verification_ticket','message'}
            for _ in range(5):
                denied(lambda:reset.complete(ticket,'000000' if code!='000000' else '111111',hashed,'synthetic-test-secret'),400)
            denied(lambda:reset.complete(ticket,code,hashed,'synthetic-test-secret'),400)
            with connect() as conn,conn.cursor() as cur:
                cur.execute('SELECT attempts FROM password_reset_challenges WHERE user_id=%s',(uid,))
                assert cur.fetchone()['attempts']==5
            ticket,code=challenge()
            with connect() as conn,conn.cursor() as cur:
                cur.execute("UPDATE password_reset_challenges SET expires_at=NOW()-INTERVAL '1 second' WHERE user_id=%s",(uid,))
            denied(lambda:reset.complete(ticket,code,hashed,'synthetic-test-secret'),400)
            ticket,code=challenge()
            old_token=api.generate_mobile_token(user)
            push.register(uid,'synthetic-session',user['password_version'],'synthetic-device','android',True)
            changed=api.hash_password('ChangedSynthetic!2026')
            assert 'Password changed' in reset.complete(ticket,code,changed,'synthetic-test-secret')['message']
            denied(lambda:reset.complete(ticket,code,hashed,'synthetic-test-secret'),400)
            current=db.get_user_by_id(uid)
            assert current['password_version']==user['password_version']+1
            with connect() as conn,conn.cursor() as cur:
                cur.execute('SELECT COUNT(*) AS n FROM push_subscriptions WHERE user_id=%s',(uid,))
                assert cur.fetchone()['n']==0
            with TestClient(api.app) as client:
                assert client.get('/api/mobile/me',headers={'Authorization':'Bearer '+old_token}).status_code==401
        print('PASS reset: generic response, five-guess durable lock, expiry, one-use success, password version and old-session/push revocation')

        with patch.dict('os.environ',{'FIREBASE_AUTH_PROJECT_ID':'synthetic-project'}):
            proof={'sub':'synthetic-google-sub','email':current['email'],'email_verified':True,'auth_time':time.time()}
            with patch.object(identity,'google_identity',return_value=(proof,current['email'])):
                linked=identity.link_google(current,'synthetic-proof','ChangedSynthetic!2026')
                assert linked['google_sub']==proof['sub'] and linked['role']=='farmer'
                assert identity.google_login('synthetic-proof')['id']==uid
            ticket=identity.start_phone(linked,'+639171234567')['ticket']
            claims={'phone_number':'+639171234567','auth_time':time.time()}
            with patch.object(identity,'verify_proof',return_value=claims):
                denied(lambda:identity.finish_phone(other,ticket,'synthetic-proof'),400)
                verified=identity.finish_phone(linked,ticket,'synthetic-proof')
                assert verified['phone_verified_at'] is not None
                denied(lambda:identity.finish_phone(linked,ticket,'synthetic-proof'),400)
            # Saving a changed number cannot carry the old verified flag.
            db.update_user_profile(uid,phone_number='+639171234568')
            assert db.get_user_by_id(uid)['phone_verified_at'] is None
            stale=identity.start_phone(db.get_user_by_id(uid),'+639171234568')['ticket']
            with connect() as conn,conn.cursor() as cur:
                cur.execute('UPDATE users SET password_version=password_version+1 WHERE id=%s',(uid,))
            with patch.object(identity,'verify_proof',return_value={'phone_number':'+639171234568','auth_time':time.time()}):
                denied(lambda:identity.finish_phone(verified,stale,'synthetic-proof'),400)
        print('PASS identity: explicit Google link persists without privilege gain; phone ownership/replay/number-change/password-version rules enforced by SQL')

        current=db.get_user_by_id(uid)
        push.register(uid,'new-synthetic-session',current['password_version'],'synthetic-device','android',True)
        with connect() as conn,conn.cursor() as cur:
            cur.execute('INSERT INTO analysis_sessions(user_id,center_lat,center_lon) VALUES(%s,7.29,125.62) RETURNING id',(uid,))
            sid=cur.fetchone()['id']
            activity.analysis_saved(cur,uid,sid,True)
            activity.analysis_saved(cur,uid,sid,True)
            cur.execute('SELECT COUNT(*) AS n FROM activity_push_deliveries')
            assert cur.fetchone()['n']==1
        event=activity.inbox(uid)['notifications'][0]
        assert activity.mark_read(other['id'],event['id']) is None
        response=Mock(status_code=503)
        http=Mock();http.post.return_value=response
        with patch.dict('os.environ',{'FCM_PROJECT_ID':'synthetic-project','PUBLIC_WEB_APP_URL':'https://example.com'}):
            assert push.deliver_activity_batch(http)==1
            with connect() as conn,conn.cursor() as cur:
                cur.execute('SELECT attempts,accepted_at,last_error FROM activity_push_deliveries')
                row=cur.fetchone();assert row['attempts']==1 and row['accepted_at'] is None and row['last_error']=='provider_delivery_failed'
                cur.execute('UPDATE activity_push_deliveries SET next_attempt_at=NOW()')
            http.post.return_value=Mock(status_code=200)
            assert push.deliver_activity_batch(http)==1
            assert push.deliver_activity_batch(http)==0
            payload=http.post.call_args.kwargs['json']['message']
            assert payload['data']['event_type']=='analysis_partial'
            assert 'phone_number' not in str(payload) and 'farm_name' not in str(payload)
            assert activity.inbox(uid)['unread_count']==1 # push acceptance is not inbox read
        db.delete_user(uid)
        with connect() as conn,conn.cursor() as cur:
            for table in ['phone_verification_challenges','password_reset_challenges','activity_push_deliveries']:
                cur.execute('SELECT COUNT(*) AS n FROM '+table)
                assert cur.fetchone()['n']==0
        print('PASS activity outbox: deduplication, owner-only reads, bounded retry, provider acceptance distinct from read; account deletion cascades new private records')


if __name__=='__main__':
    run()
