import pytest
from unittest.mock import Mock
from test_regressions import api
from fastapi.testclient import TestClient


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setattr(api, "init_db", lambda: None)
    with TestClient(api.app) as instance:
        yield instance
    api.app.dependency_overrides.clear()

from migrate_password_auth import prepare_password
from password_auth import verify_password


def account(**changes):
    data = dict(id=3, username='Farmer', email='farmer@example.com', role='farmer', is_active=True,
                email_verified=False, password_hash=api.hash_password('test-password'))
    return dict(data, **changes)


def test_login_unverified_email_and_normalization(client, monkeypatch):
    lookup = Mock(return_value=account())
    monkeypatch.setattr(api, 'get_user_by_email', lookup)
    result = client.post('/api/mobile/login', json={'email':' Farmer@Example.com ', 'password':'test-password'})
    assert result.status_code == 200
    assert result.json()['token']
    lookup.assert_called_once_with('farmer@example.com')
    assert 'password_hash' not in result.json()['user']


@pytest.mark.parametrize('changes,password,status', [({},'wrong',401), ({'password_hash':'test-password'},'test-password',401), ({'is_active':False},'test-password',403)])
def test_login_rejects_invalid_credentials_and_inactive_users(client, monkeypatch, changes,password,status):
    monkeypatch.setattr(api,'get_user_by_email',lambda email: account(**changes))
    assert client.post('/api/mobile/login',json={'email':'farmer@example.com','password':password}).status_code == status


def test_register_creates_user_directly(client, monkeypatch):
    monkeypatch.setattr(api,'get_user_by_email',lambda email: None)
    create = Mock(return_value=account())
    monkeypatch.setattr(api,'create_user',create)
    result=client.post('/api/mobile/register',json={'username':' Farmer ','email':' Farmer@Example.com ','password':'test-password','role':'super_admin'})
    assert result.status_code == 201
    assert result.json()['requires_verification'] is False
    args=create.call_args.args
    assert args[0:2] == ('Farmer','farmer@example.com')
    assert verify_password('test-password',args[2])
    assert args[3] == 'farmer'


def test_register_existing_unverified_account_is_not_replaced(client,monkeypatch):
    monkeypatch.setattr(api,'get_user_by_email',lambda email:account())
    assert client.post('/api/mobile/register',json={'username':'Farmer','email':'farmer@example.com','password':'different'}).status_code == 409


@pytest.mark.parametrize('route',['verify-email','verify-code','send-verification','resend-verification'])
def test_retired_routes_never_return_tokens(client,route):
    result=client.post('/api/mobile/'+route,json={'email':'farmer@example.com','code':'000000'})
    assert result.status_code == 410
    assert 'token' not in result.json()


def test_plaintext_migration_requires_explicit_confirmation():
    with pytest.raises(ValueError):
        prepare_password('legacy-password')
    hashed=prepare_password('legacy-password',confirmed_plaintext=True)
    assert verify_password('legacy-password',hashed)
    assert prepare_password(hashed)==hashed


def test_html_verification_redirects_to_login(client):
    result=client.post('/verify-email',data={'email':'farmer@example.com'},follow_redirects=False)
    assert result.status_code == 303
    assert result.headers['location']=='/login'


def test_html_login_does_not_require_email_verification(client, monkeypatch):
    monkeypatch.setattr(api,'get_user_by_email',lambda email:account())
    result=client.post('/login',data={'email':'farmer@example.com','password':'test-password'},follow_redirects=False)
    assert result.status_code==302
    assert result.headers['location']=='/dashboard'


def test_migration_preserves_hash_and_existing_account(monkeypatch):
    from migrate_password_auth import migrate
    existing_hash=api.hash_password('existing-password')
    cursor=Mock()
    cursor.__enter__=Mock(return_value=cursor)
    cursor.__exit__=Mock(return_value=False)
    cursor.fetchone.side_effect=[None, {'id':7}, None]
    cursor.fetchall.side_effect=[
        [{'id':7,'password_hash':existing_hash}],
        [{'username':'Duplicate','email':'EXISTING@example.com','password_hash':api.hash_password('different-password'),'role':'farmer'},
         {'username':'Pending','email':'NEW@example.com','password_hash':existing_hash,'role':'analyst'}]]
    conn=Mock()
    conn.cursor.return_value=cursor
    result=migrate(conn)
    assert result['pending_accounts_promoted']==1
    updates=[c.args for c in cursor.execute.call_args_list if c.args[0].startswith('UPDATE users SET password_hash')]
    assert updates[0][1]==(existing_hash,7)
    inserts=[c.args for c in cursor.execute.call_args_list if c.args[0].startswith('INSERT INTO users')]
    assert len(inserts)==1
    assert inserts[0][1][1]=='new@example.com'
    assert inserts[0][1][3]=='agricultural_planning_analyst'
    conn.commit.assert_not_called()


def test_migration_stops_on_duplicate_normalized_emails():
    from migrate_password_auth import migrate
    cursor=Mock()
    cursor.__enter__=Mock(return_value=cursor)
    cursor.__exit__=Mock(return_value=False)
    cursor.fetchone.return_value={'email':'duplicate@example.com'}
    conn=Mock()
    conn.cursor.return_value=cursor
    with pytest.raises(ValueError,match='Duplicate'):
        migrate(conn)
    assert not any(c.args[0].startswith('UPDATE') for c in cursor.execute.call_args_list)
