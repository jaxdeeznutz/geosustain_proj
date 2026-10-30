"""Explicit synthetic raster fixtures for local workflow acceptance only."""
from spatial_analysis import LAYERS, grid_for_polygon, build_spatial_assessment, now

RING = [{'lat': 7.29, 'lng': 125.62}, {'lat': 7.29, 'lng': 125.6212},
        {'lat': 7.29045, 'lng': 125.6212}, {'lat': 7.29045, 'lng': 125.62055},
        {'lat': 7.2911, 'lng': 125.62055}, {'lat': 7.2911, 'lng': 125.62}]


def fixture_rasters(polygon):
    rasters = {}
    for layer_id, config in LAYERS.items():
        if layer_id == 'rainfall_30d':
            rasters[layer_id] = {'reason': 'CONTROLLED UNAVAILABLE RASTER FIXTURE: no precipitation cells supplied; model samples are not substituted.'}
            continue
        grid = grid_for_polygon(polygon, config['native_resolution_m'])
        values = []
        for row in range(grid['height']):
            values.append([])
            for column in range(grid['width']):
                value = {
                    'ndvi': None if (row+column) % 5 == 0 else .25 + column*.02 + row*.01,
                    'elevation': 100 + row*2 + column*3,
                    'slope': 2 + row*.5 + column*.25,
                    'soil_ph': 6.0, 'rainfall_annual': 2100.0, 'temperature_annual': 27.0,
                }[layer_id]
                values[-1].append(value)
        rasters[layer_id] = {**grid, 'values': values, 'fixture': True, 'retrieved_at': now(),
                            'native_projection': {'crs': 'EPSG:3857', 'transform': grid['transform'],
                                                  'nominal_scale_m': config['native_resolution_m']},
                            'source_period': {'start': '2026-10-01', 'end_exclusive': '2026-10-02',
                                              'period': 'Synthetic workflow fixture window, not a real observation', 'method': 'Deterministic test grid'},
                            'resampling': 'Synthetic regular grid, not a real source resampling',
                            'mask_method': 'Explicit synthetic NDVI nodata cells; all other supplied fixture cells valid'}
    return rasters


def fixture_spatial(polygon):
    return build_spatial_assessment(polygon, provider=fixture_rasters)
