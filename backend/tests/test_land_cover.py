from unittest.mock import Mock
import pytest
from land_cover import interpret_cover, advisory_result
from model_ranking import ModelRankingUnavailable


@pytest.mark.parametrize('water,built,observed,status', [
    (80, 0, 100, 'water'), (0, 80, 100, 'built_up'),
    (6, 5, 100, 'mixed'), (0, 0, 20, 'unknown'), (0, 0, 100, 'eligible'),
    (50, 0, 100, 'water'), (0, 50, 100, 'built_up'), (0, 10, 100, 'mixed')])
def test_screening_policy(water, built, observed, status):
    screen = interpret_cover({'total': 100, 'water': water, 'built': built, 'observed': observed})
    assert screen['status'] == status
    assert screen['allow_crops'] == (status == 'eligible')
    if status != 'eligible':
        result = advisory_result(screen)
        assert result['is_crop_recommended'] is False
        assert result['top_crop_recommendations'] == []
        assert result['crop_compatibility_pct'] is None


def test_no_coverage_is_not_treated_as_farmland():
    assert interpret_cover({})['allow_crops'] is False


@pytest.mark.parametrize('status', ['water', 'built_up', 'mixed', 'unknown'])
def test_api_preflight_prevents_model_calls_and_keeps_boundary(monkeypatch, status):
    import fastapi_app as api
    from test_mobile_workflow import RING
    screen = {'allow_crops': False, 'status': status, 'message': 'Refine the boundary', 'limitation': 'Satellite screening'}
    check = Mock(return_value=screen)
    infer = Mock(side_effect=AssertionError('Model must not run on blocked land'))
    monkeypatch.setattr(api, 'screen_land_cover', check)
    monkeypatch.setattr(api, 'analyze_location', infer)
    monkeypatch.setattr(api, 'get_active_crop_keys', lambda: None)
    result, _ = api.build_analysis_result({'polygon': RING, 'place_name': 'Test boundary'})
    assert result['selected_polygon']
    assert result['land_cover']['status'] == status
    assert result['is_crop_recommended'] is False
    assert result['top_crop_recommendations'] == []
    assert len(check.call_args.args[2]) >= 4
    infer.assert_not_called()


def test_provider_failure_does_not_silently_enable_crops(monkeypatch):
    import fastapi_app as api
    monkeypatch.setattr(api, 'screen_land_cover', Mock(side_effect=RuntimeError('offline')))
    monkeypatch.setattr(api, 'get_active_crop_keys', lambda: None)
    infer = Mock()
    monkeypatch.setattr(api, 'analyze_location', infer)
    with pytest.raises(ModelRankingUnavailable, match='Land-cover verification'):
        api.build_analysis_result({'lat': 7.29, 'lon': 125.62})
    infer.assert_not_called()
