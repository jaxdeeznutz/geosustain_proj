"""Bounded raster/parcel intersection and area-weighted descriptive statistics.

All geometry arithmetic uses EPSG:3857 projected metres. Coverage is a ratio
of projected areas, not ground area or the proportion of independent samples.
Simple concave rings are triangulated, then each triangle is clipped against
each analysis-grid pixel. No interpolation from model sample points is used.
"""
from collections import OrderedDict
from copy import deepcopy
from datetime import datetime, timezone
import hashlib
import json
import math
from threading import Lock
from time import monotonic

VERSION = 'polygon-raster-v1'
RADIUS = 6378137.0
MAX_PIXELS = 1024
MAX_VERTICES = 128
MAX_FRAGMENTS = 4096
AREA_EPS = 1e-8
_CACHE = OrderedDict()
_LOCK = Lock()

LAYERS = {
    'ndvi': {'label': 'Vegetation (NDVI)', 'unit': 'index', 'native_resolution_m': 10,
             'source': 'COPERNICUS/S2_SR_HARMONIZED', 'range': [-1, 1]},
    'elevation': {'label': 'Elevation', 'unit': 'm', 'native_resolution_m': 30,
                  'source': 'USGS/SRTMGL1_003', 'range': [-500, 9000]},
    'slope': {'label': 'Slope', 'unit': '%', 'native_resolution_m': 30,
              'source': 'USGS/SRTMGL1_003 / ee.Terrain.slope', 'range': [0, None]},
    'soil_ph': {'label': 'Soil pH in water (0 cm)', 'unit': 'pH', 'native_resolution_m': 250,
                'source': 'OpenLandMap/SOL/SOL_PH-H2O_USDA-4C1A2A_M/v02', 'range': [0, 14]},
    'rainfall_30d': {'label': 'Rainfall (completed 30 days)', 'unit': 'mm/30 days', 'native_resolution_m': 5566,
                     'source': 'UCSB-CHG/CHIRPS/DAILY', 'range': [0, None]},
    'rainfall_annual': {'label': 'Rainfall (5-year annual mean)', 'unit': 'mm/year', 'native_resolution_m': 5566,
                        'source': 'UCSB-CHG/CHIRPS/DAILY', 'range': [0, None]},
    'temperature_annual': {'label': 'Air temperature (5-year mean)', 'unit': 'C', 'native_resolution_m': 11132,
                           'source': 'ECMWF/ERA5_LAND/DAILY_AGGR', 'range': [-90, 65]},
}


def now():
    return datetime.now(timezone.utc).isoformat()


def project(point):
    lon, lat = float(point['lng']), float(point['lat'])
    if not math.isfinite(lat) or not math.isfinite(lon) or abs(lat) >= 85:
        raise ValueError('Unsupported projected coordinate.')
    return RADIUS * math.radians(lon), RADIUS * math.log(math.tan(math.pi / 4 + math.radians(lat) / 2))


def unproject(point):
    x, y = point
    return {'lat': math.degrees(2 * math.atan(math.exp(y / RADIUS)) - math.pi / 2),
            'lng': math.degrees(x / RADIUS)}


def signed_area(points):
    if len(points) < 3:
        return 0.0
    ox, oy = points[0]
    p = [(x - ox, y - oy) for x, y in points]
    return sum(a[0]*b[1]-b[0]*a[1] for a, b in zip(p, p[1:]+p[:1])) / 2


def cross(a, b, c):
    return (b[0]-a[0])*(c[1]-a[1]) - (b[1]-a[1])*(c[0]-a[0])


