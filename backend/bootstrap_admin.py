"""Trusted operator only. No defaults, public route, or command-line password."""
import argparse
import getpass
from urllib.parse import urlsplit

import bcrypt
from email_validator import validate_email

import database as db
from password_auth import validate_new_password


def bootstrap(email, username, password_hash=None, promote_existing=False):
    email = validate_email(email, check_deliverability=False).normalized.lower()
    if not 3 <= len(username.strip()) <= 50:
        raise ValueError('Display name must contain 3–50 characters.')
    conn = db.get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute('SELECT pg_advisory_xact_lock(714262601)')
            cur.execute("SELECT pg_advisory_xact_lock(hashtextextended(%s, 0))", ('register:' + email,))
            cur.execute('SELECT * FROM users WHERE LOWER(BTRIM(email))=%s FOR UPDATE', (email,))
            existing = cur.fetchone()
            if existing and existing['role'] == 'super_admin' and existing['is_active']:
                return {'id': existing['id'], 'status': 'already_admin'}
            cur.execute("SELECT COUNT(*) AS count FROM users WHERE is_active AND role IN ('admin','super_admin')")
            if cur.fetchone()['count']:
                raise ValueError('An active administrator exists. Use its protected user-management workflow.')
            if existing:
                if not promote_existing:
                    raise ValueError('Email already exists; use --promote-existing intentionally. Its password will be preserved.')
                cur.execute("UPDATE users SET role='super_admin', is_active=TRUE, updated_at=NOW() WHERE id=%s RETURNING id", (existing['id'],))
            else:
                if password_hash is None:
                    raise ValueError('A private initial password is required for a new account.')
                cur.execute("""INSERT INTO users (username,email,password_hash,role,email_verified)
                    VALUES (%s,%s,%s,'super_admin',TRUE) RETURNING id""", (username.strip(), email, password_hash))
            user_id = cur.fetchone()['id']
            db.audit_in_transaction(cur, None, 'trusted_operator', 'first_admin_bootstrap', 'user', user_id,
                                    {'promoted_existing': bool(existing)})
        conn.commit()
        return {'id': user_id, 'status': 'promoted' if existing else 'created'}
    finally:
        conn.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--email', required=True)
    parser.add_argument('--name', required=True)
    parser.add_argument('--promote-existing', action='store_true')
    args = parser.parse_args()
    target = urlsplit(db.DATABASE_URL)
    print(f'Target: host={target.hostname} port={target.port or 5432} database={target.path.lstrip("/")}')
    print('Back up this database and run the additive schema migration before bootstrap.')
    existing = db.get_user_by_email(args.email.strip().lower())
    password_hash = None
    if not existing:
        password = validate_new_password(getpass.getpass('Initial password (private): '))
        if password != getpass.getpass('Repeat initial password: '):
            raise ValueError('Passwords do not match.')
        password_hash = bcrypt.hashpw(password.encode(), bcrypt.gensalt(rounds=12)).decode()
    print(bootstrap(args.email, args.name, password_hash, args.promote_existing))


if __name__ == '__main__':
    main()
