"""Server-owned city screening and separate CAGRO soil coverage policy."""
from copy import deepcopy
import os

import cagro_soil as cagro
from geometry import normalize_polygon, polygon_centroid, polygon_area_m2

VERSION = 'panabo-preliminary-cagro-v2'
MESSAGE = ('Location not supported for formal analysis. GeoSustain currently provides formal '
           'crop analysis only for locations where available CAGRO soil information can support '
           'the assessment. Additional areas can be supported when more validated CAGRO soil '
           'records become available.')
HISTORICAL_NOTE = ('CAGRO nutrient records provide locally available historical soil information '
                   'for supported Panabo City locations. They may not represent the current exact '
                   'soil condition of every point within the farm and should be supplemented by '
                   'field or laboratory assessment when necessary.')


class CoverageUnavailable(ValueError):
    def __init__(self, coverage):
        super().__init__(coverage.get('message') or MESSAGE)
        self.coverage = coverage


def coverage_from_soil(soil):
    rows = soil.get('observations', []) if soil.get('status') == 'matched' else []
    # Preserve all matches and their original addresses; never choose one row.
    matches = [{key: deepcopy(row.get(key)) for key in (
        'id', 'location_id', 'locality_id', 'location_name', 'catalog_location_name',
        'latitude', 'longitude', 'coordinate_precision', 'confidence',
        'original_cagro_gps', 'coordinate_source', 'source', 'source_file', 'source_row', 'match')}
        for row in rows]
    return {'schema_version': VERSION, 'supported': bool(rows),
            'reason': 'CAGRO soil data available' if rows else 'No CAGRO soil data available for this farm location',
            'message': HISTORICAL_NOTE if rows else MESSAGE,
            'matches': matches, 'matching_policy': soil.get('matching_policy'),
            'locality_ids': sorted({r['locality_id'] for r in rows}),
            'nutrient_source': 'Panabo City CAGRO historical soil record' if rows else None,
            'used_for_model_prediction': False}


def check_coverage(polygon):
    soil = cagro.lookup_soil_observations(polygon)
    coverage = coverage_from_soil(soil)
    from city_boundary import contains_polygon, VERSION as CITY_VERSION
    city_supported = contains_polygon(polygon)
    coverage.update(preliminary_supported=city_supported, can_analyze=city_supported,
        analysis_mode='cagro_supported' if coverage['supported'] else 'preliminary_environmental',
        city_boundary_version=CITY_VERSION)
    if city_supported and not coverage['supported']:
        coverage.update(reason='Preliminary screening available; CAGRO NPK unavailable',
            message='Environmental screening is available within the Panabo City reference boundary. No matching CAGRO soil sample is available: NPK is not assessed for this farm.')
    return coverage, soil


def require_coverage(polygon):
    coverage, soil = check_coverage(polygon)
    if not coverage['supported']:
        raise CoverageUnavailable(coverage)
    return coverage, soil


def require_analysis_coverage(polygon):
    coverage, soil = check_coverage(polygon)
    if not coverage['can_analyze']:
        raise CoverageUnavailable(coverage)
    return coverage, soil


def require_point_coverage(lat, lon):
    """A point permits city screening, never an invented parcel/soil association."""
    from city_boundary import contains_point, VERSION as CITY_VERSION
    soil = cagro.lookup_soil_observations([])
    coverage = coverage_from_soil(soil)
    inside = contains_point(lat, lon)
    coverage.update(preliminary_supported=inside, can_analyze=inside,
        analysis_mode='preliminary_environmental', geometry_type='Point',
        city_boundary_version=CITY_VERSION,
        reason='Point screening; CAGRO NPK unavailable' if inside else 'Point outside Panabo City reference boundary',
        message=('Preliminary screening at the selected point. A farm boundary and reviewed soil association are required for CAGRO NPK.'
                 if inside else 'Select a point inside the Panabo City reference boundary.'))
    if not inside:
        raise CoverageUnavailable(coverage)
    return coverage, soil


def farm_coverage(row):
    """Current preflight status, without changing any old analysis snapshot."""
    if row is None:
        return None
    result = deepcopy(row)
    polygon = row.get('polygon') or []
    coverage, _ = check_coverage(polygon)
    result['analysis_coverage'] = coverage
    try:
        ring = normalize_polygon(polygon)
        lat, lon = polygon_centroid(ring)
        result.update(center_lat=lat, center_lon=lon, area_m2=polygon_area_m2(ring),
                      centroid_method='Area-weighted polygon centroid; not a soil sample coordinate')
    except (ValueError, TypeError, KeyError):
        result.update(center_lat=None, center_lon=None)
    return result


def coverage_catalog():
    """Only reviewed boundaries and existing mapped anchors; no invented circles."""
    result = {'schema_version': VERSION, 'reference_locations': [], 'boundaries': [],
              'city_boundary': __import__('city_boundary').reference(),
              'note': 'Reference markers are reconstructed locality anchors, not barangay boundaries or original sample GPS. Full farm geometry is checked by the server.'}
    try:
        rows = cagro._read(cagro.DATA / 'cagro_observations.json')
        locations = cagro._read(cagro.DATA / 'cagro_locations.json')
        ids = {r['location_id'] for r in rows}
        localities = {l['locality_id'] for l in locations if l['id'] in ids}
        result['reference_locations'] = [deepcopy(l) for l in locations
                                        if l['id'] in ids and l['coordinate_precision'] in cagro.MAPPED_PRECISIONS]
        path = os.getenv('CAGRO_LOCALITY_BOUNDARIES_PATH')
        if path:
            for feature in cagro._read(path).get('features', []):
                p, g = feature.get('properties', {}), feature.get('geometry', {})
                polygons = [g.get('coordinates', [])] if g.get('type') == 'Polygon' else g.get('coordinates', []) if g.get('type') == 'MultiPolygon' else []
                if (p.get('verified') is True and p.get('source') and p.get('locality_id') in localities
                        and polygons and all(cagro._rings_valid(rings) for rings in polygons)):
                    result['boundaries'].append(deepcopy(feature))
    except (OSError, ValueError, TypeError, KeyError):
        # A broken configured boundary also makes the matcher fail closed.
        result.update(reference_locations=[], boundaries=[], error='Coverage configuration unavailable')
    return result
