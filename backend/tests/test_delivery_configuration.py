import json
import pytest
import push_delivery as push
import mail_delivery as mail


@pytest.mark.parametrize('value',['not-json','null','[]','{}',json.dumps({'type':'service_account','token_uri':'http://example.com/token'})])
def test_required_push_cannot_report_ready_for_malformed_or_unsafe_identity(monkeypatch,value):
    monkeypatch.setenv('FCM_PROJECT_ID','geosustain-fixture')
    monkeypatch.setenv('FCM_SERVICE_ACCOUNT_JSON',value)
    assert push.configured() is False


def test_validated_push_identity_uses_bounded_google_scope(monkeypatch):
    info={'type':'service_account','token_uri':'https://oauth2.googleapis.com/token'}
    monkeypatch.setenv('FCM_PROJECT_ID','geosustain-fixture')
    monkeypatch.setenv('FCM_SERVICE_ACCOUNT_JSON',json.dumps(info))
    seen={}
    def validate(data,scopes):
        seen.update(data=data,scopes=scopes)
        return object()
    monkeypatch.setattr(push.Credentials,'from_service_account_info',validate)
    assert push.configured()
    assert seen['scopes']==['https://www.googleapis.com/auth/firebase.messaging']


@pytest.mark.parametrize('port,mode',[('0','starttls'),('70000','ssl'),('587','none')])
def test_required_email_cannot_report_ready_for_unsupported_tls_or_port(monkeypatch,port,mode):
    monkeypatch.setenv('EMAIL_TRANSPORT','smtp')
    monkeypatch.setenv('MAIL_FROM','fixture@example.com')
    monkeypatch.setenv('SMTP_HOST','smtp.example.com')
    monkeypatch.setenv('SMTP_PORT',port)
    monkeypatch.setenv('SMTP_SECURITY',mode)
    assert mail.configured() is False
