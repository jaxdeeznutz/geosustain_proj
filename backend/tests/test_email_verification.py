from unittest.mock import Mock
import pytest
from fastapi import HTTPException
import email_verification as mail


def test_unconfigured_delivery_never_claims_sent(monkeypatch):
    monkeypatch.delenv('SMTP_HOST', raising=False)
    with pytest.raises(HTTPException) as exc:
        mail.deliver('fixture@example.com', '123456')
    assert exc.value.status_code == 503


def test_smtp_failure_is_sanitized(monkeypatch):
    monkeypatch.setenv('SMTP_HOST', 'fixture.invalid')
    monkeypatch.setenv('SMTP_FROM', 'fixture@example.com')
    monkeypatch.setattr(mail.smtplib, 'SMTP', Mock(side_effect=RuntimeError('private-secret')))
    with pytest.raises(HTTPException) as exc:
        mail.deliver('fixture@example.com', '123456')
    assert 'private-secret' not in str(exc.value.detail)


def test_code_bound_to_ticket_and_server_key():
    a = mail.code_digest('ticket-one', '123456', 'secret-one')
    assert a != mail.code_digest('ticket-two', '123456', 'secret-one')
    assert a != mail.code_digest('ticket-one', '123456', 'secret-two')


def test_enabled_signup_returns_challenge_and_does_not_create_user(client, monkeypatch):
    import fastapi_app as api
    monkeypatch.setenv('EMAIL_VERIFICATION_REQUIRED', '1')
    monkeypatch.setattr(api, 'get_user_by_email', lambda email: None)
    create = Mock(); monkeypatch.setattr(api, 'create_user', create)
    start = Mock(return_value={'requires_verification': True, 'verification_ticket': 'x'*43})
    monkeypatch.setattr(mail, 'start', start)
    response = client.post('/api/mobile/register', json={'username':'Farmer','email':'new@example.com','password':'Test!234','role':'super_admin'})
    assert response.status_code == 201 and response.json()['requires_verification']
    create.assert_not_called()
    assert 'token' not in response.json()


def test_code_routes_validate_ticket_and_never_issue_login_token(client, monkeypatch):
    monkeypatch.setenv('EMAIL_VERIFICATION_REQUIRED', '1')
    verify = Mock(return_value={'verified': True}); monkeypatch.setattr(mail, 'verify', verify)
    assert client.post('/api/mobile/verify-email', json={'email':'new@example.com','code':'123456'}).status_code == 422
    assert client.post('/api/mobile/verify-email', json={'ticket':'x'*43,'code':'12ab56'}).status_code == 422
    response = client.post('/api/mobile/verify-email', json={'ticket':'x'*43,'code':'123456'})
    assert response.json() == {'verified': True}


def test_sender_uses_tls_and_never_logs_code(monkeypatch):
    monkeypatch.setenv('SMTP_HOST', 'fixture.invalid'); monkeypatch.setenv('SMTP_FROM', 'fixture@example.com')
    monkeypatch.setenv('SMTP_SECURITY', 'starttls'); monkeypatch.delenv('SMTP_USERNAME', raising=False)
    smtp = Mock(); smtp.__enter__ = Mock(return_value=smtp); smtp.__exit__ = Mock(return_value=False)
    smtp.send_message.return_value = {}
    monkeypatch.setattr(mail.smtplib, 'SMTP', Mock(return_value=smtp))
    mail.deliver('recipient@example.com', '123456')
    smtp.starttls.assert_called_once()
    assert smtp.send_message.call_args.args[0]['To'] == 'recipient@example.com'
