"""Firebase proof exchange, explicit account linking and owner-bound phone checks."""
from contextlib import closing
import hashlib
import os
import re
import secrets
import time

from fastapi import HTTPException
from google.auth.transport.requests import Request
from google.oauth2 import id_token
import psycopg2
import database as db


def project_id():
    return os.getenv('FIREBASE_AUTH_PROJECT_ID', '')


class BoundedRequest(Request):
    def __call__(self, *args, **kwargs):
        kwargs['timeout'] = 10
        return super().__call__(*args, **kwargs)


def verify_proof(token, provider):
    project = project_id()
    if not project:
        raise HTTPException(503, 'Identity verification is temporarily unavailable. Please use your email and password.')
    try:
        claims = id_token.verify_firebase_token(token, BoundedRequest(), audience=project)
        now = time.time()
        if (claims.get('iss') != 'https://securetoken.google.com/' + project
                or claims.get('aud') != project
                or not isinstance(claims.get('sub'), str) or not 1 <= len(claims['sub']) <= 128
                or not isinstance(claims.get('firebase'), dict)
                or claims['firebase'].get('sign_in_provider') != provider
                or not isinstance(claims.get('auth_time'), (int, float))
                or claims['auth_time'] > now + 30 or now - claims['auth_time'] > 300):
            raise ValueError('Invalid or stale identity proof')
        return claims
    except HTTPException:
        raise
    except ValueError:
        raise HTTPException(401, 'Identity proof is invalid or expired. Sign in with the provider again.') from None
    except Exception:
        raise HTTPException(503, 'Identity verification is temporarily unavailable. Please try again.') from None


def google_identity(token):
    from email_validator import validate_email, EmailNotValidError
    claims = verify_proof(token, 'google.com')
    try:
        if claims.get('email_verified') is not True:
            raise ValueError('Unverified provider email')
        email = validate_email(claims.get('email', ''), check_deliverability=False).normalized.lower()
        if len(email) > 100:
            raise ValueError('Email exceeds account storage limit')
    except (ValueError, EmailNotValidError):
        raise HTTPException(401, 'A verified Google email is required.') from None
    return claims, email


def google_login(token):
    import bcrypt
    claims, email = google_identity(token)
    user = db.get_user_by_google_sub(claims['sub'])
    if user:
        if not user.get('is_active', True):
            raise HTTPException(403, 'This account is deactivated.')
        return user
    # Do not seize an existing password account based on an email claim.
    if db.get_user_by_email(email):
        raise HTTPException(409, 'Sign in with your existing password, then link Google from your profile.')
    name = str(claims.get('name') or 'Google Farmer').strip()[:50]
    if len(name) < 3:
        name = 'Google Farmer'
    password_hash = bcrypt.hashpw(secrets.token_urlsafe(32).encode(), bcrypt.gensalt()).decode()
    user = db.create_user(name, email, password_hash,
        role='farmer', email_verified=True, auth_provider='google', google_sub=claims['sub'])
    if not user:
        raise HTTPException(409, 'An account already exists. Sign in and link Google from your profile.')
    return user


def link_google(user, token, current_password):
    from password_auth import verify_password
    claims, email = google_identity(token)
    if email != user['email'].strip().lower():
        raise HTTPException(400, 'Use the Google account with the same verified email as this profile.')
    if user.get('google_sub') == claims['sub']:
        return user
    if user.get('google_sub') or not verify_password(current_password, user.get('password_hash') or ''):
        raise HTTPException(401, 'Confirm your current account password before linking Google.')
    # Conditional update and unique subject prevent concurrent identity replacement.
    try:
        with closing(db.get_conn()) as conn, conn:
            with conn.cursor() as cur:
                cur.execute('''UPDATE users SET google_sub=%s,auth_provider='google',
                    email_verified=TRUE,updated_at=NOW() WHERE id=%s AND google_sub IS NULL
                    AND password_version=%s AND is_active=TRUE RETURNING *''',
                    (claims['sub'], user['id'], user.get('password_version', 0)))
                updated = cur.fetchone()
                if not updated:
                    raise HTTPException(409, 'Account access changed. Sign in again before linking.')
                db.audit_in_transaction(cur, user['id'], user['role'], 'google_link', 'user', user['id'])
                return dict(updated)
    except psycopg2.errors.UniqueViolation:
        raise HTTPException(409, 'This Google identity is linked to another account.') from None


