from datetime import datetime, timedelta
from unittest.mock import Mock
import pytest
import requests
import environmental_pipeline as pipeline
import rainfallDatasets as env


def test_humidity_backup_is_coordinate_specific(monkeypatch):
    response = Mock()
    response.json.return_value = {'current': {'relative_humidity_2m': 73}}
    get = Mock(return_value=response)
    monkeypatch.setattr(requests, 'get', get)
    result = pipeline.current_humidity((80, '', 0, 0, 'fallback_default'), 7.3, 125.6)
    assert result['value'] == 73
    assert result['quality'] == 'modelled'
    assert 'Open-Meteo' in result['source']
    assert get.call_args.kwargs['params']['latitude'] == 7.3


@pytest.mark.parametrize('value', [None, -1, 101, float('nan')])
def test_invalid_humidity_never_becomes_default(monkeypatch, value):
    response = Mock()
    response.json.return_value = {'current': {'relative_humidity_2m': value}}
    monkeypatch.setattr(requests, 'get', Mock(return_value=response))
    assert pipeline.current_humidity((80, '', 0, 0, 'fallback_default'), 7.3, 125.6)['value'] is None


def test_primary_humidity_avoids_backup(monkeypatch):
    get = Mock(side_effect=AssertionError('No backup needed'))
    monkeypatch.setattr(requests, 'get', get)
    assert pipeline.current_humidity((75, '', 0, 0, 'measured'), 7.3, 125.6)['value'] == 75
    get.assert_not_called()


def rainfall_response(missing=False):
    end = datetime.utcnow().date() - timedelta(days=1)
    dates = [(end-timedelta(days=29-i)).isoformat() for i in range(30)]
    values = [1.0]*30
    if missing: values[10] = None
    # Include today: forecast must not replace a completed day.
    dates.append((end+timedelta(days=1)).isoformat())
    values.append(999)
    return Mock(status_code=200, json=lambda: {'daily': {'time': dates, 'precipitation_sum': values}})


def test_rainfall_excludes_forecast_day(monkeypatch):
    monkeypatch.setattr(env.requests, 'get', Mock(return_value=rainfall_response()))
    assert env._open_meteo_recent_monthly_rainfall(7.3, 125.6) == 30


def test_partial_rainfall_is_not_full_month(monkeypatch):
    monkeypatch.setattr(env.requests, 'get', Mock(return_value=rainfall_response(True)))
    assert env._open_meteo_recent_monthly_rainfall(7.3, 125.6) is None


def test_polygon_preserves_missing_input_reason(monkeypatch):
    from test_regressions import api
    from test_mobile_workflow import RING
    from model_ranking import ModelRankingUnavailable
    monkeypatch.setattr(api, 'get_active_crop_keys', lambda: None)
    monkeypatch.setattr(api, 'analyze_location', Mock(side_effect=ModelRankingUnavailable('Required model inputs unavailable: humidity.')))
    with pytest.raises(ModelRankingUnavailable, match='humidity'):
        api.build_analysis_result(body={'polygon': RING})
