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
    from test_cagro_soil import square
    RING = square(7.39242,125.62293)
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
        api.build_analysis_result({'polygon': __import__('test_cagro_soil').square(7.39242,125.62293)})
    infer.assert_not_called()


@pytest.mark.parametrize('stats', [
    {'total': -1}, {'total': float('nan')},
    {'total': 100, 'observed': 101},
    {'total': 100, 'observed': 10, 'built': 90},
])
def test_invalid_provider_areas_never_allow_crops(stats):
    with pytest.raises(ValueError):
        interpret_cover(stats)


def test_null_reducer_values_are_unknown():
    assert interpret_cover({'total': None, 'observed': None, 'water': None, 'built': None})['status'] == 'unknown'


def test_uncertain_new_observation_does_not_erase_older_confident_land_cover():
    from land_cover import confident_observation

    class Pixel:
        def __init__(self, bands, valid=True):
            self.bands, self.valid = bands, valid
        def select(self, names):
            names = [names] if isinstance(names, str) else names
            return Pixel({name: self.bands[name] for name in names}, self.valid)
        def reduce(self, _):
            return Pixel({'max': max(self.bands.values())}, self.valid)
        def gte(self, threshold):
            return Pixel({k: int(v >= threshold) for k, v in self.bands.items()}, self.valid)
        def eq(self, target):
            return Pixel({k: int(v == target) for k, v in self.bands.items()}, self.valid)
        def rename(self, name):
            return Pixel({name: next(iter(self.bands.values()))}, self.valid)
        def addBands(self, other):
            return Pixel({**self.bands, **other.bands}, self.valid)
        def toByte(self):
            return self
        def updateMask(self, mask):
            return Pixel(self.bands, self.valid and bool(next(iter(mask.bands.values()))))

    from land_cover import BANDS
    ee = Mock()
    def observation(label, probability):
        bands = {b: (probability if i == label else (1-probability)/8) for i, b in enumerate(BANDS)}
        return confident_observation(Pixel({**bands, 'label': label}), ee)
    old = observation(6, .9)
    uncertain = observation(4, .4)
    assert old.valid and old.bands == {'water': 0, 'built': 1, 'observed': 1}
    assert not uncertain.valid
    # Earth Engine mosaic selects the latest unmasked pixel.
    selected = next(p for p in reversed([old, uncertain]) if p.valid)
    assert selected.bands['built'] == 1
    newer = observation(0, .8)
    selected = next(p for p in reversed([old, uncertain, newer]) if p.valid)
    assert selected.bands == {'water': 1, 'built': 0, 'observed': 1}
