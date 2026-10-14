"""Exercise real EE deadline setup without contacting Google or using secrets."""
from types import SimpleNamespace
from unittest.mock import Mock
from concurrent.futures import ThreadPoolExecutor

import pytest
import rainfallDatasets as engine


@pytest.fixture
def cold_engine(monkeypatch):
    monkeypatch.setattr(engine, '_EE_INITIALIZED', False)
    monkeypatch.setattr(engine, '_EE_RETRY_AFTER', 0.0)
    monkeypatch.setattr(engine, '_EE_INITIALIZATION_ERROR', None)
    # The real installed EE code asserts that this session exists when
    # setDeadline rebuilds its resource. Only discovery/network is mocked.
    state = SimpleNamespace(
        requests_session=None, deadline_ms=0, max_retries=5,
        cloud_api_base_url='https://earthengine.googleapis.com',
        credentials=None, cloud_api_key=None, http_transport=None,
    )
    monkeypatch.setattr(engine.ee.data, '_get_state', lambda: state)
    discovery = Mock(return_value=object())
    monkeypatch.setattr(engine.ee.data._cloud_api_utils, 'build_cloud_resource', discovery)
    def initialize():
        state.requests_session = object()
    init = Mock(side_effect=initialize)
    monkeypatch.setattr(engine, 'initialize_earth_engine', init)
    return state, init, discovery


def test_deadline_on_uninitialized_ee_reproduces_render_assertion(cold_engine):
    with pytest.raises(AssertionError):
        engine.ee.data.setDeadline(30000)


def test_cold_start_initializes_before_deadline_and_initializes_once(cold_engine):
    state, init, discovery = cold_engine
    # Polygon workers can arrive concurrently; only one initializes the client.
    with ThreadPoolExecutor(max_workers=4) as pool:
        assert all(pool.map(lambda _: engine.ensure_earth_engine_initialized(), range(9)))
    init.assert_called_once()
    assert state.deadline_ms == 30000
    assert state.max_retries == 1
    assert discovery.call_count == 2  # regular and raw EE Cloud API clients
    assert all(call.kwargs['timeout'] == 30 for call in discovery.call_args_list)
    assert engine._EE_INITIALIZED is True


def test_failed_auth_keeps_retry_cooldown_without_false_success(cold_engine):
    state, init, discovery = cold_engine
    init.side_effect = RuntimeError('authentication unavailable')
    with pytest.raises(RuntimeError, match='authentication unavailable'):
        engine.ensure_earth_engine_initialized()
    assert engine._EE_INITIALIZED is False
    assert isinstance(engine._EE_INITIALIZATION_ERROR, RuntimeError)
    with pytest.raises(RuntimeError, match='temporarily unavailable'):
        engine.ensure_earth_engine_initialized()
    init.assert_called_once()
    discovery.assert_not_called()
