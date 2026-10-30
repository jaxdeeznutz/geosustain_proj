"""Independent analytic grid references: exact areas, not the tested reducer."""
from copy import deepcopy
import math
from unittest.mock import Mock

import pytest

import spatial_analysis as spatial


def raster(values):
    return {'crs': 'EPSG:3857', 'width': len(values[0]), 'height': len(values),
            'transform': [1, 0, 0, 0, -1, len(values)], 'values': values}


@pytest.fixture(autouse=True)
def cache_isolation():
    spatial._CACHE.clear()
    yield
    spatial._CACHE.clear()


def test_full_four_cell_reference_and_population_stddev():
    # Four unit squares, equal area: known 1,2,3,4 distribution.
    ring = [(0, 0), (2, 0), (2, 2), (0, 2), (0, 0)]
    stats, cells = spatial.reduce_grid_xy(ring, raster([[1, 2], [3, 4]]))
    assert stats['valid_pixel_count'] == stats['intersecting_pixel_count'] == 4
    assert stats['minimum'] == 1 and stats['maximum'] == 4
    assert stats['mean'] == stats['median'] == 2.5
    assert stats['standard_deviation'] == pytest.approx(math.sqrt(1.25))
    assert stats['valid_area_fraction'] == stats['grid_extent_area_fraction'] == 1
    assert sum(c['intersection_area_projected_m2'] for c in cells) == 4


@pytest.mark.parametrize('reverse', [False, True])
def test_diagonal_edge_reference_with_fractional_areas_and_nodata(reverse):
    # x+y<=2: top-left intersection 1/2 (value 1), bottom-left
    # intersection 1 (value 3), bottom-right intersection 1/2 (nodata).
    # Valid weighted mean=(1/2+3)/(3/2)=7/3; variance=8/9.
    ring = [(0, 0), (2, 0), (0, 2)]
    if reverse:
        ring.reverse()
    stats, cells = spatial.reduce_grid_xy(ring, raster([[1, 2], [3, None]]))
    assert stats['parcel_area_projected_m2'] == 2
    assert stats['valid_area_projected_m2'] == 1.5
    assert stats['valid_area_fraction'] == .75
    assert stats['mean'] == pytest.approx(7/3)
    assert stats['median'] == 3
    assert stats['standard_deviation'] == pytest.approx(math.sqrt(8/9))
    assert stats['valid_pixel_count'] == 2 and len(cells) == 3
    for cell in cells:
        for part in cell['parts_xy']:
            assert all(x >= -1e-10 and y >= -1e-10 and x+y <= 2+1e-10 for x, y in part)


def test_concave_l_shape_clips_excluded_quadrant_and_preserves_missing_area():
    ring = [(0, 0), (2, 0), (2, 1), (1, 1), (1, 2), (0, 2)]
    stats, cells = spatial.reduce_grid_xy(ring, raster([[1, 999], [3, None]]))
    assert stats['parcel_area_projected_m2'] == 3
    assert stats['mean'] == stats['median'] == 2
    assert stats['standard_deviation'] == 1
    assert stats['valid_area_fraction'] == pytest.approx(2/3)
    assert stats['intersecting_pixel_count'] == 3
    for cell in cells:
        for part in cell['parts_xy']:
            assert all(0 <= x <= 2 and 0 <= y <= 2 and (x <= 1 or y <= 1) for x, y in part)


def test_small_parcel_constant_zero_and_partial_raster_extent():
    stats, cells = spatial.reduce_grid_xy([(.1, .1), (.2, .1), (.1, .2)], raster([[0]]))
    assert stats['valid_pixel_count'] == 1 and len(cells) == 1
    assert stats['mean'] == stats['median'] == stats['minimum'] == stats['maximum'] == 0
    assert stats['standard_deviation'] == 0
    assert stats['valid_area_fraction'] == pytest.approx(1)
    assert len(spatial.legend(stats)['classes']) == 1
    stats, _ = spatial.reduce_grid_xy([(0, 0), (2, 0), (2, 1), (0, 1)], raster([[7]]))
    assert stats['valid_area_fraction'] == stats['grid_extent_area_fraction'] == .5
    assert stats['mean'] == 7


@pytest.mark.parametrize('missing', [None, float('nan'), float('inf'), -9999, True, 'invalid'])
def test_all_nodata_is_never_zero_or_a_suitability_grade(missing):
    stats, cells = spatial.reduce_grid_xy([(0, 0), (1, 0), (1, 1), (0, 1)], raster([[missing]]))
    assert stats['valid_pixel_count'] == 0 and stats['valid_area_fraction'] == 0
    assert all(stats[key] is None for key in ['minimum', 'maximum', 'mean', 'median', 'standard_deviation'])
    assert cells[0]['status'] == 'nodata' and spatial.legend(stats)['classes'] == []


@pytest.mark.parametrize('field,value', [('crs', 'EPSG:4326'), ('width', 0), ('height', 2000), ('transform', [1, 0, 0, 0, float('nan'), 2]), ('values', [])])
def test_invalid_grid_metadata_is_rejected(field, value):
    grid = raster([[1, 2], [3, 4]])
    grid[field] = value
    with pytest.raises((ValueError, TypeError)):
        spatial.reduce_grid_xy([(0, 0), (2, 0), (0, 2)], grid)


def test_projected_precision_and_reprojection_roundtrip():
    origin = spatial.project({'lat': 7.29, 'lng': 125.62})
    ring = [(origin[0]+x, origin[1]+y) for x, y in [(0, 0), (2, 0), (0, 2)]]
    grid = raster([[1, 2], [3, None]])
    grid['transform'][2] = origin[0]
    grid['transform'][5] += origin[1]
    stats, _ = spatial.reduce_grid_xy(ring, grid)
    assert stats['mean'] == pytest.approx(7/3)
    assert spatial.unproject(origin) == pytest.approx({'lat': 7.29, 'lng': 125.62})


def test_saved_snapshot_is_immutable_and_provider_failure_explicit():
    polygon = [spatial.unproject(p) for p in [(0, 0), (2, 0), (0, 2), (0, 0)]]
    provider = Mock(return_value={'elevation': raster([[1, 2], [3, None]])})
    first = spatial.build_spatial_assessment(polygon, provider)
    layer = next(l for l in first['layers'] if l['id'] == 'elevation')
    assert layer['statistics']['valid_area_fraction'] == pytest.approx(.75)
    assert all('parts' in c and 'parts_xy' not in c for c in layer['cells'])
    retained = deepcopy(first)
    layer['cells'].clear()
    second = spatial.build_spatial_assessment(polygon, provider)
    assert second['cache_hit'] is True and provider.call_count == 1
    second['cache_hit'] = False
    assert second == retained
    unavailable = spatial.build_spatial_assessment(polygon, lambda _: (_ for _ in ()).throw(RuntimeError('fixture')))
    assert unavailable['status'] == 'unavailable'
    assert all(l['statistics'] is None and not l['cells'] for l in unavailable['layers'])
    point = spatial.build_spatial_assessment([], provider)
    assert point['status'] == 'not_applicable'


def test_grid_budget_and_no_finer_than_native_ground_scale():
    polygon = [{'lat': 7.29, 'lng': 125.62}, {'lat': 7.291, 'lng': 125.62}, {'lat': 7.29, 'lng': 125.621}]
    grid = spatial.grid_for_polygon(polygon, 250)
    assert grid['effective_resolution_projected_m']*math.cos(math.radians(7.29)) >= 250
    with pytest.raises(ValueError, match='exceeds'):
        spatial.grid_for_polygon(polygon, .01)
