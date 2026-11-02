"""One-time Google password setup: real signed app tokens, isolated persistence."""
from copy import deepcopy
import time
from unittest.mock import Mock

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from itsdangerous import TimestampSigner
from starlette.requests import Request
import fastapi_app as api
import federated_identity as identity
from password_auth import verify_password

PASSWORD = 'FixturePass!234'


def pending(**changes):
    return dict(dict(id=81, username='Fixture Farmer', email='fixture@example.com',
        role='farmer', is_active=True, email_verified=True, google_sub='fixture-google-sub',
        auth_provider='google', password_version=0, password_setup_required=True,
        password_hash='unusable-fixture-only'), **changes)


@pytest.fixture
def auth(monkeypatch):
    user = pending()
    sessions = []
    monkeypatch.setattr(api, 'init_db', lambda: None)
    monkeypatch.setattr(api, 'get_user_by_id', lambda uid: dict(user) if uid == user['id'] else None)
    monkeypatch.setattr(api, 'get_user_by_email', lambda email: dict(user) if email.strip().lower() == user['email'] else None)
    monkeypatch.setattr(api.defense_db, 'start_session', lambda uid, sid, ttl: sessions.append((uid, sid, ttl)))
    monkeypatch.setattr(api.defense_db, 'session_revoked', lambda sid: False)
    monkeypatch.setattr(api.defense_db, 'revoke_session', lambda *args: None)
    previous = dict(api.app.dependency_overrides)
    api.app.dependency_overrides.clear()
    try:
        with TestClient(api.app) as client:
            yield client, user, sessions
    finally:
        api.app.dependency_overrides.clear()
        api.app.dependency_overrides.update(previous)


def headers(user):
    return {'Authorization': 'Bearer ' + api.generate_mobile_token(user)}


def test_google_exchange_issues_only_setup_session(auth, monkeypatch):
    client, user, sessions = auth
    monkeypatch.setattr(identity, 'google_login', lambda proof: dict(user))
    response = client.post('/api/mobile/auth/google', json={'id_token': 'synthetic-identity-proof-' * 3})
    assert response.status_code == 200
    data = response.json()
    assert data['user']['id'] == user['id']
    assert data['user']['password_setup_required'] is True
    assert data['user']['google_linked'] is True
    assert data['user']['role'] == 'farmer'
    assert 'password_hash' not in data['user'] and 'google_sub' not in data['user']
    assert api.token_serializer.loads(data['token'], salt='geosustain-mobile')['scope'] == 'password_setup'
    assert sessions[-1][2] == 900


def test_pending_session_can_restore_profile_and_sign_out(auth):
    client, user, _ = auth
    auth_headers = headers(user)
    assert client.get('/api/mobile/me', headers=auth_headers).json()['user']['password_setup_required'] is True
    assert client.post('/api/mobile/logout', headers=auth_headers).status_code == 200


@pytest.mark.parametrize('path', ['/api/mobile/farms', '/api/mobile/history', '/api/mobile/activity',
    '/api/mobile/notifications', '/api/admin/users'])
def test_setup_session_cannot_open_workspace_routes(auth, path):
    client, user, _ = auth
    result = client.get(path, headers=headers(user))
    assert result.status_code == 403
    assert 'password' in result.json()['detail'].lower()


def test_pending_session_cannot_link_or_request_phone_code(auth):
    client, user, _ = auth
    auth_headers = headers(user)
    response = client.post('/api/mobile/auth/link-google', headers=auth_headers,
        json={'id_token': 'synthetic-proof-' * 4, 'current_password': PASSWORD})
    assert response.status_code == 403
    response = client.post('/api/mobile/phone-verification/start', headers=auth_headers,
        json={'phone_number': '+639999999999'})
    assert response.status_code == 403


def test_setup_session_expires_in_fifteen_minutes(auth, monkeypatch):
    client, user, _ = auth
    with monkeypatch.context() as clock:
        clock.setattr(TimestampSigner, 'get_timestamp', lambda self: int(time.time()) - 901)
        token = api.generate_mobile_token(user)
    assert client.get('/api/mobile/me', headers={'Authorization': 'Bearer ' + token}).status_code == 401


