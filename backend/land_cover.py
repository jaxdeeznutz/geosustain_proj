"""Whole-boundary land-cover screening, separate from crop model ranking."""
from datetime import datetime, timedelta, timezone
import math

SOURCE = 'Google Dynamic World V1 (10 m), latest clear observations within 90 days'
BANDS = ['water', 'trees', 'grass', 'flooded_vegetation', 'crops', 'shrub_and_scrub', 'built', 'bare', 'snow_and_ice']


def interpret_cover(stats):
    # Conservative application screening thresholds, not validated agronomic limits.
    areas = [stats.get(key, 0) or 0 for key in ('total', 'observed', 'water', 'built')]
    if not all(isinstance(v, (int, float)) and math.isfinite(v) and v >= 0 for v in areas):
        raise ValueError('Invalid land-cover observations')
    total, observed, water_area, built_area = areas
    if observed > total + 1e-6 or water_area + built_area > observed + 1e-6:
        raise ValueError('Inconsistent land-cover areas')
    coverage = observed / total if total else 0
    water = water_area / total if total else 0
    built = built_area / total if total else 0
    status, message = 'eligible', 'No substantial mapped water or built-up area detected. This does not confirm agricultural suitability.'
    if water >= .5:
        status, message = 'water', 'This area is predominantly mapped water. No crop recommendation is provided. Select a land boundary.'
    elif built >= .5:
        status, message = 'built_up', 'This area is predominantly mapped buildings or roads. No crop recommendation is provided. Select agricultural land.'
    elif water + built >= .1:
        status, message = 'mixed', 'Your boundary includes mapped water or buildings. Refine it to exclude these areas before requesting crop recommendations.'
    elif coverage < .8:
        status, message = 'unknown', 'There is not enough confident recent satellite coverage to verify this area. Please retry later or ask an agricultural officer to check the boundary.'
    return {'status': status, 'allow_crops': status == 'eligible', 'message': message,
            'water_fraction': water, 'built_fraction': built, 'observed_fraction': coverage,
            'source': SOURCE, 'screening_policy': 'v1: class confidence >=0.6; >=50% dominant, >=10% mixed exclusion, >=80% observed coverage',
            'limitation': 'Satellite classification can miss small buildings or recent changes. Thresholds are application safeguards, not field-validated suitability rules.',
            'attribution': 'Dynamic World Project by Google in partnership with National Geographic Society and the World Resources Institute. Contains modified Copernicus Sentinel data.'}


def screen_land_cover(lat, lon, polygon):
    import rainfallDatasets as env
    env.ensure_earth_engine_initialized()
    ee = env.ee
    region = (ee.Geometry.Polygon([[[p['lng'], p['lat']] for p in polygon]]) if polygon
              else ee.Geometry.Point([lon, lat]).buffer(20))
    end = datetime.now(timezone.utc)
    start = end - timedelta(days=90)
    collection = ee.ImageCollection('GOOGLE/DYNAMICWORLD/V1').filterBounds(region).filterDate(start.isoformat(), end.isoformat())
    def masks(image):
        confidence = image.select(BANDS).reduce(ee.Reducer.max())
        label = image.select('label')
        return (label.eq(0).And(confidence.gte(.6)).rename('water')
                .addBands(label.eq(6).And(confidence.gte(.6)).rename('built'))
                .addBands(confidence.gte(.6).rename('observed'))).toByte()
    # Empty collections produce a fully masked observation, never a safe-land default.
    empty = ee.Image.constant([0, 0, 0]).rename(['water', 'built', 'observed']).toByte().updateMask(ee.Image.constant(0))
    composite = ee.ImageCollection.fromImages([empty]).merge(collection.sort('system:time_start').map(masks)).mosaic()
    areas = composite.unmask(0).multiply(ee.Image.pixelArea()).addBands(ee.Image.pixelArea().rename('total'))
    stats = areas.reduceRegion(reducer=ee.Reducer.sum(), geometry=region, scale=10, maxPixels=10000000, tileScale=4).getInfo()
    result = interpret_cover(stats)
    result.update(start=start.date().isoformat(), end=end.date().isoformat(), scope='whole_polygon' if polygon else '20m_point_buffer')
    return result


def advisory_result(screen):
    return {'scoring_version': 'land-cover-screen-v1', 'recommendation_basis': 'land_cover_screening',
            'land_cover': screen, 'land_type': screen['status'], 'land_status': screen['status'].replace('_', ' ').upper(),
            'is_crop_recommended': False, 'analysis_summary': screen['message'], 'recommendation': screen['message'],
            'recommendation_title': 'Land use advisory', 'top_crop_recommendations': [], 'alternative_crops': [],
            'crop_assessments': [], 'best_crop': None, 'predicted_crop': None, 'crop': None,
            'crop_compatibility_pct': None, 'model_explanation': None,
            'environmental_measurements': {}, 'data_quality_warnings': [screen['limitation']]}