def triangulate(ring):
    points = list(ring)
    if points and points[0] == points[-1]:
        points.pop()
    if len(points) < 3 or len(points) > MAX_VERTICES:
        raise ValueError(f'Raster analysis supports 3–{MAX_VERTICES} boundary vertices.')
    # Collinear vertices add no area and can prevent ear selection.
    while len(points) > 3:
        index = next((i for i in range(len(points)) if abs(cross(points[i-1], points[i], points[(i+1) % len(points)])) < AREA_EPS), None)
        if index is None:
            break
        points.pop(index)
    if signed_area(points) < 0:
        points.reverse()
    if abs(signed_area(points)) < AREA_EPS:
        raise ValueError('Raster geometry has zero area.')
    triangles = []
    while len(points) > 3:
        found = False
        for i in range(len(points)):
            a, b, c = points[i-1], points[i], points[(i+1) % len(points)]
            if cross(a, b, c) <= AREA_EPS:
                continue
            others = [p for j, p in enumerate(points) if j not in ((i-1) % len(points), i, (i+1) % len(points))]
            if any(min(cross(a, b, p), cross(b, c, p), cross(c, a, p)) >= -AREA_EPS for p in others):
                continue
            triangles.append([a, b, c])
            points.pop(i)
            found = True
            break
        if not found:
            raise ValueError('Raster geometry could not be triangulated safely.')
    return triangles + [points]


def clip_rectangle(points, left, bottom, right, top):
    output = list(points)
    for axis, bound, greater in [(0, left, True), (0, right, False), (1, bottom, True), (1, top, False)]:
        source, output = output, []
        if not source:
            break
        previous = source[-1]
        previous_in = previous[axis] >= bound if greater else previous[axis] <= bound
        for current in source:
            current_in = current[axis] >= bound if greater else current[axis] <= bound
            if current_in != previous_in:
                t = (bound - previous[axis]) / (current[axis] - previous[axis])
                output.append((previous[0] + t*(current[0]-previous[0]), previous[1] + t*(current[1]-previous[1])))
            if current_in:
                output.append(current)
            previous, previous_in = current, current_in
    return output


def grid_for_polygon(polygon, native_resolution_m):
    projected = [project(p) for p in polygon]
    latitude = sum(p['lat'] for p in polygon) / len(polygon)
    # EPSG:3857 scale distortion: choose projected cell width so its nominal
    # ground width is no finer than the configured native source resolution.
    scale = math.ceil(native_resolution_m / math.cos(math.radians(latitude)))
    left = math.floor(min(p[0] for p in projected) / scale) * scale
    top = math.ceil(max(p[1] for p in projected) / scale) * scale
    width = max(1, math.ceil((max(p[0] for p in projected) - left) / scale))
    height = max(1, math.ceil((top - min(p[1] for p in projected)) / scale))
    if width * height > MAX_PIXELS:
        raise ValueError(f'Native-resolution bounding grid exceeds {MAX_PIXELS} cells; no finer or fabricated layer is substituted.')
    return {'crs': 'EPSG:3857', 'width': width, 'height': height,
            'transform': [scale, 0, left, 0, -scale, top], 'effective_resolution_projected_m': scale}


def clean_value(value, limits):
    if isinstance(value, bool) or value is None:
        return None
    try:
        value = float(value)
    except (TypeError, ValueError):
        return None
    low, high = limits
    if not math.isfinite(value) or value == -9999 or (low is not None and value < low) or (high is not None and value > high):
        return None
    return value


