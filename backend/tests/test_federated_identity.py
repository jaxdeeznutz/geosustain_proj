"""Real local RSA signature verification; no Firebase project/provider requests."""
from datetime import datetime, timedelta, timezone
import json
import time
from unittest.mock import Mock
import pytest
from fastapi import HTTPException
from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import serialization, hashes
from cryptography.hazmat.primitives.asymmetric import rsa
from google.auth import crypt, jwt
import federated_identity as identity


@pytest.fixture
def proof(monkeypatch):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'Local test certificate')])
    now = datetime.now(timezone.utc)
    cert = x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(key.public_key()).serial_number(
        x509.random_serial_number()).not_valid_before(now-timedelta(minutes=1)).not_valid_after(now+timedelta(days=1)).sign(key, hashes.SHA256())
    signer = crypt.RSASigner.from_string(key.private_bytes(serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8, serialization.NoEncryption()), key_id='fixture')
    request = Mock(return_value=Mock(status=200, data=json.dumps({'fixture': cert.public_bytes(serialization.Encoding.PEM).decode()}).encode()))
    monkeypatch.setattr(identity, 'BoundedRequest', lambda: request)
    monkeypatch.setenv('FIREBASE_AUTH_PROJECT_ID', 'geosustain-fixture')
    def signed(**changes):
        payload = {'iss': 'https://securetoken.google.com/geosustain-fixture', 'aud': 'geosustain-fixture',
            'sub': 'immutable-fixture-subject', 'iat': int(time.time()), 'exp': int(time.time())+3600,
            'auth_time': int(time.time()), 'firebase': {'sign_in_provider': 'google.com'},
            'email_verified': True, 'email': 'fixture@example.com', 'name': 'Fixture Farmer'}
        payload.update(changes)
        return jwt.encode(signer, payload).decode()
    return signed


def test_real_signature_and_correct_identity_are_required(proof):
    claims, email = identity.google_identity(proof())
    assert claims['sub'] == 'immutable-fixture-subject' and email == 'fixture@example.com'
    token = proof()
    head, body, signature = token.split('.')
    with pytest.raises(HTTPException) as failure:
        identity.google_identity(head+'.'+body+'.'+('A' if signature[0] != 'A' else 'B')+signature[1:])
    assert failure.value.status_code == 401


@pytest.mark.parametrize('changes', [
    {'iss': 'https://attacker.invalid'}, {'aud': 'different-project'},
    {'auth_time': int(time.time())-600}, {'auth_time': int(time.time())+600},
    {'firebase': {'sign_in_provider': 'phone'}}, {'email_verified': False},
    {'exp': int(time.time())-60}, {'sub': ''},
])
def test_signed_but_wrong_or_stale_claims_are_rejected(proof, changes):
    with pytest.raises(HTTPException) as failure:
        identity.google_identity(proof(**changes))
    assert failure.value.status_code == 401


def test_existing_email_never_implicitly_merges_accounts(proof, monkeypatch):
    monkeypatch.setattr(identity.db, 'get_user_by_google_sub', lambda subject: None)
    monkeypatch.setattr(identity.db, 'get_user_by_email', lambda email: {'id': 5, 'role': 'farmer'})
    create = Mock(); monkeypatch.setattr(identity.db, 'create_user', create)
    with pytest.raises(HTTPException) as failure:
        identity.google_login(proof())
    assert failure.value.status_code == 409
    create.assert_not_called()


def test_new_google_user_has_server_owned_lowest_role(proof, monkeypatch):
    monkeypatch.setattr(identity.db, 'get_user_by_google_sub', lambda subject: None)
    monkeypatch.setattr(identity.db, 'get_user_by_email', lambda email: None)
    create = Mock(return_value={'id': 5, 'role': 'farmer'})
    monkeypatch.setattr(identity.db, 'create_user', create)
    assert identity.google_login(proof())['role'] == 'farmer'
    assert create.call_args.kwargs == {'role': 'farmer', 'email_verified': True,
        'auth_provider': 'google', 'google_sub': 'immutable-fixture-subject'}


def test_disabled_identity_cannot_get_an_app_session(proof, monkeypatch):
    monkeypatch.setattr(identity.db, 'get_user_by_google_sub', lambda subject: {'id': 5, 'is_active': False})
    with pytest.raises(HTTPException) as failure:
        identity.google_login(proof())
    assert failure.value.status_code == 403


def test_link_needs_existing_password_and_same_email(proof):
    user = {'id': 5, 'email': 'fixture@example.com', 'password_hash': None}
    with pytest.raises(HTTPException) as failure:
        identity.link_google(user, proof(), 'wrong-password')
    assert failure.value.status_code == 401
    with pytest.raises(HTTPException) as failure:
        identity.link_google({**user, 'email': 'different@example.com'}, proof(), 'anything')
    assert failure.value.status_code == 400


def test_missing_provider_fails_closed_without_database(client, monkeypatch):
    monkeypatch.delenv('FIREBASE_AUTH_PROJECT_ID', raising=False)
    response = client.post('/api/mobile/auth/google', json={'id_token': 'x'*100, 'role': 'super_admin'})
    assert response.status_code == 503 and 'token' not in response.json()
    assert client.post('/api/mobile/phone-verification/start', json={'phone_number': '09171234567'}).status_code == 422
    assert client.post('/api/mobile/phone-verification/start', json={'phone_number': '+639171234567'}).status_code == 503


def test_phone_status_is_server_owned(client, monkeypatch):
    import fastapi_app as api
    update = Mock(return_value={'id': 10, 'username': 'Farmer', 'email': 'fixture@example.com', 'role': 'farmer',
        'phone_number': '+639171234567', 'phone_verified_at': None})
    monkeypatch.setattr(api, 'update_user_profile', update)
    response = client.put('/api/mobile/me', json={'phone_number': '+639171234567', 'phone_verified': True, 'role': 'super_admin'})
    assert response.status_code == 200
    assert not response.json()['user']['phone_verified'] and response.json()['user']['role'] == 'farmer'
    assert update.call_args.kwargs['phone_number'] == '+639171234567'
