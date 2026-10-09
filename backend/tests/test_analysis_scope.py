"""Request recovery and farm scoping without live providers or user data."""
from contextlib import nullcontext
from unittest.mock import Mock

from test_mobile_workflow import client, RING  # noqa: F401
from test_regressions import api
from geometry import normalize_polygon, polygon_area_m2


def test_inflight_retry_does_not_start_inference(client, monkeypatch):
    monkeypatch.setattr(api, 'analysis_request_lock', lambda *args: nullcontext(False))
    build = Mock()
    monkeypatch.setattr(api, 'build_analysis_result', build)
    response = client.post('/api/mobile/analysis', json={'polygon': RING}, headers={'Idempotency-Key': 'retry'})
    assert response.status_code == 202
    assert response.json()['status'] == 'processing'
    build.assert_not_called()


def test_request_status_is_scoped_to_authenticated_user(client, monkeypatch):
    status = Mock(return_value={'status': 'not_found'})
    monkeypatch.setattr(api, 'analysis_request_status', status)
    assert client.get('/api/mobile/analysis-requests/retry').json() == {'status': 'not_found'}
    status.assert_called_once_with(10, 'retry')


def test_farm_history_uses_owned_farm_and_sql_filter(client, monkeypatch):
    farm = Mock(return_value={'id': 7})
    history = Mock(return_value=[])
    monkeypatch.setattr(api, 'get_farm_parcel', farm)
    monkeypatch.setattr(api, 'get_user_history', history)
    response = client.get('/api/mobile/history?farm_id=7')
    assert response.status_code == 200
    farm.assert_called_once_with(10, 7)
    assert history.call_args.kwargs['farm_id'] == 7
    assert history.call_args.args[0] == 10
    farm.return_value = None
    history.reset_mock()
    assert client.get('/api/mobile/history?farm_id=8').status_code == 404
    history.assert_not_called()


def test_engine_failure_never_saves_completed_record(client, monkeypatch):
    monkeypatch.setattr(api, 'build_analysis_result', Mock(side_effect=RuntimeError('provider failed')))
    save = Mock()
    monkeypatch.setattr(api, 'save_analysis_session', save)
    response = client.post('/api/mobile/analysis', json={'polygon': RING})
    assert response.status_code == 503
    assert 'provider failed' not in response.text
    save.assert_not_called()


def test_twenty_square_metre_boundary_is_above_existing_minimum():
    ring = normalize_polygon([
        {'lat': 7.3, 'lng': 125.6},
        {'lat': 7.3, 'lng': 125.600045},
        {'lat': 7.300036, 'lng': 125.600045},
        {'lat': 7.300036, 'lng': 125.6},
    ])
    assert 19 < polygon_area_m2(ring) < 21
