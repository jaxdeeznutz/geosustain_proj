from unittest.mock import Mock
import pytest
from land_cover import interpret_cover, advisory_result, allow_estimated_analysis


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


@pytest.mark.parametrize('status', ['water', 'built_up', 'mixed'])
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


@pytest.mark.parametrize('provider_failed', [False, True])
def test_unknown_cover_continues_model_with_explicit_warning(monkeypatch, provider_failed):
    import fastapi_app as api
    unknown = interpret_cover({'total': 100, 'observed': 20})
    monkeypatch.setattr(api, 'screen_land_cover',
                        Mock(side_effect=RuntimeError('offline')) if provider_failed else Mock(return_value=unknown))
    monkeypatch.setattr(api, 'get_active_crop_keys', lambda: None)
    infer = Mock(return_value={'scoring_version': 'fixture', 'is_crop_recommended': True,
                              'predicted_crop': 'Rice', 'model_explanation': {'samples': [
                                  {'inputs': {'N': 80, 'P': 47, 'K': 50}}]}})
    monkeypatch.setattr(api, 'analyze_location', infer)
    result, _ = api.build_analysis_result({'lat': 7.29, 'lon': 125.62, 'place_name': 'Test fixture'})
    infer.assert_called_once()
    assert result['predicted_crop'] == 'Rice'
    assert result['land_cover']['status'] == 'unknown'
    assert result['land_cover']['verification_status'] == 'unverified'
    assert result['land_cover_notice'] in result['data_quality_warnings']
    assert result['nitrogen'] == 80
    assert result['land_cover']['observed_fraction'] == (None if provider_failed else .2)


def test_warning_policy_does_not_mutate_original_or_invent_verified_land():
    original = interpret_cover({})
    result = allow_estimated_analysis(original)
    assert original['allow_crops'] is False
    assert result['allow_crops'] is True
    assert result['status'] == 'unknown'
    assert result['verification_status'] == 'unverified'


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
