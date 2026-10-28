"""Analysis contract regressions; all provider/storage effects are explicit doubles."""
from copy import deepcopy
from unittest.mock import Mock
import pytest
from analysis_coverage import require_point_coverage, CoverageUnavailable
from city_boundary import reference


def test_point_screening_does_not_create_a_farm_or_soil_match():
    coverage, soil = require_point_coverage(7.29, 125.62)
    assert coverage['can_analyze'] and coverage['geometry_type'] == 'Point'
    assert coverage['analysis_mode'] == 'legacy_model_estimates'
    assert not coverage['supported'] and coverage['matches'] == []
    assert not soil['observations'] and coverage['nutrient_source'] is None


def test_point_rejects_outside_and_reference_edge():
    x, y = reference()['geometry']['coordinates'][0][0]
    for lat, lon in [(7.29, 125.53), (y, x), (float('nan'), 125.62)]:
        with pytest.raises(CoverageUnavailable):
            require_point_coverage(lat, lon)


@pytest.mark.parametrize('mode', ['body', 'query'])
def test_builder_accepts_inside_point_without_fabricating_polygon(monkeypatch, mode):
    import fastapi_app as api
    infer = Mock(return_value={'scoring_version': 'explicit-fixture', 'crop_assessments': []})
    monkeypatch.setattr(api, 'analyze_location', infer)
    monkeypatch.setattr(api, 'get_active_crop_keys', lambda: ['rice'])
    monkeypatch.setattr(api, 'reverse_geocode_place', lambda *args: 'Explicit point fixture')
    params = {'lat': 7.29, 'lon': 125.62}
    result, source = api.build_analysis_result(**{('body' if mode == 'body' else 'query_args'): params})
    infer.assert_called_once_with(7.29, 125.62, ['rice'])
    assert source == 'query-point' and result['selected_polygon'] == []
    assert result['selection_type'] == 'Point location'
    assert 'area_hectares' not in result
    assert 'not a farm centroid' in result['centroid_method']
    assert result['analysis_coverage']['geometry_type'] == 'Point'


def test_preliminary_contract_cannot_export_complete_recommendation():
    from suitability import attach_assessment, mark_preliminary
    def measured(value, unit, period):
        return {'value': value, 'unit': unit, 'period': period, 'quality': 'measured', 'source': 'Explicit test'}
    inputs = {'temperature': measured(27, 'C', 'annual_mean'),
              'rainfall': measured(1800, 'mm/year', 'annual_mean_total'),
              'soil_ph': measured(6, 'pH', 'soil_surface')}
    original = attach_assessment({}, inputs, ['rice'])
    assert original['best_crop'] and original['is_crop_recommended']
    result = mark_preliminary(deepcopy(original))
    assert result['best_crop'] is None and result['predicted_crop'] is None
    assert result['crop_compatibility_pct'] is None and not result['is_crop_recommended']
    assert result['top_crop_recommendations'] == [] and result['alternative_crops'] == []
    rice = next(c for c in result['crop_assessments'] if c['crop'] == 'Rice')
    assert rice['reference_condition_index'] == 100 and rice['compatibility_pct'] is None
    assert rice['rank'] is None and rice['factors'][0]['score'] == 100
    assert original['best_crop'] is not None
