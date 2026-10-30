"""Production datetime/JSONB crash and CORS regression tests; no live services."""
import json
from contextlib import nullcontext
from datetime import datetime, date, timezone
from decimal import Decimal
from unittest.mock import Mock

import numpy as np
import pandas as pd
import pytest
from fastapi.testclient import TestClient
from psycopg2.extras import Json

import fastapi_app as api
import database as db
from http_config import CorsFastAPI, frontend_origins
from json_safe import json_safe
from test_mobile_workflow import CaptureCursor, RING

ORIGIN = 'https://geosustain.vercel.app'


def test_json_safe_dates_scientific_values_and_missing_data():
    timestamp = datetime(2026, 10, 14, 9, 30, tzinfo=timezone.utc)
    raw = {'fetched_at': timestamp, 'date': date(2026, 10, 14),
           'measurements': [np.float32(6.5), np.int64(9), np.bool_(True),
                            np.array([1, np.nan, np.inf]), Decimal('2.5'),
                            pd.NA, pd.NaT, pd.Timestamp(timestamp), np.datetime64('NaT')]}
    result = json_safe(raw)
    assert result['fetched_at'] == '2026-10-14T09:30:00+00:00'
    assert result['measurements'] == [6.5, 9, True, [1.0, None, None], 2.5,
                                      None, None, timestamp.isoformat(), None]
    json.dumps(result, allow_nan=False)
    assert raw['fetched_at'] is timestamp
    with pytest.raises(TypeError, match='Unsupported analysis JSON type'):
        json_safe(object())


def test_actual_save_adapter_and_post_handle_cached_baseline(monkeypatch):
    timestamp = datetime(2026, 10, 14, 9, 30, tzinfo=timezone.utc)
    result = {'lat': np.float64(7.29), 'lon': 125.62,
              'selected_polygon': RING, 'ndvi': np.float32(.5),
              'historical_climate_baseline': {'fetched_at': timestamp},
              'data_quality': {'missing': np.nan}}
    snapshots = []

    class SerializingCursor(CaptureCursor):
        def execute(self, query, params=()):
            super().execute(query, params)
            for param in params:
                if isinstance(param, Json):
                    # Exercise psycopg2's real JSON adapter, which crashed on Render.
                    param.getquoted()
                    json.dumps(param.adapted, allow_nan=False)
            if 'INSERT INTO analysis_sessions' in query:
                snapshots.append(params[20].adapted)

    cursor = SerializingCursor([None, {'boundary_version': 1}, {'id': 42}])
    conn = Mock()
    conn.cursor.return_value = cursor
    monkeypatch.setattr(db, 'get_conn', lambda: conn)
    monkeypatch.setattr(api, 'init_db', lambda: None)
    monkeypatch.setattr(api, 'analysis_request_lock', lambda *args: nullcontext(True))
    monkeypatch.setattr(api, 'find_analysis_request', lambda *args: None)
    monkeypatch.setattr(api, 'get_farm_parcel', lambda *args: {
        'id': 2, 'farm_name': 'Farm', 'polygon': RING, 'boundary_version': 1})
    monkeypatch.setattr(api, 'build_analysis_result', lambda **kw: (result, 'selected-polygon'))
    monkeypatch.setattr(api, 'get_user_analysis', lambda *args: {
        **snapshots[0], 'session_id': 42, 'analysis_status': 'completed', 'created_at': timestamp})
    api.app.dependency_overrides[api.get_api_user] = lambda: {'id': 2, 'role': 'farmer'}
    try:
        with TestClient(api.app) as client:
            response = client.post('/api/mobile/analysis', json={'farm_id': 2},
                                   headers={'Origin': ORIGIN, 'Idempotency-Key': 'regression-save-42'})
    finally:
        api.app.dependency_overrides.clear()
    assert response.status_code == 200, response.text
    assert response.headers['access-control-allow-origin'] == ORIGIN
    assert response.json()['historical_climate_baseline']['fetched_at'] == timestamp.isoformat()
    assert response.json()['farm_id'] == 2
    assert snapshots[0]['data_quality']['missing'] is None
    conn.commit.assert_called_once()
    conn.close.assert_called_once()


def test_failed_serialization_never_commits(monkeypatch):
    connect = Mock()
    monkeypatch.setattr(db, 'get_conn', connect)
    with pytest.raises(TypeError):
        db.save_analysis_session(2, {'lat': 7.29, 'lon': 125.62, 'bad': object()}, 'point')
    connect.assert_not_called()


@pytest.mark.parametrize('origin', [ORIGIN, 'http://localhost:3000', 'http://localhost:5173', 'http://localhost:8080'])
def test_preflight_allows_trusted_origin(monkeypatch, origin):
    monkeypatch.delenv('FRONTEND_ORIGINS', raising=False)
    with TestClient(CorsFastAPI()) as client:
        response = client.options('/api/mobile/analysis', headers={
            'Origin': origin, 'Access-Control-Request-Method': 'POST',
            'Access-Control-Request-Headers': 'authorization,content-type,idempotency-key'})
    assert response.status_code == 200
    assert response.headers['access-control-allow-origin'] == origin
    assert response.headers['access-control-allow-credentials'] == 'true'


def test_untrusted_preview_is_not_implicitly_allowed(monkeypatch):
    monkeypatch.delenv('FRONTEND_ORIGINS', raising=False)
    with TestClient(CorsFastAPI()) as client:
        response = client.options('/api/mobile/analysis', headers={
            'Origin': 'https://attacker.vercel.app', 'Access-Control-Request-Method': 'POST'})
    assert response.status_code == 400
    assert 'access-control-allow-origin' not in response.headers


def test_unhandled_500_including_dependency_has_cors(monkeypatch):
    monkeypatch.setattr(api, 'init_db', lambda: None)
    def crash():
        raise TypeError('private failure details')
    api.app.dependency_overrides[api.get_api_user] = crash
    try:
        with TestClient(api.app, raise_server_exceptions=False) as client:
            response = client.post('/api/mobile/analysis', json={'farm_id': 2}, headers={'Origin': ORIGIN})
    finally:
        api.app.dependency_overrides.clear()
    assert response.status_code == 500
    assert response.headers['access-control-allow-origin'] == ORIGIN
    assert 'private' not in response.text
    assert response.json()['detail']


def test_origins_normalized_and_explicit_previews_supported(monkeypatch):
    monkeypatch.setenv('FRONTEND_ORIGINS', f' {ORIGIN}/, https://geosustain-trusted-preview.vercel.app ')
    assert frontend_origins() == [ORIGIN, 'https://geosustain-trusted-preview.vercel.app']


@pytest.mark.parametrize('value', ['*', 'https://example.org/path', 'https://user:secret@example.org', ''])
def test_invalid_origins_fail_configuration(monkeypatch, value):
    monkeypatch.setenv('FRONTEND_ORIGINS', value)
    with pytest.raises(ValueError):
        frontend_origins()
