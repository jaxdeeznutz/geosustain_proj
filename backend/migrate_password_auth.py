"""Migrate legacy accounts without printing passwords. Dry-run unless --apply."""
import argparse
import re
import bcrypt
from database import get_conn

BCRYPT = re.compile(r'^\$2[aby]\$\d{2}\$[./A-Za-z0-9]{53}$')


def prepare_password(value, *, confirmed_plaintext=False):
    if BCRYPT.fullmatch(value or ''):
        return value
    if not confirmed_plaintext:
        raise ValueError('Unsupported password format; confirm plaintext explicitly or reset the password.')
    if not value or len(value.encode('utf-8')) > 72:
        raise ValueError('Legacy password is empty or exceeds the bcrypt byte limit; reset it.')
    return bcrypt.hashpw(value.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')


def migrate(conn, plaintext_user_ids=()):
    """Caller commits or rolls back the entire migration."""
    with conn.cursor() as cur:
        cur.execute('LOCK TABLE users, pending_registrations IN SHARE ROW EXCLUSIVE MODE')
        cur.execute('SELECT LOWER(BTRIM(email)) FROM users GROUP BY LOWER(BTRIM(email)) HAVING COUNT(*) > 1')
        if cur.fetchone():
            raise ValueError('Duplicate normalized user emails detected. Resolve duplicates before migrating.')
        cur.execute('SELECT id, password_hash FROM users ORDER BY id')
        rows = cur.fetchall()
        known = {r['id'] for r in rows}
        if set(plaintext_user_ids) - known:
            raise ValueError('A requested plaintext user ID does not exist.')
        unresolved = []
        converted = 0
        for row in rows:
            try:
                encoded = prepare_password(row['password_hash'], confirmed_plaintext=row['id'] in plaintext_user_ids)
            except ValueError:
                unresolved.append(row['id'])
                continue
            cur.execute("UPDATE users SET password_hash=%s, auth_provider='email', updated_at=NOW() WHERE id=%s", (encoded, row['id']))
            converted += 1
        cur.execute('UPDATE users SET email=LOWER(BTRIM(email)), verification_code_hash=NULL, verification_expires_at=NULL')
        # This flag remains historical: disabling verification does not prove email ownership.
        cur.execute('CREATE UNIQUE INDEX IF NOT EXISTS users_email_normalized_unique ON users (LOWER(BTRIM(email)))')
        cur.execute("ALTER TABLE users ALTER COLUMN auth_provider SET DEFAULT 'email'")
        cur.execute('SELECT username,email,password_hash,role FROM pending_registrations ORDER BY created_at')
        pending = cur.fetchall()
        promoted = 0
        for row in pending:
            email = row['email'].strip().lower()
            cur.execute('SELECT id FROM users WHERE LOWER(BTRIM(email))=%s', (email,))
            if cur.fetchone():
                continue  # Never overwrite an existing account with pending signup data.
            if not BCRYPT.fullmatch(row['password_hash'] or ''):
                continue
            role = 'agricultural_planning_analyst' if row['role'] in ('analyst', 'planner', 'agricultural_planning_analyst') else 'farmer'
            cur.execute("INSERT INTO users (username,email,password_hash,role,email_verified,auth_provider) VALUES (%s,%s,%s,%s,FALSE,'email')", (row['username'], email, row['password_hash'], role))
            cur.execute('DELETE FROM pending_registrations WHERE email=%s', (row['email'],))
            promoted += 1
        return {'password_accounts': converted, 'pending_accounts_promoted': promoted, 'user_ids_needing_password_reset': unresolved}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--plaintext-user-ids', type=int, nargs='*', default=[], help='Only IDs whose current stored value you have confirmed is plaintext.')
    args = parser.parse_args()
    conn = get_conn()
    try:
        result = migrate(conn, args.plaintext_user_ids)
        if args.apply:
            conn.commit()
        else:
            conn.rollback()
        print('APPLIED' if args.apply else 'DRY RUN (rolled back)', result)
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == '__main__':
    main()
