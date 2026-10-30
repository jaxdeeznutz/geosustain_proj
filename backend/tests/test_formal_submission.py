from copy import deepcopy
from unittest.mock import Mock, MagicMock

import pytest

import database as db
from submission_policy import require_formal_polygon, attach_analysis_scope
from test_mobile_workflow import RING, connection


def farm():
    return {'id': 7, 'farmer_id': 10, 'polygon': deepcopy(RING),
            'boundary_version': 2, 'is_archived': False}


def draft():
    return {'id': 42, 'user_id': 10, 'farm_id': 7, 'boundary_version': 2,
            'selected_polygon': deepcopy(RING), 'verification_status': 'draft',
            'result_snapshot': {'selected_polygon': deepcopy(RING), 'boundary_version': 2}}


def test_equivalent_closed_reversed_boundary_is_eligible_without_rewriting():
    record, parcel = draft(), farm()
    before = deepcopy(record)
    parcel['polygon'] = RING[::-1] + [RING[-1]]
    require_formal_polygon(record, parcel, 10)
    assert record == before


@pytest.mark.parametrize('target,key,value', [
    ('farm', 'is_archived', True), ('farm', 'farmer_id', 11),
    ('session', 'user_id', 11), ('session', 'farm_id', None),
    ('session', 'farm_id', 8), ('session', 'boundary_version', 1),
    ('session', 'boundary_version', None), ('session', 'selected_polygon', []),
    ('session', 'selected_polygon', [RING[0], RING[2], RING[1], RING[3]]),
    ('session', 'result_snapshot', {'formal_submission_eligible': False}),
    ('session', 'result_snapshot', {'boundary_version': 1}),
    ('session', 'result_snapshot', {'selected_polygon': RING[:3]}),
])
def test_invalid_formal_submission_is_rejected(target, key, value):
    record, parcel = draft(), farm()
    (parcel if target == 'farm' else record)[key] = value
    with pytest.raises(ValueError):
        require_formal_polygon(record, parcel, 10)


def test_different_current_geometry_is_rejected_even_if_version_matches():
    parcel = farm()
    parcel['polygon'] = [{**p, 'lng': p['lng'] + .0001} for p in RING]
    with pytest.raises(ValueError, match='boundary'):
        require_formal_polygon(draft(), parcel, 10)


def test_initial_submission_locks_validates_and_notifies_once(monkeypatch):
    import activity_notifications
    import operator_workflow
    conn, cur = connection(monkeypatch, [draft(), farm(), {'id': 42, 'verification_status': 'pending'}])
    notify, ensure = Mock(), Mock()
    monkeypatch.setattr(activity_notifications, 'submitted', notify)
    monkeypatch.setattr(operator_workflow, 'ensure_case', ensure)
    assert db.submit_analysis_to_planner(10, 42)['verification_status'] == 'pending'
    assert 'FOR UPDATE OF s' in cur.queries[0][0]
    assert 'FOR SHARE' in cur.queries[1][0]
    notify.assert_called_once_with(cur, 10, 42)
    ensure.assert_called_once_with(cur, 42)
    conn.commit.assert_called_once()


def test_stale_submission_never_updates_status_or_creates_events(monkeypatch):
    record = draft()
    record['boundary_version'] = 1
    conn, cur = connection(monkeypatch, [record, farm()])
    with pytest.raises(ValueError, match='changed'):
        db.submit_analysis_to_planner(10, 42)
    assert not any('UPDATE analysis_sessions' in q for q, _ in cur.queries)
    conn.commit.assert_not_called()
    conn.close.assert_called_once()


@pytest.mark.parametrize('status', ['pending', 'verified', 'rejected', 'needs_information'])
def test_historical_submitted_retry_does_not_require_current_farm_or_repeat_events(monkeypatch, status):
    record = {'id': 42, 'verification_status': status, 'planner_notes': 'Original notes'}
    conn, cur = connection(monkeypatch, [record])
    result = db.submit_analysis_to_planner(10, 42)
    assert result['verification_status'] == status
    assert result['planner_notes'] == 'Original notes'
    assert len(cur.queries) == 1


