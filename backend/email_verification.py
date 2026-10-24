"""Password signup with a one-use email code; delivery is never simulated in production."""
import hashlib
import hmac
import os
import secrets
from mail_delivery import smtplib as smtplib
from contextlib import closing

from fastapi import HTTPException
import database


def enabled():
    from auth_security import production_mode
    return os.getenv('EMAIL_VERIFICATION_REQUIRED', '1' if production_mode() else '0') == '1'


def migrate(cur):
    cur.execute('''CREATE TABLE IF NOT EXISTS email_signup_challenges (
        ticket_hash CHAR(64) PRIMARY KEY, email VARCHAR(100) NOT NULL,
        username VARCHAR(50) NOT NULL, password_hash VARCHAR(255) NOT NULL,
        code_hash CHAR(64) NOT NULL, attempts INTEGER NOT NULL DEFAULT 0,
        expires_at TIMESTAMPTZ NOT NULL DEFAULT NOW()+INTERVAL '10 minutes',
        sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), used_at TIMESTAMPTZ)''')
    cur.execute('CREATE INDEX IF NOT EXISTS idx_email_signup_sent ON email_signup_challenges(email,sent_at)')


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


def code_digest(ticket, code, secret):
    return hmac.new(secret.encode(), (ticket + ':' + code).encode(), hashlib.sha256).hexdigest()


def deliver(email, code):
    from mail_delivery import send
    send(email, 'Verify your GeoSustain email',
         f'Your GeoSustain verification code is {code}.\n'
         'It expires in 10 minutes. Do not share this code.\n'
         'If you did not request an account, ignore this email.',
         idempotency_key='signup-' + digest(email + ':' + code))


def start(username, email, password_hash, secret):
    ticket, code = secrets.token_urlsafe(32), f'{secrets.randbelow(1000000):06d}'
    with closing(database.get_conn()) as conn, conn:
        with conn.cursor() as cur:
            cur.execute('SELECT pg_advisory_xact_lock(hashtextextended(%s,0))', ('email-signup:' + email,))
            cur.execute("DELETE FROM email_signup_challenges WHERE expires_at<NOW()-INTERVAL '1 day'")
            cur.execute("SELECT COUNT(*) AS n FROM email_signup_challenges WHERE email=%s AND sent_at>NOW()-INTERVAL '5 minutes'", (email,))
            if cur.fetchone()['n'] >= 3:
                raise HTTPException(429, 'Too many verification emails. Wait five minutes before retrying.')
            cur.execute('SELECT id FROM users WHERE LOWER(BTRIM(email))=%s', (email,))
            if cur.fetchone():
                raise HTTPException(409, 'Email is already registered. Please log in.')
            cur.execute('''INSERT INTO email_signup_challenges(ticket_hash,email,username,password_hash,code_hash)
                VALUES (%s,%s,%s,%s,%s)''', (digest(ticket), email, username, password_hash, code_digest(ticket, code, secret)))
            deliver(email, code)
    return {'requires_verification': True, 'verification_ticket': ticket, 'email': email,
            'message': 'Enter the code sent to your email. Your account is created after verification.'}


def resend(ticket, secret):
    code = f'{secrets.randbelow(1000000):06d}'
    with closing(database.get_conn()) as conn, conn:
        with conn.cursor() as cur:
            cur.execute('''SELECT *,sent_at>NOW()-INTERVAL '60 seconds' AS cooldown
                FROM email_signup_challenges WHERE ticket_hash=%s AND used_at IS NULL
                AND expires_at>NOW() FOR UPDATE''', (digest(ticket),))
            row = cur.fetchone()
            if not row:
                raise HTTPException(400, 'Verification expired. Please register again.')
            if row['cooldown']:
                raise HTTPException(429, 'Wait one minute before requesting another code.')
            # Resending must not reset the five-attempt budget or extend expiry.
            if row['attempts'] >= 5:
                raise HTTPException(429, 'Too many incorrect codes. Please register again.')
            cur.execute("SELECT COUNT(*) AS n FROM email_signup_challenges WHERE email=%s AND sent_at>NOW()-INTERVAL '5 minutes'", (row['email'],))
            if cur.fetchone()['n'] >= 3:
                raise HTTPException(429, 'Too many verification emails. Please wait before retrying.')
            cur.execute('UPDATE email_signup_challenges SET code_hash=%s,sent_at=NOW() WHERE ticket_hash=%s', (code_digest(ticket, code, secret), digest(ticket)))
            deliver(row['email'], code)
    return {'message': 'A new code was sent. The previous code no longer works.'}


def verify(ticket, code, secret):
    error = None
    with closing(database.get_conn()) as conn, conn:
        with conn.cursor() as cur:
            cur.execute('''SELECT * FROM email_signup_challenges WHERE ticket_hash=%s
                AND used_at IS NULL AND expires_at>NOW() FOR UPDATE''', (digest(ticket),))
            row = cur.fetchone()
            if not row or row['attempts'] >= 5:
                error = 'Verification expired or locked. Please register again.'
            elif not hmac.compare_digest(row['code_hash'], code_digest(ticket, code, secret)):
                cur.execute('UPDATE email_signup_challenges SET attempts=attempts+1 WHERE ticket_hash=%s', (digest(ticket),))
                error = 'Incorrect verification code. Check your email and try again.'
            else:
                # Same lock convention as create_user prevents account replacement races.
                cur.execute('SELECT pg_advisory_xact_lock(hashtextextended(%s,0))', ('register:' + row['email'],))
                cur.execute('''INSERT INTO users(username,email,password_hash,role,email_verified,auth_provider)
                    VALUES (%s,%s,%s,'farmer',TRUE,'email') ON CONFLICT (email) DO NOTHING
                    RETURNING id''', (row['username'], row['email'], row['password_hash']))
                created = cur.fetchone()
                cur.execute('UPDATE email_signup_challenges SET used_at=NOW(),password_hash=%s WHERE ticket_hash=%s', ('consumed', digest(ticket)))
                if not created:
                    error = 'Email is already registered. Please log in.'
    if error:
        raise HTTPException(400, error)
    # Email ownership is not a login session. Require the user's password next.
    return {'message': 'Email verified. Sign in with your email and password.', 'verified': True}
