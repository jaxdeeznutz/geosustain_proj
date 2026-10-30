"""Restored analyst tools retain owner isolation and farmer submission rules."""
from copy import deepcopy
from unittest.mock import Mock

import pytest


ROLES = ['analyst', 'planner', 'agricultural_planning_analyst']


@pytest.mark.parametrize('role', ROLES)
def test_independent_assessment_saves_only_to_authenticated_analyst(client, monkeypatch, role):
    import fastapi_app as api
    import analysis_jobs
    user = {'id': 27, 'role': role}
    api.app.dependency_overrides[api.get_api_user] = lambda: user
    monkeypatch.setattr(analysis_jobs, 'enabled', lambda: False)
    monkeypatch.setattr(api, 'find_analysis_request', lambda *args: None)
    monkeypatch.setattr(api.qa_closure, 'enforce_quota', lambda *args: None)
    result = {'selected_polygon': [], 'nitrogen': 75, 'crop_compatibility_pct': 12.042,
              'local_model_explanation': {'snapshot_hash': 'unchanged-test-snapshot'}}
    monkeypatch.setattr(api, 'build_analysis_result', lambda **kwargs: (deepcopy(result), 'test'))
    save = Mock(return_value=91)
    monkeypatch.setattr(api, 'save_analysis_session', save)
    read = Mock(return_value={'session_id': 91, 'user_id': 27})
    monkeypatch.setattr(api, 'get_user_analysis', read)
    response = client.post('/api/web/analysis', json={'lat': 7.29, 'lon': 125.62},
                           headers={'Idempotency-Key': 'phase07-independent-analysis'})
    assert response.status_code == 200, response.text
    assert response.json()['user_id'] == 27
    owner, snapshot, source = save.call_args.args
    assert owner == 27 and source == 'test'
    assert all(snapshot[key] == value for key, value in result.items())
    assert snapshot['formal_submission_eligible'] is False
    assert snapshot.get('farm_id') is None
    read.assert_called_once_with(27, 91)


@pytest.mark.parametrize('role', ROLES)
@pytest.mark.parametrize('field,value', [('farm_id', 7), ('boundary_version', 1)])
def test_independent_assessment_cannot_attach_farmer_fields_or_enqueue(client, monkeypatch, role, field, value):
    import fastapi_app as api
    import analysis_jobs
    api.app.dependency_overrides[api.get_api_user] = lambda: {'id': 27, 'role': role}
    monkeypatch.setattr(analysis_jobs, 'enabled', lambda: True)
    enqueue = Mock()
    monkeypatch.setattr(analysis_jobs, 'enqueue', enqueue)
    response = client.post('/api/web/analysis', json={'lat': 7.29, 'lon': 125.62, field: value},
                           headers={'Idempotency-Key': 'phase07-independent-analysis'})
    assert response.status_code == 403
    enqueue.assert_not_called()
    # The worker's common pipeline must enforce the same boundary.
    with pytest.raises(api.HTTPException) as error:
        api._perform_mobile_analysis(api.AnalysisBody(lat=7.29, lon=125.62, **{field: value}),
                                     {'id': 27, 'role': role}, 'phase07-worker-check')
    assert error.value.status_code == 403


@pytest.mark.parametrize('role', ['farmer', 'admin', 'super_admin', 'unknown'])
def test_independent_endpoint_does_not_expand_other_roles(client, monkeypatch, role):
    import fastapi_app as api
    build = Mock()
    monkeypatch.setattr(api, 'build_analysis_result', build)
    api.app.dependency_overrides[api.get_api_user] = lambda: {'id': 27, 'role': role}
    assert client.post('/api/web/analysis', json={'lat': 7.29, 'lon': 125.62}).status_code == 403
    build.assert_not_called()


def test_independent_queue_keeps_authenticated_owner_and_shared_request_tracking(client, monkeypatch):
    import fastapi_app as api
    import analysis_jobs
    user = {'id': 27, 'role': 'analyst'}
    api.app.dependency_overrides[api.get_api_user] = lambda: user
    monkeypatch.setattr(analysis_jobs, 'enabled', lambda: True)
    monkeypatch.setattr(api, 'find_analysis_request', lambda *args: None)
    enqueue = Mock()
    monkeypatch.setattr(analysis_jobs, 'enqueue', enqueue)
    response = client.post('/api/web/analysis', json={'lat': 7.29, 'lon': 125.62},
                           headers={'Idempotency-Key': 'phase07-independent-analysis'})
    assert response.status_code == 202
    assert enqueue.call_args.args[0] == user
    assert enqueue.call_args.args[3] == {'lat': 7.29, 'lon': 125.62}
