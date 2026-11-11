from unittest.mock import Mock

import fastapi_app as api
import operator_workflow as workflow
import database as db


def test_only_analyst_can_save_a_submitted_case_report(client, monkeypatch):
    detail = Mock(return_value={'case': {'id': 12, 'current_session_id': 41}})
    save = Mock(return_value={
        'id': 7,
        'user_id': 20,
        'session_id': 41,
        'report_title': 'GeoSustain Review Report - Case #12',
    })
    monkeypatch.setattr(workflow, 'detail', detail)
    monkeypatch.setattr(db, 'create_report_for_reviewer', save)

    assert client.post('/api/operator/cases/12/report').status_code == 403
    detail.assert_not_called()
    save.assert_not_called()

    api.app.dependency_overrides[api.get_api_user] = lambda: {
        'id': 20,
        'role': 'agricultural_planning_analyst',
        'is_active': True,
    }
    response = client.post('/api/operator/cases/12/report')
    assert response.status_code == 200
    assert response.json()['session_id'] == 41
    detail.assert_called_once_with(12)
    save.assert_called_once_with(20, 12)
