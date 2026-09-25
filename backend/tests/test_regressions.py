"""Offline regression checks: no production database or provider requests."""
from copy import deepcopy
from datetime import datetime, timedelta
from pathlib import Path
import sys
from unittest.mock import Mock

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import fastapi_app as api
import rainfallDatasets as engine


@pytest.fixture
def weather_payload():
    now = datetime(2026, 9, 23, 23, 15)
    days = [(now - timedelta(days=i)).date().isoformat() for i in range(30, -2, -1)]
    return {
        'current': {'time': now.isoformat(), 'temperature_2m': 28, 'wind_speed_10m': 36,
                    'weather_code': 0, 'relative_humidity_2m': 80},
        'daily': {'time': days, 'precipitation_sum': [1] * 30 + [7, 90]},
        'hourly': {
            'time': ['2026-08-24T00:00', '2026-09-23T23:00'] +
                    [f'2026-09-24T{i:02d}:00' for i in range(6)],
            'precipitation': [100, 100] + [1] * 6,
            'precipitation_probability': [99, 99] + [55] * 6,
            'wind_speed_10m': [100, 100] + [36] * 6,
            'temperature_2m': [50, 50] + [28] * 6,
            'weather_code': [95, 95] + [61] * 6,
        },
    }


def test_weather_uses_upcoming_hours_and_correct_days(monkeypatch, weather_payload):
    response = Mock()
    response.json.return_value = weather_payload
    get = Mock(return_value=response)
    monkeypatch.setattr(api.requests, 'get', get)
    data = api.fetch_open_meteo_weather(7.3, 125.6)
    assert data['rain_next_6h_mm'] == 6
    assert data['rain_next_3h_mm'] == 3
    assert data['rain_probability_next_6h'] == 55
    assert data['rainfall_today_mm'] == 7
    assert data['rainfall_30d_mm'] == 30
    assert data['wind_speed_ms'] == 10
    assert data['wind_speed_kmh'] == 36
    assert data['weather_codes_next_6h'] == [61] * 6
    assert get.call_args.kwargs['params']['forecast_days'] == 2
    response.raise_for_status.assert_called_once()


def test_missing_rainfall_is_not_reported_as_dry_weather(monkeypatch, weather_payload):
    weather_payload['daily']['precipitation_sum'][0] = None
    monkeypatch.setattr(api.requests, 'get', lambda *a, **k: Mock(json=lambda: weather_payload))
    assert api.fetch_open_meteo_weather(7.3, 125.6)['rainfall_30d_mm'] is None


def test_empty_provider_payload_is_not_a_success(monkeypatch):
    monkeypatch.setattr(api.requests, 'get', lambda *a, **k: Mock(json=lambda: {}))
    with pytest.raises(ValueError):
        api.fetch_open_meteo_weather(7.3, 125.6)


def test_cached_analysis_is_not_mutated_by_season_or_session_data(monkeypatch):
    import time
    original = {'is_crop_recommended': True, 'top_crop_recommendations': [
        {'crop': 'Cacao', 'compatibility_pct': 90}], 'xai_explanation': {}}
    monkeypatch.setattr(engine, 'ANALYSIS_CACHE', {
        (7.3, 125.6, None): {'ts': time.time(), 'data': deepcopy(original)}})
    first = engine.analyze_location(7.3, 125.6)
    api.apply_local_seasonality(first, 1)
    first['session_id'] = 42
    second = engine.analyze_location(7.3, 125.6)
    assert second == original
    second['top_crop_recommendations'][0]['compatibility_pct'] = 0
    assert engine.analyze_location(7.3, 125.6) == original


def test_model_inference_uses_original_feature_contract():
    result = engine.get_ai_prediction(80, 47, 50, 27.5, 80, 6, 105, .6, 25, 2)
    assert len(result) == 2
    assert isinstance(result[1], list)


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setattr(api, 'init_db', lambda: None)
    with TestClient(api.app) as client:
        yield client
    api.app.dependency_overrides.clear()


def test_health_and_protected_routes(client):
    assert client.get('/health').status_code == 200
    assert client.get('/api/mobile/me').status_code == 401
    assert client.get('/api/planner/queue').status_code == 401


def test_farmer_cannot_use_admin_or_planner_endpoints(client):
    api.app.dependency_overrides[api.get_api_user] = lambda: {'id': 10, 'role': 'farmer'}
    assert client.get('/api/admin/users').status_code == 403
    assert client.get('/api/planner/queue').status_code == 403


def test_invalid_month_rejected_before_analysis(client):
    api.app.dependency_overrides[api.get_api_user] = lambda: {'id': 10, 'role': 'farmer'}
    assert client.post('/api/mobile/analysis', json={'lat': 7.3, 'lon': 125.6,
                                                  'intended_planting_month': 13}).status_code == 422


def test_saved_session_survives_optional_farm_attach_failure(client, monkeypatch):
    api.app.dependency_overrides[api.get_api_user] = lambda: {'id': 10, 'role': 'farmer'}
    monkeypatch.setattr(api, 'build_analysis_result', lambda **kw: ({'crop': 'Cacao'}, 'selected-polygon'))
    monkeypatch.setattr(api, 'save_analysis_session', lambda *a: 42)
    monkeypatch.setattr(api, 'attach_analysis_to_farm', Mock(side_effect=ValueError('Not your farm')))
    response = client.post('/api/mobile/analysis', json={'lat': 7.3, 'lon': 125.6, 'farm_id': 7})
    assert response.status_code == 200
    assert response.json()['session_id'] == 42
    assert 'farm_id' not in response.json()


def test_weather_failure_returns_502(client, monkeypatch):
    monkeypatch.setattr(api, 'fetch_open_meteo_weather', Mock(side_effect=TimeoutError()))
    assert client.get('/api/mobile/weather?lat=7.3&lon=125.6').status_code == 502


def test_profile_update_drops_privileged_role():
    body = api.ProfileUpdateBody(username='farmer', role='super_admin')
    assert 'role' not in body.model_dump()
