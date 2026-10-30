"""Isolated administrator lab with existing actual model and synthetic observations."""
from contextlib import contextmanager
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import phase05_manual_host as previous

api, db, TestClient = previous.api, previous.db, previous.TestClient
ADMIN = 'phase6-admin@example.com'
PASSWORD = previous.base.PASSWORD


@contextmanager
def workspace():
    with previous.workspace() as (farmer, analyst, farm):
        admin = db.create_user('Phase 6 Test Administrator', ADMIN, api.hash_password(PASSWORD), role='super_admin', email_verified=True)
        yield farmer, analyst, farm, admin


def main():
    import uvicorn
    with workspace():
        print('PHASE 6 LOCAL ADMINISTRATION LAB - SYNTHETIC WORKFLOW - NOT PRODUCTION', flush=True)
        print('Backend http://127.0.0.1:18001 | Web http://localhost:18002')
        print('Admin:', ADMIN, '| Farmer:', previous.base.FARMER, '| Analyst:', previous.base.ANALYST)
        print('Disposable password:', PASSWORD)
        print('Use Crop & Season Settings > Controlled reference records. New records start inactive; review and activate explicitly.')
        print('Use Phase 5 Explainable AI Test Farm for new analysis consumer checks. External backend HTTP, email and push are disabled.')
        print('Ctrl+C removes only the temporary lab schema.', flush=True)
        uvicorn.run(api.app, host='127.0.0.1', port=18001, log_level='warning')


if __name__ == '__main__': main()
