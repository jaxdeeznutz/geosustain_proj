"""Back up the configured database before applying additive defense migrations.

Trusted operator command. It never prints the database URL or password.
Use a separate staging database and rehearse restore before production rollout.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
from datetime import datetime, timezone

from psycopg2.extensions import parse_dsn
import database as db


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--backup', required=True, type=Path)
    parser.add_argument('--pg-dump', default=shutil.which('pg_dump'))
    args=parser.parse_args()
    if not args.pg_dump:
        raise ValueError('Provide --pg-dump pointing to the PostgreSQL pg_dump executable.')
    if args.backup.exists():
        raise ValueError('Backup path already exists. Choose a new dated path; backups are never overwritten.')
    target=parse_dsn(db.DATABASE_URL)
    print(f"Target: host={target.get('host')} database={target.get('dbname')}")
    env=os.environ.copy()
    for key,value in target.items():
        env['PG'+key.upper()]=str(value)
    # libpq uses PGDATABASE rather than PGDBNAME.
    env['PGDATABASE']=target['dbname']
    args.backup.parent.mkdir(parents=True,exist_ok=True)
    subprocess.run([args.pg_dump,'--format=custom','--no-owner','--no-acl','--file',str(args.backup)],env=env,check=True)
    if args.backup.stat().st_size==0:
        raise RuntimeError('Empty backup. No migration was applied.')
    digest=hashlib.sha256(args.backup.read_bytes()).hexdigest()
    print('Backup completed. Applying additive schema migration.')
    db.init_db()
    receipt={'completed_at':datetime.now(timezone.utc).isoformat(),'backup':str(args.backup),
             'backup_sha256':digest,'backup_bytes':args.backup.stat().st_size,
             'host':target.get('host'),'database':target.get('dbname'),
             'migration':'database.init_db defense additive schema'}
    args.backup.with_suffix(args.backup.suffix+'.receipt.json').write_text(json.dumps(receipt,indent=2),encoding='utf-8')
    print('Migration completed. Keep the backup and receipt private.')


if __name__=='__main__':
    main()