def normalize_phone(value):
    value = value.strip()
    if not re.fullmatch(r'\+[1-9][0-9]{7,14}', value):
        raise ValueError('Use international format, for example +639171234567.')
    return value


def migrate(cur):
    cur.execute('ALTER TABLE users ADD COLUMN IF NOT EXISTS phone_number VARCHAR(16)')
    cur.execute('ALTER TABLE users ADD COLUMN IF NOT EXISTS phone_verified_at TIMESTAMPTZ')
    cur.execute('''CREATE UNIQUE INDEX IF NOT EXISTS idx_verified_phone ON users(phone_number)
        WHERE phone_verified_at IS NOT NULL''')
    cur.execute('''CREATE TABLE IF NOT EXISTS phone_verification_challenges (
        ticket_hash CHAR(64) PRIMARY KEY,user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        phone_number VARCHAR(16) NOT NULL,password_version INTEGER NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),expires_at TIMESTAMPTZ NOT NULL DEFAULT NOW()+INTERVAL '10 minutes',
        used_at TIMESTAMPTZ)''')
    cur.execute('CREATE INDEX IF NOT EXISTS idx_phone_challenge_owner ON phone_verification_challenges(user_id)')


def start_phone(user, phone):
    if not project_id():
        raise HTTPException(503, 'Phone verification is temporarily unavailable.')
    from qa_closure import enforce_quota
    enforce_quota(user['id'], 'phone_verification', 3)
    phone = normalize_phone(phone)
    ticket = secrets.token_urlsafe(32)
    with closing(db.get_conn()) as conn, conn:
        with conn.cursor() as cur:
            cur.execute('''UPDATE users SET phone_verified_at=CASE WHEN phone_number=%s THEN phone_verified_at ELSE NULL END,
                phone_number=%s,updated_at=NOW() WHERE id=%s AND is_active=TRUE AND password_version=%s RETURNING id''',
                (phone, phone, user['id'], user.get('password_version', 0)))
            if not cur.fetchone():
                raise HTTPException(401, 'Sign in again before verifying your phone.')
            cur.execute('DELETE FROM phone_verification_challenges WHERE user_id=%s OR expires_at<NOW()', (user['id'],))
            cur.execute('''INSERT INTO phone_verification_challenges(ticket_hash,user_id,phone_number,password_version)
                VALUES(%s,%s,%s,%s)''', (hashlib.sha256(ticket.encode()).hexdigest(), user['id'], phone, user.get('password_version', 0)))
    return {'ticket': ticket, 'phone_number': phone, 'expires_in': 600}


def finish_phone(user, ticket, token):
    claims = verify_proof(token, 'phone')
    try:
        phone = normalize_phone(claims.get('phone_number', ''))
    except (ValueError, AttributeError):
        raise HTTPException(401, 'A verified phone identity is required.') from None
    try:
        with closing(db.get_conn()) as conn, conn:
            with conn.cursor() as cur:
                cur.execute('''SELECT c.*,EXTRACT(EPOCH FROM c.created_at) AS started_epoch
                    FROM phone_verification_challenges c JOIN users u ON u.id=c.user_id
                    WHERE c.ticket_hash=%s AND c.user_id=%s AND c.used_at IS NULL AND c.expires_at>NOW()
                    AND c.phone_number=u.phone_number AND c.password_version=u.password_version AND u.is_active=TRUE
                    FOR UPDATE OF c,u''', (hashlib.sha256(ticket.encode()).hexdigest(), user['id']))
                challenge = cur.fetchone()
                if (not challenge or challenge['phone_number'] != phone
                        or challenge['password_version'] != user.get('password_version', 0)
                        or claims['auth_time'] < float(challenge['started_epoch']) - 5):
                    raise HTTPException(400, 'Phone verification expired or does not match this account and number. Start again.')
                cur.execute('UPDATE users SET phone_verified_at=NOW(),updated_at=NOW() WHERE id=%s RETURNING *', (user['id'],))
                updated = dict(cur.fetchone())
                cur.execute('UPDATE phone_verification_challenges SET used_at=NOW() WHERE ticket_hash=%s',
                    (hashlib.sha256(ticket.encode()).hexdigest(),))
                db.audit_in_transaction(cur, user['id'], user['role'], 'phone_verified', 'user', user['id'])
                return updated
    except psycopg2.errors.UniqueViolation:
        raise HTTPException(409, 'This phone number is already verified on another account.') from None
