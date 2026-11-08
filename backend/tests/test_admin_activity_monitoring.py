import json
from unittest.mock import Mock
import pytest
import database
import fastapi_app as api
import system_monitoring
import rainfallDatasets


@pytest.mark.parametrize('role', ['farmer', 'agricultural_planning_analyst', 'super_admin'])
def test_successful_password_signin_records_actual_role_without_credentials(client, monkeypatch, role):
    user = dict(id=44, username='Synthetic user', email='synthetic@example.com',
                role=role, is_active=True, password_hash='not-a-real-hash')
    monkeypatch.setattr(api, 'get_user_by_email', lambda email: user)
    monkeypatch.setattr(api, 'verify_password', lambda *args: True)
    monkeypatch.setattr(api, 'generate_mobile_token', lambda user: 'synthetic-token')
    audit = Mock()
    monkeypatch.setattr(database, 'write_audit_log', audit)
    response = client.post('/api/mobile/login', json={'email': user['email'], 'password': 'Synthetic!234'})
    assert response.status_code == 200
    audit.assert_called_once_with(44, role, 'sign_in', 'user', 44,
                                  {'method': 'password', 'channel': 'api'})
    assert 'Synthetic!234' not in repr(audit.call_args)
    assert 'synthetic-token' not in repr(audit.call_args)


def test_rejected_signin_does_not_record_a_success(client, monkeypatch):
    monkeypatch.setattr(api, 'get_user_by_email', lambda email: None)
    monkeypatch.setattr(api, 'verify_password', lambda *args: False)
    audit = Mock()
    monkeypatch.setattr(database, 'write_audit_log', audit)
    assert client.post('/api/mobile/login', json={'email': 'nobody@example.com', 'password': 'bad'}).status_code == 401
    audit.assert_not_called()


def test_google_signin_records_provider_without_identity_proof(client, monkeypatch):
    import federated_identity
    user = dict(id=44, role='farmer', username='Synthetic', email='synthetic@example.com')
    monkeypatch.setattr(federated_identity, 'google_login', lambda proof: user)
    monkeypatch.setattr(api, 'generate_mobile_token', lambda user: 'synthetic-token')
    audit = Mock()
    monkeypatch.setattr(database, 'write_audit_log', audit)
    assert client.post('/api/mobile/auth/google', json={'id_token': 'x'*40}).status_code == 200
    assert audit.call_args.args[-1] == {'method': 'google', 'channel': 'api'}
    assert 'x'*40 not in repr(audit.call_args)


def test_monitoring_is_admin_only_and_never_cached(client, monkeypatch):
    value = {'status': 'healthy', 'checked_at': '2026-11-08T00:00:00Z', 'checks': []}
    monkeypatch.setattr(system_monitoring, 'snapshot', lambda: value)
    assert client.get('/api/admin/system-status').status_code == 403
    api.app.dependency_overrides[api.get_api_user] = lambda: {'id': 1, 'role': 'super_admin', 'is_active': True}
    response = client.get('/api/admin/system-status')
    assert response.status_code == 200 and response.json() == value
    assert response.headers['cache-control'] == 'no-store'


@pytest.mark.parametrize('reports_fail', [False, True])
def test_monitoring_reports_actual_reads_and_does_not_claim_maps_are_healthy(monkeypatch, reports_fail):
    cursor = Mock()
    cursor.__enter__ = Mock(return_value=cursor)
    cursor.__exit__ = Mock(return_value=False)
    def execute(statement):
        if reports_fail and 'FROM reports' in statement:
            raise RuntimeError('synthetic missing report relation')
    cursor.execute.side_effect = execute
    connection = Mock()
    connection.cursor.return_value = cursor
    monkeypatch.setattr(database, 'get_conn', lambda: connection)
    monkeypatch.setattr(rainfallDatasets, 'model_health', lambda: {'status': 'loaded'})
    snapshot = system_monitoring.snapshot()
    checks = {c['key']: c for c in snapshot['checks']}
    assert checks['database']['status'] == 'healthy'
    assert checks['reports']['status'] == ('unavailable' if reports_fail else 'healthy')
    assert checks['maps']['status'] == 'client_side'
    assert snapshot['status'] == ('attention' if reports_fail else 'healthy')
    connection.close.assert_called_once()


def test_monitoring_failure_is_explicit_and_sanitized(monkeypatch):
    def unavailable():
        raise RuntimeError('postgresql://private:secret@example.com/database')
    monkeypatch.setattr(database, 'get_conn', unavailable)
    monkeypatch.setattr(rainfallDatasets, 'model_health', lambda: {'status': 'loaded'})
    snapshot = system_monitoring.snapshot()
    assert snapshot['status'] == 'attention'
    assert next(c for c in snapshot['checks'] if c['key'] == 'database')['status'] == 'unavailable'
    assert 'secret' not in json.dumps(snapshot)
