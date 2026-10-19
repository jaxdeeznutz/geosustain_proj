from unittest.mock import Mock
import pytest
import provider_cache as cache


@pytest.fixture(autouse=True)
def reset_cache():
    cache._values.clear()
    yield
    cache._values.clear()


def test_reuses_success_without_sharing_mutable_data():
    provider = Mock(return_value=(6.2, 'measured', {'source': 'test'}))
    first = cache.retrieve('soil_ph', provider, 7.1, 125.5, 60)
    first[2]['source'] = 'changed'
    second = cache.retrieve('soil_ph', provider, 7.1, 125.5, 60)
    assert second[2]['source'] == 'test'
    assert provider.call_count == 1


def test_distinct_coordinates_are_not_merged():
    provider = Mock(return_value=(6.2, 'measured', 'test'))
    cache.retrieve('soil_ph', provider, 7.10001, 125.5, 60)
    cache.retrieve('soil_ph', provider, 7.10002, 125.5, 60)
    assert provider.call_count == 2


def test_expired_values_are_refetched(monkeypatch):
    clock = [0]
    monkeypatch.setattr(cache, 'monotonic', lambda: clock[0])
    provider = Mock(return_value=(6.2, 'measured', 'test'))
    cache.retrieve('soil_ph', provider, 7, 125, 60)
    clock[0] = 61
    cache.retrieve('soil_ph', provider, 7, 125, 60)
    assert provider.call_count == 2


def test_fallbacks_and_failures_are_not_cached():
    provider = Mock(side_effect=[(6, 'fallback_default', 'test'), RuntimeError('offline'), (6.2, 'measured', 'test')])
    cache.retrieve('soil_ph', provider, 7, 125, 60)
    with pytest.raises(RuntimeError):
        cache.retrieve('soil_ph', provider, 7, 125, 60)
    assert cache.retrieve('soil_ph', provider, 7, 125, 60)[0] == 6.2
    assert provider.call_count == 3