@pytest.mark.parametrize('scope', [None, 'workspace'])
def test_pending_account_rejects_other_token_purposes(auth, scope):
    client, user, _ = auth
    payload = {'id': user['id'], 'sid': 'fixture', 'password_version': 0}
    if scope is not None:
        payload['scope'] = scope
    token = api.token_serializer.dumps(payload, salt='geosustain-mobile')
    assert client.get('/api/mobile/me', headers={'Authorization': 'Bearer ' + token}).status_code == 401


def test_setup_needs_authenticated_owner_and_ignores_no_identifiers(auth, monkeypatch):
    client, user, _ = auth
    save = Mock()
    monkeypatch.setattr(identity, 'setup_google_password', save)
    assert client.post('/api/mobile/auth/password-setup', json={'new_password': PASSWORD}).status_code == 401
    for extra in [{'id': 99}, {'role': 'super_admin'}, {'email': 'other@example.com'}, {'password_setup_required': False}]:
        result = client.post('/api/mobile/auth/password-setup', headers=headers(user), json={'new_password': PASSWORD, **extra})
        assert result.status_code == 422
        assert PASSWORD not in result.text
    save.assert_not_called()


@pytest.mark.parametrize('password', ['short!', 'nosymbolpassword', 'contains spaces!', 'x' * 73 + '!'])
def test_setup_reuses_password_policy_without_echoing_password(auth, monkeypatch, password):
    client, user, _ = auth
    save = Mock()
    monkeypatch.setattr(identity, 'setup_google_password', save)
    result = client.post('/api/mobile/auth/password-setup', headers=headers(user), json={'new_password': password})
    assert result.status_code == 422
    assert password not in result.text
    save.assert_not_called()


def test_same_account_can_use_password_and_google_after_setup(auth, monkeypatch):
    client, user, sessions = auth
    before = deepcopy(user)
    old_headers = headers(user)
    def save(actor, password_hash):
        assert actor['id'] == user['id']
        assert password_hash != PASSWORD and verify_password(PASSWORD, password_hash)
        user.update(password_hash=password_hash, password_setup_required=False, password_version=1)
        return dict(user)
    saved = Mock(side_effect=save)
    monkeypatch.setattr(identity, 'setup_google_password', saved)
    result = client.post('/api/mobile/auth/password-setup', headers=old_headers, json={'new_password': PASSWORD})
    assert result.status_code == 200
    data = result.json()
    assert data['user']['password_setup_required'] is False
    for key in ['id', 'email', 'role', 'google_sub', 'auth_provider']:
        assert user[key] == before[key]
    assert 'scope' not in api.token_serializer.loads(data['token'], salt='geosustain-mobile')
    assert sessions[-1][2] == api.MOBILE_TOKEN_MAX_AGE
    assert client.get('/api/mobile/me', headers=old_headers).status_code == 401
    new_headers = {'Authorization': 'Bearer ' + data['token']}
    assert client.get('/api/mobile/me', headers=new_headers).status_code == 200
    assert client.post('/api/mobile/auth/password-setup', headers=new_headers, json={'new_password': 'OtherFixture!234'}).status_code == 409
    saved.assert_called_once()
    login = client.post('/api/mobile/login', json={'email': user['email'], 'password': PASSWORD})
    assert login.status_code == 200 and login.json()['user']['id'] == before['id']
    monkeypatch.setattr(identity, 'google_login', lambda token: dict(user))
    google = client.post('/api/mobile/auth/google', json={'id_token': 'synthetic-proof-' * 3})
    assert google.status_code == 200
    assert google.json()['user']['id'] == before['id']
    assert google.json()['user']['password_setup_required'] is False


def test_existing_accounts_do_not_gain_a_setup_requirement(auth, monkeypatch):
    client, user, _ = auth
    user['password_setup_required'] = False
    monkeypatch.setattr(identity, 'google_login', lambda token: dict(user))
    result = client.post('/api/mobile/auth/google', json={'id_token': 'synthetic-proof-' * 3})
    assert result.status_code == 200
    assert result.json()['user']['password_setup_required'] is False
    assert 'scope' not in api.token_serializer.loads(result.json()['token'], salt='geosustain-mobile')