def reduce_grid_xy(ring, raster, limits=(None, None)):
    """Exact planar clipping on an explicit axis-aligned grid; no point fill."""
    if raster.get('crs') != 'EPSG:3857':
        raise ValueError('Raster CRS must be EPSG:3857.')
    width, height = raster['width'], raster['height']
    sx, shear_x, left, shear_y, sy, top = raster['transform']
    if (type(width) is not int or type(height) is not int
            or not all(isinstance(v, (int, float)) and math.isfinite(v) for v in raster['transform'])
            or width <= 0 or height <= 0 or width*height > MAX_PIXELS or sx <= 0 or sy >= 0 or shear_x or shear_y):
        raise ValueError('Unsupported or oversized raster grid.')
    rows = raster['values']
    if len(rows) != height or any(len(row) != width for row in rows):
        raise ValueError('Raster dimensions do not match returned values.')
    triangles = triangulate(ring)
    parcel_area = abs(signed_area(list(ring)))
    cells, weighted, evaluated_area, valid_area = [], [], 0.0, 0.0
    fragment_count = 0
    for row in range(height):
        for column in range(width):
            x0, y1 = left+column*sx, top+row*sy
            parts = [clip_rectangle(t, x0, y1+sy, x0+sx, y1) for t in triangles]
            parts = [p for p in parts if abs(signed_area(p)) > AREA_EPS]
            area = sum(abs(signed_area(p)) for p in parts)
            if area <= AREA_EPS:
                continue
            fragment_count += len(parts)
            if fragment_count > MAX_FRAGMENTS:
                raise ValueError('Clipped geometry exceeds the bounded fragment count.')
            value = clean_value(rows[row][column], limits)
            evaluated_area += area
            if value is not None:
                valid_area += area
                weighted.append((value, area))
            cells.append({'row': row, 'column': column, 'value': value,
                          'status': 'valid' if value is not None else 'nodata',
                          'intersection_area_projected_m2': area, 'parts_xy': parts})
    weighted.sort()
    mean = sum(v*w for v, w in weighted)/valid_area if valid_area else None
    median = None
    accumulated = 0
    for index, (value, weight) in enumerate(weighted):
        accumulated += weight
        if accumulated >= valid_area/2:
            median = ((value+weighted[index+1][0])/2
                      if math.isclose(accumulated, valid_area/2, abs_tol=AREA_EPS) and index+1 < len(weighted) else value)
            break
    stats = {
        'minimum': weighted[0][0] if weighted else None, 'maximum': weighted[-1][0] if weighted else None,
        'mean': mean, 'median': median,
        'standard_deviation': math.sqrt(sum(w*(v-mean)**2 for v, w in weighted)/valid_area) if weighted else None,
        'valid_pixel_count': len(weighted), 'intersecting_pixel_count': len(cells),
        'parcel_area_projected_m2': parcel_area, 'evaluated_area_projected_m2': evaluated_area,
        'valid_area_projected_m2': valid_area,
        'valid_area_fraction': min(1.0, valid_area/parcel_area) if parcel_area else 0.0,
        'grid_extent_area_fraction': min(1.0, evaluated_area/parcel_area) if parcel_area else 0.0,
    }
    return stats, cells


def legend(stats):
    low, high = stats['minimum'], stats['maximum']
    if low is None:
        classes = []
    elif low == high:
        classes = [{'minimum': low, 'maximum': high, 'color': '#6baed6', 'label': 'Constant observed value'}]
    else:
        colors = ['#deebf7', '#9ecae1', '#3182bd']
        classes = [{'minimum': low+(high-low)*i/3, 'maximum': low+(high-low)*(i+1)/3,
                    'color': colors[i], 'label': ['Lower', 'Middle', 'Higher'][i]} for i in range(3)]
    return {'classes': classes, 'nodata_color': '#bdbdbd',
            'interpretation': 'Descriptive lower-to-higher values within this saved layer; not agronomic suitability.',
            'bounds': 'Lower bound inclusive; upper bound exclusive except last class; constant layer uses neutral blue.'}


def unavailable_layer(layer_id, reason):
    return {'id': layer_id, **deepcopy(LAYERS[layer_id]), 'status': 'unavailable',
            'quality': 'unavailable',
            'reason': reason, 'cells': [], 'statistics': None,
            'legend': {'classes': [], 'nodata_color': '#bdbdbd', 'interpretation': 'No raster observations available; no suitability conclusion.'}}


