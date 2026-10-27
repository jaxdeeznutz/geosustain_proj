from unittest.mock import Mock
import pytest
from fastapi import HTTPException
import mail_delivery as mail


@pytest.fixture
def https_sender(monkeypatch):
    monkeypatch.setenv('EMAIL_TRANSPORT', 'resend')
    monkeypatch.setenv('RESEND_API_KEY', 'synthetic-provider-key')
    monkeypatch.setenv('MAIL_FROM', 'GeoSustain <fixture@example.com>')


def test_https_sender_binds_message_and_retry_identity(https_sender, monkeypatch):
    post = Mock(return_value=Mock(status_code=200, json=lambda: {'id': 'fixture-accepted'}))
    monkeypatch.setattr(mail.requests, 'post', post)
    mail.send('recipient@example.com', 'Fixture subject', 'Fixture message', idempotency_key='fixture-once')
    assert post.call_args.args[0] == 'https://api.resend.com/emails'
    request = post.call_args.kwargs
    assert request['json']['to'] == ['recipient@example.com']
    assert request['headers']['Idempotency-Key'] == 'fixture-once'
    assert request['timeout'] == (5, 15) and request['allow_redirects'] is False


@pytest.mark.parametrize('status,payload', [(429, {'error': 'private-provider-detail'}), (503, {}), (200, {})])
def test_provider_failure_never_claims_delivery_or_leaks_body(https_sender, monkeypatch, status, payload):
    monkeypatch.setattr(mail.requests, 'post', Mock(return_value=Mock(status_code=status, json=lambda: payload)))
    with pytest.raises(HTTPException) as failure:
        mail.send('recipient@example.com', 'Fixture', 'Fixture')
    assert failure.value.status_code == 503 and 'private-provider-detail' not in failure.value.detail


def test_free_render_smtp_cannot_be_misreported_ready(monkeypatch):
    monkeypatch.setenv('RENDER', 'true'); monkeypatch.setenv('EMAIL_TRANSPORT', 'smtp')
    monkeypatch.setenv('SMTP_HOST', 'fixture.invalid'); monkeypatch.setenv('SMTP_FROM', 'fixture@example.com')
    for port in ['25', '465', '587', 'invalid']:
        monkeypatch.setenv('SMTP_PORT', port)
        assert not mail.configured()


def test_production_requires_email_verification_unless_explicit_policy(monkeypatch):
    import email_verification
    monkeypatch.setenv('APP_ENV', 'production')
    monkeypatch.delenv('EMAIL_VERIFICATION_REQUIRED', raising=False)
    assert email_verification.enabled()


@pytest.fixture
def brevo_sender(monkeypatch):
    monkeypatch.setenv('EMAIL_TRANSPORT', 'brevo')
    monkeypatch.setenv('BREVO_API_KEY', 'synthetic-brevo-key')
    monkeypatch.setenv('MAIL_FROM', 'GeoSustain <fixture@example.com>')


def test_brevo_https_sender_and_stable_uuid_retry_identity(brevo_sender, monkeypatch):
    from uuid import UUID
    post = Mock(return_value=Mock(status_code=201, json=lambda: {'messageId': '<fixture-only>'}))
    monkeypatch.setattr(mail.requests, 'post', post)
    monkeypatch.setenv('RENDER', 'true')
    assert mail.configured()
    mail.send('recipient@example.com', 'Fixture', 'Fixture message', idempotency_key='fixture-retry')
    request = post.call_args.kwargs
    assert post.call_args.args[0] == 'https://api.brevo.com/v3/smtp/email'
    assert request['headers']['api-key'] == 'synthetic-brevo-key'
    assert request['json']['sender'] == {'name': 'GeoSustain', 'email': 'fixture@example.com'}
    assert request['json']['to'] == [{'email': 'recipient@example.com'}]
    assert request['json']['textContent'] == 'Fixture message'
    assert request['timeout'] == (5, 15) and request['allow_redirects'] is False
    first = request['json']['headers']['IdempotencyKey']
    assert str(UUID(first)) == first
    mail.send('recipient@example.com', 'Fixture', 'Fixture message', idempotency_key='fixture-retry')
    assert post.call_args.kwargs['json']['headers']['IdempotencyKey'] == first
    mail.send('recipient@example.com', 'Fixture', 'Fixture message', idempotency_key='different-retry')
    assert post.call_args.kwargs['json']['headers']['IdempotencyKey'] != first


@pytest.mark.parametrize('status,payload', [(400, {'code': 'duplicate_parameter'}),
    (401, {'message': 'private-provider-detail'}), (429, {}), (500, {}), (201, {})])
def test_brevo_failure_does_not_claim_delivery_or_expose_provider(brevo_sender, monkeypatch, status, payload):
    monkeypatch.setattr(mail.requests, 'post', Mock(return_value=Mock(status_code=status, json=lambda: payload)))
    with pytest.raises(HTTPException) as failure:
        mail.send('recipient@example.com', 'Fixture', 'Fixture')
    assert failure.value.status_code == 503
    assert 'private-provider-detail' not in failure.value.detail


def test_brevo_missing_key_and_invalid_sender_are_unconfigured(brevo_sender, monkeypatch):
    monkeypatch.delenv('BREVO_API_KEY')
    assert not mail.configured()
    monkeypatch.setenv('BREVO_API_KEY', 'synthetic-brevo-key')
    for sender in ('not-an-address', 'GeoSustain <broken@>', 'fixture@example.com\nInjected: value'):
        monkeypatch.setenv('MAIL_FROM', sender)
        assert not mail.configured()


def test_brevo_selection_preserves_existing_resend_precedence(monkeypatch):
    monkeypatch.delenv('EMAIL_TRANSPORT', raising=False)
    monkeypatch.delenv('RESEND_API_KEY', raising=False)
    monkeypatch.setenv('BREVO_API_KEY', 'synthetic-brevo-key')
    assert mail.transport() == 'brevo'
    monkeypatch.setenv('RESEND_API_KEY', 'synthetic-resend-key')
    assert mail.transport() == 'resend'
