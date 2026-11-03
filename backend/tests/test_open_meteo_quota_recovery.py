from concurrent.futures import ThreadPoolExecutor
import json
from threading import Event, Lock
from unittest.mock import Mock

import pytest
import requests
import environmental_pipeline as pipeline
import open_meteo_http as meteo
import provider_cache as cache
import rainfallDatasets as env
from climate_contract import model_climate_inputs
from model_ranking import ModelRankingUnavailable


def reply(status=200, value=73, headers=None):
    response = requests.Response()
    response.status_code = status
    response.url = 'https://api.open-meteo.com/v1/forecast'
    response._content = json.dumps({'current': {'relative_humidity_2m': value}}).encode()
    response.headers.update(headers or {})
    return response


def test_429_cools_both_endpoints_and_respects_retry_after(monkeypatch):
    clock = [100.0]
    monkeypatch.setattr(meteo, 'monotonic', lambda: clock[0])
    get = Mock(side_effect=[reply(429, headers={'Retry-After': '120'}), reply()])
    monkeypatch.setattr(requests, 'get', get)
    assert meteo.get('https://api.open-meteo.com/v1/forecast').status_code == 429
    with pytest.raises(meteo.ProviderCooldown):
        meteo.get('https://archive-api.open-meteo.com/v1/archive')
    assert get.call_count == 1
    clock[0] = 221.0
    assert meteo.get('https://api.open-meteo.com/v1/forecast').status_code == 200
    assert get.call_count == 2


@pytest.mark.parametrize('retry_after', ['invalid', 'nan', '-20', '999999999999999'])
def test_retry_after_is_bounded_and_never_becomes_a_busy_loop(monkeypatch, retry_after):
    get = Mock(return_value=reply(429, headers={'Retry-After': retry_after}))
    monkeypatch.setattr(requests, 'get', get)
    meteo.get('https://api.open-meteo.com/v1/forecast')
    with pytest.raises(meteo.ProviderCooldown):
        meteo.get('https://api.open-meteo.com/v1/forecast')
    assert get.call_count == 1


def test_waiting_polygon_workers_recheck_cooldown_before_sending(monkeypatch):
    release = Event()
    entered = Event()
    lock = Lock()
    count = [0]

    def provider(*args, **kwargs):
        with lock:
            count[0] += 1
            if count[0] == 2:
                entered.set()
        assert release.wait(3)
        return reply(429)

    def call():
        try:
            return meteo.get('https://api.open-meteo.com/v1/forecast').status_code
        except meteo.ProviderCooldown:
            return 'cooldown'

    monkeypatch.setattr(requests, 'get', provider)
    with ThreadPoolExecutor(max_workers=9) as workers:
        futures = [workers.submit(call) for _ in range(9)]
        assert entered.wait(3)
        release.set()
        results = [future.result() for future in futures]
    assert count[0] == 2
    assert results.count('cooldown') == 7


def test_humidity_reuses_only_fresh_exact_coordinate_observations(monkeypatch):
    clock = [0.0]
    monkeypatch.setattr(cache, 'monotonic', lambda: clock[0])
    get = Mock(return_value=reply(value=73))
    monkeypatch.setattr(requests, 'get', get)
    weather = (80, '', 0, 0, 'fallback_default')
    first = pipeline.current_humidity(weather, 7.3, 125.6)
    first['value'] = 99
    assert pipeline.current_humidity(weather, 7.3, 125.6)['value'] == 73
    assert get.call_count == 1
    pipeline.current_humidity(weather, 7.300001, 125.6)
    assert get.call_count == 2
    clock[0] = 301
    pipeline.current_humidity(weather, 7.3, 125.6)
    assert get.call_count == 3


def test_rate_limit_never_fills_missing_humidity_or_bypasses_model_gate(monkeypatch):
    get = Mock(return_value=reply(429))
    monkeypatch.setattr(requests, 'get', get)
    missing = pipeline.current_humidity((80, '', 0, 0, 'fallback_default'), 7.3, 125.6)
    assert missing['value'] is None
    assert missing['quality'] == 'unavailable'
    # A second sample must not make another request or inherit the sentinel 80.
    other = pipeline.current_humidity((80, '', 0, 0, 'fallback_default'), 7.3001, 125.6)
    assert other['value'] is None
    assert get.call_count == 1
    measurements = {
        'temperature': {'value': 27, 'unit': 'C', 'period': 'annual_mean', 'quality': 'modelled'},
        'rainfall_recent': {'value': 110, 'unit': 'mm', 'period': 'rolling_30_days', 'quality': 'modelled'},
        'humidity_current': missing,
    }
    with pytest.raises(ModelRankingUnavailable, match='humidity'):
        model_climate_inputs(measurements)


def test_zero_humidity_is_valid_but_missing_results_are_not_cached(monkeypatch):
    get = Mock(side_effect=[reply(value=None), reply(value=0)])
    monkeypatch.setattr(requests, 'get', get)
    weather = (80, '', 0, 0, 'fallback_default')
    assert pipeline.current_humidity(weather, 7.3, 125.6)['value'] is None
    assert pipeline.current_humidity(weather, 7.3, 125.6)['value'] == 0
    assert pipeline.current_humidity(weather, 7.3, 125.6)['value'] == 0
    assert get.call_count == 2


def test_unconfigured_openweather_does_not_send_an_empty_api_key(monkeypatch):
    monkeypatch.setattr(env, 'OPENWEATHER_KEY', '')
    get = Mock(side_effect=AssertionError('No unconfigured request'))
    monkeypatch.setattr(requests, 'get', get)
    assert env.get_live_weather(7.3, 125.6)[4] == 'fallback_default'
    get.assert_not_called()


def test_rainfall_stops_retrying_a_throttled_provider(monkeypatch):
    get = Mock(return_value=reply(429))
    monkeypatch.setattr(requests, 'get', get)
    assert env._open_meteo_recent_monthly_rainfall(7.3, 125.6) is None
    assert get.call_count == 1
