"""One-use emailed recovery codes; never returns a login or reveals an account."""
from contextlib import closing
import hashlib
import hmac
import logging
import secrets
from fastapi import HTTPException
import database as db
from email_verification import code_digest, digest
import mail_delivery


def migrate(cur):
    cur.execute('''CREATE TABLE IF NOT EXISTS password_reset_challenges (
        ticket_hash CHAR(64) PRIMARY KEY,user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        code_hash CHAR(64) NOT NULL,password_version INTEGER NOT NULL,attempts INTEGER NOT NULL DEFAULT 0,
        expires_at TIMESTAMPTZ NOT NULL DEFAULT NOW()+INTERVAL '10 minutes',used_at TIMESTAMPTZ)''')
    cur.execute('CREATE INDEX IF NOT EXISTS idx_reset_owner ON password_reset_challenges(user_id)')


def start(email, secret):
    if not mail_delivery.configured():
        raise HTTPException(503, 'Account recovery delivery is temporarily unavailable. Please contact your project administrator.')
    email = email.strip().lower()
    from qa_closure import enforce_quota
    enforce_quota(hashlib.sha256(email.encode()).hexdigest(), 'email_password_reset', 3)
    ticket, code = secrets.token_urlsafe(32), f'{secrets.randbelow(1000000):06d}'
    user = db.get_user_by_email(email)
    if user and user.get('is_active', True):
        try:
            with closing(db.get_conn()) as conn, conn:
                with conn.cursor() as cur:
                    cur.execute('SELECT id,password_version FROM users WHERE id=%s AND is_active=TRUE FOR UPDATE', (user['id'],))
                    current = cur.fetchone()
                    if current:
                        cur.execute('DELETE FROM password_reset_challenges WHERE user_id=%s OR expires_at<NOW()', (user['id'],))
                        cur.execute('''INSERT INTO password_reset_challenges(ticket_hash,user_id,code_hash,password_version)
                            VALUES(%s,%s,%s,%s)''', (digest(ticket), user['id'], code_digest(ticket, code, secret), current['password_version']))
                        mail_delivery.send(email, 'Reset your GeoSustain password',
                            f'Your GeoSustain recovery code is {code}. It expires in 10 minutes.\n'
                            'Do not share this code. If you did not request a reset, ignore this email.',
                            idempotency_key='reset-' + digest(ticket))
        except HTTPException:
            # Keep the public response indistinguishable from an unknown account.
            logging.getLogger('uvicorn.error').warning('Password recovery email was not accepted by the configured transport.')
    return {'verification_ticket': ticket,
        'message': 'If this account is active and delivery is available, a recovery code will arrive by email. Check your inbox and spam folder.'}


def complete(ticket, code, password_hash, secret):
    error = None
    email = None
    with closing(db.get_conn()) as conn, conn:
        with conn.cursor() as cur:
            cur.execute('''SELECT c.*,u.email FROM password_reset_challenges c JOIN users u ON u.id=c.user_id
                WHERE c.ticket_hash=%s AND c.used_at IS NULL AND c.expires_at>NOW()
                AND c.password_version=u.password_version AND u.is_active=TRUE FOR UPDATE OF c,u''', (digest(ticket),))
            challenge = cur.fetchone()
            if not challenge or challenge['attempts'] >= 5:
                error = 'Recovery expired or locked. Request a new code.'
            elif not hmac.compare_digest(challenge['code_hash'], code_digest(ticket, code, secret)):
                cur.execute('UPDATE password_reset_challenges SET attempts=attempts+1 WHERE ticket_hash=%s', (digest(ticket),))
                error = 'Incorrect recovery code. Check your email and try again.'
            else:
                cur.execute('''UPDATE users SET password_hash=%s,password_version=password_version+1,
                    email_verified=TRUE,updated_at=NOW() WHERE id=%s''', (password_hash, challenge['user_id']))
                cur.execute('UPDATE password_reset_challenges SET used_at=NOW() WHERE ticket_hash=%s', (digest(ticket),))
                cur.execute('DELETE FROM push_subscriptions WHERE user_id=%s', (challenge['user_id'],))
                db.audit_in_transaction(cur, challenge['user_id'], None, 'email_password_reset', 'user', challenge['user_id'])
                email = challenge['email']
    if error:
        raise HTTPException(400, error)
    try:
        mail_delivery.send(email, 'Your GeoSustain password changed',
            'Your GeoSustain password was reset. Previous app sessions are no longer valid. '
            'If you did not make this change, contact your project administrator immediately.',
            idempotency_key='reset-notice-' + digest(ticket))
    except HTTPException:
        logging.getLogger('uvicorn.error').warning('Password changed; security notice delivery remains unavailable.')
    return {'message': 'Password changed. Sign in with your new password. Previous sessions are no longer valid.'}
