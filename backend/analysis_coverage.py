"""Server-owned coverage policy; the existing matcher is the sole admission rule."""
from copy import deepcopy
import os

import cagro_soil as cagro
from geometry import normalize_polygon, polygon_centroid, polygon_area_m2

VERSION = 'cagro-supported-analysis-v1'
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
        super().__init__(MESSAGE)
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
    return coverage_from_soil(soil), soil


def require_coverage(polygon):
    coverage, soil = check_coverage(polygon)
    if not coverage['supported']:
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