def layer_from_raster(layer_id, polygon, raster):
    config = LAYERS[layer_id]
    stats, cells = reduce_grid_xy([project(p) for p in polygon], raster, config['range'])
    for cell in cells:
        cell['parts'] = [[unproject(p) for p in part] for part in cell.pop('parts_xy')]
    status = 'unavailable' if not stats['valid_pixel_count'] else 'available' if stats['valid_area_fraction'] >= 1-1e-8 else 'partial'
    metadata = {k: deepcopy(v) for k, v in raster.items() if k != 'values'}
    return {'id': layer_id, **deepcopy(config),
            **({'source': config['source']+' (SYNTHETIC WORKFLOW FIXTURE; not provider observations)', 'fixture': True} if raster.get('fixture') else {}),
            'quality': 'unavailable' if not stats['valid_pixel_count'] else 'synthetic_fixture' if raster.get('fixture') else 'gridded_source_estimate',
            'status': status, 'grid': metadata,
            'statistics': stats, 'cells': cells, 'legend': legend(stats),
            'limitation': 'Analysis-grid cells are reprojected source estimates, not independent field observations. Coarse grids do not resolve subpixel variation.'}


def build_spatial_assessment(polygon, provider=None):
    if provider is None:
        from spatial_provider import fetch_rasters
        provider = fetch_rasters
    if not polygon:
        return {'version': VERSION, 'status': 'not_applicable', 'captured_at': now(), 'layers': [],
                'reason': 'Polygon raster statistics require a saved or inspection polygon; point values are not zonal statistics.'}
    key = (hashlib.sha256(json.dumps(polygon, sort_keys=True).encode()).hexdigest(), datetime.now(timezone.utc).date().isoformat(), provider)
    with _LOCK:
        prior = _CACHE.get(key)
        if prior and monotonic() < prior[0]:
            _CACHE.move_to_end(key)
            result = deepcopy(prior[1]); result['cache_hit'] = True
            return result
    result = {
        'version': VERSION, 'captured_at': now(), 'analysis_crs': 'EPSG:3857',
        'geometry_hash': key[0], 'boundary': deepcopy(polygon), 'layers': [],
        'statistics_method': 'Min/max of intersecting valid cells; mean, median and population standard deviation weighted by exact parcel-cell intersection area. Median uses midpoint on an exact half-area tie.',
        'coverage_method': 'Valid cell intersection area / complete parcel area in EPSG:3857; edge cells use their clipped area. Counts are analysis-grid cells, not independent field samples. Missing values remain missing.',
        'limitations': ['EPSG:3857 areas are projected areas, not legal-survey or geodesic ground areas.',
                        'Raster statistics and descriptive colors do not change sampled model inputs, scores, crop order or annual factor grades.',
                        'Current humidity and estimated NPK are point/model products; no raster coverage or nutrient heatmap is inferred.'],
    }
    try:
        triangulate([project(p) for p in polygon])
        rasters = provider(polygon)
    except Exception:
        rasters = {}
    for layer_id in LAYERS:
        raster = rasters.get(layer_id) or {}
        try:
            layer = (layer_from_raster(layer_id, polygon, raster) if raster.get('values') is not None
                     else unavailable_layer(layer_id, raster.get('reason', 'Spatial source unavailable; sampled values were not substituted.')))
        except (ValueError, TypeError, KeyError, OverflowError):
            layer = unavailable_layer(layer_id, 'Raster geometry, metadata or values failed validation; no sample-based fill was substituted.')
        result['layers'].append(layer)
    statuses = [r['status'] for r in result['layers']]
    result['status'] = 'available' if all(s == 'available' for s in statuses) else 'unavailable' if all(s == 'unavailable' for s in statuses) else 'partial'
    result['cache_hit'] = False
    with _LOCK:
        _CACHE[key] = (monotonic()+(900 if result['status'] != 'unavailable' else 60), deepcopy(result))
        _CACHE.move_to_end(key)
        while len(_CACHE) > 16:
            _CACHE.popitem(last=False)
    return result
