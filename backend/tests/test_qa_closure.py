from unittest.mock import Mock
import pytest
import qa_closure
import fastapi_app as api
import analysis_jobs
from fastapi import HTTPException


def test_private_response_headers_and_limits(client, monkeypatch):
    monkeypatch.setattr(qa_closure,'inbox',lambda *a: {'notifications':[], 'unread_count':0,'has_more':False})
    response=client.get('/api/mobile/notifications')
    assert response.status_code == 200
    assert response.headers['cache-control'] == 'no-store'
    assert response.headers['x-frame-options'] == 'DENY'
    assert "frame-ancestors 'none'" in response.headers['content-security-policy']
    assert client.get('/api/mobile/notifications?limit=101').status_code == 422
    assert client.get('/api/mobile/notifications?offset=-1').status_code == 422
    assert client.get('/api/admin/messages').status_code == 403


def test_inbox_and_read_always_receive_authenticated_owner(client, monkeypatch):
    inbox=Mock(return_value={'notifications':[], 'unread_count':0})
    mark=Mock(return_value=None)
    monkeypatch.setattr(qa_closure,'inbox',inbox)
    monkeypatch.setattr(qa_closure,'read_notification',mark)
    assert client.get('/api/mobile/notifications?offset=50').status_code == 200
    inbox.assert_called_once_with(10,50,50)
    assert client.post('/api/mobile/notifications/100/read').status_code == 404
    mark.assert_called_with(10,100)
    assert client.post('/api/mobile/reviews/100/read').status_code == 404
    mark.assert_called_with(10,100,by_session=True)


def test_shared_auth_limit_and_database_failure_are_sanitized(client, monkeypatch):
    monkeypatch.setattr(qa_closure,'consume_quota',lambda *a: 12)
    response=client.post('/api/mobile/login',json={'email':'a@example.com','password':'x'})
    assert response.status_code == 429
    assert response.headers['retry-after']=='12'
    def fail(*a):
        raise RuntimeError('private database string')
    monkeypatch.setattr(qa_closure,'consume_quota',fail)
    response=client.post('/api/mobile/login',json={})
    assert response.status_code == 503
    assert 'private database' not in response.text


def test_quota_error_has_retry_after(monkeypatch):
    monkeypatch.setattr(qa_closure,'consume_quota',lambda *a: 9)
    with pytest.raises(HTTPException) as exc:
        qa_closure.enforce_quota(1,'analysis',10)
    assert exc.value.status_code == 429
    assert exc.value.headers['Retry-After']=='9'


def test_body_size_and_depth_limits_recover(client):
    assert client.post('/api/mobile/analysis',content=b' '*3_000_001,headers={'Content-Type':'application/json'}).status_code==413
    assert client.post('/api/mobile/analysis',content='['*65+'0'+']'*65,headers={'Content-Type':'application/json'}).status_code==413
    assert client.post('/api/mobile/analysis',json={'lat':91,'lon':125}).status_code==422
    assert client.get('/health').status_code==200


def test_queue_contract_and_required_identity(client,monkeypatch):
    monkeypatch.setattr(analysis_jobs,'enabled',lambda:True)
    monkeypatch.setattr(api,'find_analysis_request',lambda *a:None)
    queued=Mock()
    monkeypatch.setattr(analysis_jobs,'enqueue',queued)
    payload={'lat':7.29,'lon':125.62}
    assert client.post('/api/mobile/analysis',json=payload).status_code==400
    response=client.post('/api/mobile/analysis',json=payload,headers={'Idempotency-Key':'queued-key-0001'})
    assert response.status_code==202 and response.json()['stage']=='queued'
    assert queued.call_args.args[0]['id']==10


def test_push_link_is_configured_https_and_content_is_generic(monkeypatch):
    from push_delivery import send
    monkeypatch.setenv('FCM_PROJECT_ID','test-project')
    monkeypatch.setenv('PUBLIC_WEB_APP_URL','https://example.com')
    http=Mock()
    http.post.return_value.status_code=200
    assert send('test-only-device-token',99,http)=='sent'
    message=http.post.call_args.kwargs['json']['message']
    assert message['webpush']['fcm_options']['link']=='https://example.com/?review=99'
    assert message['data']=={'session_id':'99'}
    monkeypatch.setenv('PUBLIC_WEB_APP_URL','http://example.com')
    send('test-only-device-token',99,http)
    assert 'fcm_options' not in http.post.call_args.kwargs['json']['message']['webpush']