def test_disabled_pending_account_and_wrong_payload_cannot_restore(auth):
    client, user, _ = auth
    token = api.generate_mobile_token(user)
    user['is_active'] = False
    assert client.get('/api/mobile/me', headers={'Authorization': 'Bearer ' + token}).status_code == 401
    token = api.token_serializer.dumps(['invalid-payload'], salt='geosustain-mobile')
    assert client.get('/api/mobile/me', headers={'Authorization': 'Bearer ' + token}).status_code == 401


def test_cookie_session_does_not_bypass_setup(auth):
    _, user, _ = auth
    request = Request({'type': 'http', 'path': '/dashboard', 'method': 'GET', 'headers': [],
        'session': {'user_id': user['id'], 'password_version': 0, 'sid': 'fixture'}})
    assert api.current_user(request) is None


class LockedConnection:
    def __init__(self, user):
        self.user = user
        self.result = None
        self.updates = 0
    def __enter__(self):
        self.before = deepcopy(self.user)
        return self
    def __exit__(self, kind, value, trace):
        if kind:
            self.user.clear()
            self.user.update(self.before)
    def close(self):
        pass
    def cursor(self):
        return self
    def execute(self, sql, args):
        if sql.startswith('SELECT'):
            self.result = dict(self.user) if args[0] == self.user['id'] else None
        elif sql.startswith('UPDATE users'):
            password_hash, uid, version = args
            if uid == self.user['id'] and self.user['password_version'] == version and self.user['password_setup_required'] and self.user['is_active']:
                self.user.update(password_hash=password_hash, password_version=version + 1, password_setup_required=False)
                self.updates += 1
                self.result = dict(self.user)
            else:
                self.result = None
        elif sql.startswith('DELETE FROM push_subscriptions'):
            assert args == (self.user['id'],)
        else:
            raise AssertionError('Unexpected query in setup transaction')
    def fetchone(self):
        return self.result


@pytest.mark.parametrize('role', ['farmer', 'agricultural_planning_analyst', 'super_admin'])
def test_locked_setup_is_one_time_and_preserves_identity_and_role(monkeypatch, role):
    user = pending(role=role)
    actor = dict(user)
    connection = LockedConnection(user)
    audit = Mock()
    monkeypatch.setattr(identity.db, 'get_conn', lambda: connection)
    monkeypatch.setattr(identity.db, 'audit_in_transaction', audit)
    updated = identity.setup_google_password(actor, 'hashed-fixture-password')
    assert updated['password_setup_required'] is False and updated['password_version'] == 1
    for key in ['id', 'email', 'role', 'google_sub', 'auth_provider']:
        assert updated[key] == actor[key]
    with pytest.raises(HTTPException):
        identity.setup_google_password(actor, 'must-not-overwrite')
    assert connection.updates == 1 and user['password_hash'] == 'hashed-fixture-password'
    audit.assert_called_once()


@pytest.mark.parametrize('changes', [{'password_setup_required': False}, {'is_active': False},
    {'google_sub': None}, {'email_verified': False}])
def test_locked_setup_rejects_ineligible_accounts_without_writes(monkeypatch, changes):
    user = pending(**changes)
    connection = LockedConnection(user)
    monkeypatch.setattr(identity.db, 'get_conn', lambda: connection)
    with pytest.raises(HTTPException):
        identity.setup_google_password(dict(user), 'must-not-write')
    assert connection.updates == 0


def test_audit_failure_rolls_back_setup(monkeypatch):
    user = pending()
    before = dict(user)
    connection = LockedConnection(user)
    monkeypatch.setattr(identity.db, 'get_conn', lambda: connection)
    monkeypatch.setattr(identity.db, 'audit_in_transaction', Mock(side_effect=RuntimeError('fixture audit unavailable')))
    with pytest.raises(RuntimeError):
        identity.setup_google_password(dict(user), 'must-roll-back')
    assert user == before