def test_cross_user_or_nonfarmer_record_is_not_found(monkeypatch):
    _, cur = connection(monkeypatch, [None])
    assert db.submit_analysis_to_planner(10, 42) is None
    assert "u.role='farmer'" in cur.queries[0][0]
    assert cur.queries[0][1] == (42, 10)


def test_submission_api_returns_useful_conflict(client, monkeypatch):
    import fastapi_app as api
    monkeypatch.setattr(api, 'submit_analysis_to_planner', Mock(side_effect=ValueError('Analyze the current saved boundary.')))
    response = client.post('/api/mobile/submit-to-planner', json={'session_id': 42})
    assert response.status_code == 409
    assert response.json()['detail'] == 'Analyze the current saved boundary.'


@pytest.mark.parametrize('role', ['analyst', 'agricultural_planning_analyst', 'super_admin'])
def test_review_roles_cannot_use_farmer_analysis_route_including_queue(client, monkeypatch, role):
    import fastapi_app as api
    import analysis_jobs
    enqueue = Mock()
    monkeypatch.setattr(analysis_jobs, 'enabled', lambda: True)
    monkeypatch.setattr(analysis_jobs, 'enqueue', enqueue)
    api.app.dependency_overrides[api.get_api_user] = lambda: {'id': 10, 'role': role}
    assert client.post('/api/mobile/analysis', json={'lat': 7.29, 'lon': 125.62}).status_code == 403
    enqueue.assert_not_called()


def test_farm_version_conflict_fails_before_inference(client, monkeypatch):
    import fastapi_app as api
    monkeypatch.setattr(api, 'get_farm_parcel', lambda *a: farm())
    build = Mock()
    monkeypatch.setattr(api, 'build_analysis_result', build)
    response = client.post('/api/mobile/analysis', json={'farm_id': 7, 'boundary_version': 1})
    assert response.status_code == 409
    build.assert_not_called()


def test_versioned_farm_request_rejects_a_replacement_client_polygon(client, monkeypatch):
    import fastapi_app as api
    monkeypatch.setattr(api, 'get_farm_parcel', lambda *a: farm())
    build = Mock()
    monkeypatch.setattr(api, 'build_analysis_result', build)
    response = client.post('/api/mobile/analysis', json={
        'farm_id': 7, 'boundary_version': 2, 'polygon': RING[:3]})
    assert response.status_code == 409
    build.assert_not_called()


def test_versioned_farm_request_with_invalid_geometry_is_a_client_error(client, monkeypatch):
    import fastapi_app as api
    monkeypatch.setattr(api, 'get_farm_parcel', lambda *a: farm())
    build = Mock()
    monkeypatch.setattr(api, 'build_analysis_result', build)
    response = client.post('/api/mobile/analysis', json={
        'farm_id': 7, 'boundary_version': 2, 'polygon': [RING[0]] * 3})
    assert response.status_code == 400
    build.assert_not_called()


@pytest.mark.parametrize('polygon', [False, True])
def test_inspection_keeps_npk_and_scores_but_cannot_be_formally_submitted(polygon):
    record = {'nitrogen': 80, 'phosphorus': 47, 'potassium': 50,
              'crop_compatibility_pct': 60, 'selected_polygon': RING if polygon else []}
    previous = deepcopy(record)
    attach_analysis_scope(record)
    assert record['formal_submission_eligible'] is False
    assert record['analysis_scope'] == ('unsaved_polygon_inspection' if polygon else 'preliminary_point_inspection')
    assert all(record[k] == v for k, v in previous.items())


def test_corrected_resubmission_also_rejects_a_stale_farm(monkeypatch):
    import operator_workflow as workflow
    record = draft()
    record['boundary_version'] = 1
    conn, cur = connection(monkeypatch, [
        {'id': 3, 'owner_id': 10, 'farm_id': 7, 'status': 'needs_information',
         'version': 2, 'current_session_id': 41}, record, farm()])
    # resubmit uses the connection as a transaction context.
    transaction = MagicMock()
    transaction.__enter__.return_value = conn
    transaction.cursor.return_value = cur
    monkeypatch.setattr(db, 'get_conn', lambda: transaction)
    with pytest.raises(workflow.HTTPException) as error:
        workflow.resubmit(3, 10, 42, 2, 'Corrected boundary')
    assert error.value.status_code == 409
    assert not any('UPDATE analysis_sessions' in q for q, _ in cur.queries)
