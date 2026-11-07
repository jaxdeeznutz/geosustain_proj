from unittest.mock import Mock
import pytest
import fastapi_app as api
import recommendation_patterns as patterns


def test_installed_model_identity_matches_seven_classes():
    version, classes = patterns.model_identity()
    assert len(version) == 64
    assert set(classes) == {'banana','cacao','coconut','durian','mango','rice','rubber'}


def test_model_scopes_and_access_are_explicit(client, monkeypatch):
    fetch = Mock(return_value={'model_scope': 'current', 'analysis_count': 0})
    monkeypatch.setattr(patterns, 'patterns', fetch)
    assert client.get('/api/web/recommendation-patterns?user_id=999').status_code == 200
    fetch.assert_called_once_with(10, model_scope='current')
    assert client.get('/api/operator/recommendation-patterns').status_code == 403
    api.app.dependency_overrides[api.get_api_user] = lambda: {'id': 20, 'role': 'agricultural_planning_analyst', 'is_active': True}
    fetch.reset_mock()
    assert client.get('/api/operator/recommendation-patterns?model_scope=all').status_code == 200
    fetch.assert_called_once_with(20, submitted=True, model_scope='all')
    assert client.get('/api/operator/recommendation-patterns?model_scope=bad').status_code == 422


def test_invalid_scope_is_rejected_before_database_access():
    with pytest.raises(ValueError, match='scope'):
        patterns.patterns(10, model_scope='invalid')
