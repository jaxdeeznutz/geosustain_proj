"""Bounded Earth Engine pixel downloads using existing provider credentials.

No provider deadlines or global EE transport are changed. Each REST request
uses explicit connect/read deadlines; responses and grid dimensions are capped.
Credentials and temporary access tokens are never placed in saved snapshots.
"""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
import io
import json

from spatial_analysis import LAYERS, grid_for_polygon, now


def limited_body(response, limit=2*1024*1024):
    response.raise_for_status()
    chunks, total = [], 0
    try:
        for chunk in response.iter_content(8192):
            total += len(chunk)
            if total > limit:
                raise ValueError('Spatial response exceeded the byte limit.')
            chunks.append(chunk)
    finally:
        response.close()
    return b''.join(chunks)


def image_for_layer(ee, layer_id, polygon, today):
    geometry = ee.Geometry.Polygon([[[p['lng'], p['lat']] for p in polygon]], 'EPSG:4326', False)
    dem = ee.Image('USGS/SRTMGL1_003').select('elevation')
    if layer_id in ('elevation', 'slope'):
        image = dem if layer_id == 'elevation' else ee.Terrain.slope(dem).multiply(3.141592653589793/180).tan().multiply(100)
        return image, dem.projection(), {'start': '2000-02-11', 'end_exclusive': '2000-02-23',
                                         'period': 'SRTM acquisition; static terrain reference', 'method': 'Elevation raster' if layer_id == 'elevation' else 'tan(ee.Terrain.slope in degrees) * 100'}
    if layer_id == 'soil_ph':
        image = ee.Image('OpenLandMap/SOL/SOL_PH-H2O_USDA-4C1A2A_M/v02').select('b0')
        return image.multiply(.1), image.projection(), {'start': '1950-01-01', 'end_exclusive': '2018-01-01',
                                                       'period': 'Static soil model; catalog coverage, not a pixel sampling date', 'method': 'b0 (0 cm) multiplied by catalog scale 0.1'}
    if layer_id == 'ndvi':
        start, end = (today-timedelta(days=548)).isoformat(), today.isoformat()
        collection = (ee.ImageCollection('COPERNICUS/S2_SR_HARMONIZED').filterBounds(geometry).filterDate(start, end)
                      .filter(ee.Filter.lt('CLOUDY_PIXEL_PERCENTAGE', 20)).sort('system:time_start', False))
        scene = ee.Image(collection.first())
        scl = scene.select('SCL')
        mask = scl.neq(0).And(scl.neq(1)).And(scl.neq(3)).And(scl.neq(8)).And(scl.neq(9)).And(scl.neq(10)).And(scl.neq(11))
        ndvi = scene.normalizedDifference(['B8', 'B4']).updateMask(mask)
        return ndvi, scene.select('B8').projection(), {
            'start': start, 'end_exclusive': end, 'period': 'Latest qualifying scene in completed 548-day search window',
            'observation_date': scene.date().format('YYYY-MM-dd'), 'scene_id': scene.get('system:index'),
            'method': '(B8-B4)/(B8+B4); scene clouds <20%; SCL cloud/shadow/snow/nodata mask (20 m mask, nearest resampling)',
        }
    end = today.isoformat() if layer_id == 'rainfall_30d' else f'{today.year}-01-01'
    start = ((today-timedelta(days=30)).isoformat() if layer_id == 'rainfall_30d' else f'{today.year-5}-01-01')
    expected = (datetime.fromisoformat(end)-datetime.fromisoformat(start)).days
    temperature = layer_id == 'temperature_annual'
    dataset, band = ('ECMWF/ERA5_LAND/DAILY_AGGR', 'temperature_2m') if temperature else ('UCSB-CHG/CHIRPS/DAILY', 'precipitation')
    collection = ee.ImageCollection(dataset).filterDate(start, end).select(band)
    native = ee.Image(collection.first()).projection()
    image = collection.mean().subtract(273.15) if temperature else collection.sum()
    if layer_id == 'rainfall_annual':
        image = image.divide(5)
    # Missing dates or per-pixel masked days never become a full-period total.
    image = image.updateMask(collection.count().eq(expected)).updateMask(ee.Image.constant(collection.size().eq(expected)))
    return image.setDefaultProjection(native), native, {
        'start': start, 'end_exclusive': end, 'expected_images': expected, 'retrieved_images': collection.size(),
        'period': 'rolling_30_complete_UTC_days' if layer_id == 'rainfall_30d' else 'five_complete_calendar_years',
        'method': ('Daily mean air temperature averaged; Kelvin minus 273.15' if temperature else
                   'Sum of complete daily precipitation images' + (' divided by five years' if layer_id == 'rainfall_annual' else '')),
    }


def fetch_rasters(polygon):
    import rainfallDatasets as env
    import ee
    import numpy as np
    from google.auth.transport.requests import AuthorizedSession, Request
    from google.oauth2 import service_account

    try:
        # Successful model inference already initializes EE. Do not initiate
        # optional global discovery/auth work here (for example on a land-use
        # advisory that did not run inference). That work has no local timeout.
        if not env._EE_INITIALIZED:
            return {}
        credentials = (service_account.Credentials.from_service_account_info(
            json.loads(env.GEE_SERVICE_ACCOUNT_JSON), scopes=['https://www.googleapis.com/auth/earthengine'])
            if env.GEE_SERVICE_ACCOUNT_JSON else ee.data.get_persistent_credentials())
        transport = Request()
        def auth_request(url, method='GET', body=None, headers=None, **kwargs):
            kwargs.pop('timeout', None)
            return transport(url=url, method=method, body=body, headers=headers, timeout=(3, 8), **kwargs)
        if not credentials.valid:
            credentials.refresh(auth_request)
    except Exception:
        return {}
    today = datetime.now(timezone.utc).date()
    base = f'https://earthengine.googleapis.com/v1/projects/{env.GEE_PROJECT}'

    def retrieve(layer_id):
        try:
            image, native, period = image_for_layer(ee, layer_id, polygon, today)
            metadata = ee.Dictionary({
                'native_projection': {'crs': native.crs(), 'transform': native.transform(), 'nominal_scale_m': native.nominalScale()},
                'source_period': ee.Dictionary(period),
            })
            with AuthorizedSession(credentials, auth_request=auth_request, max_refresh_attempts=0, refresh_timeout=8) as session:
                response = session.post(base+'/value:compute', json={'expression': ee.serializer.encode(metadata)}, timeout=(3, 8), stream=True)
                meta = json.loads(limited_body(response, 65536))['result']
                native_scale = float(meta['native_projection']['nominal_scale_m'])
                grid = grid_for_polygon(polygon, max(native_scale, LAYERS[layer_id]['native_resolution_m']))
                sx, _, x0, _, sy, y0 = grid['transform']
                value = image.rename('value').toFloat()
                valid = value.mask().reduce(ee.Reducer.min()).gt(0).unmask(0).rename('valid').toFloat()
                expression = value.unmask(-9999).addBands(valid)
                body = {'expression': ee.serializer.encode(expression), 'fileFormat': 'NPY', 'bandIds': ['value', 'valid'],
                        'grid': {'crsCode': 'EPSG:3857', 'dimensions': {'width': grid['width'], 'height': grid['height']},
                                 'affineTransform': {'scaleX': sx, 'shearX': 0, 'translateX': x0, 'shearY': 0, 'scaleY': sy, 'translateY': y0}}}
                response = session.post(base+'/image:computePixels', json=body, timeout=(3, 8), stream=True)
                array = np.load(io.BytesIO(limited_body(response)), allow_pickle=False, max_header_size=16384)
            if array.shape != (grid['height'], grid['width']) or not array.dtype.names or set(array.dtype.names) != {'value', 'valid'}:
                raise ValueError('Unexpected pixel array schema.')
            values = [[float(array['value'][r, c]) if array['valid'][r, c] == 1 else None for c in range(grid['width'])] for r in range(grid['height'])]
            return layer_id, {**grid, **meta, 'values': values, 'retrieved_at': now(),
                              'resampling': 'Nearest source pixel on explicit EPSG:3857 grid; nominal ground scale no finer than source. No model-sample interpolation.',
                              'mask_method': 'Original image mask plus documented cloud/complete-time-window mask; unmasked sentinel is never a valid observation.'}
        except Exception:
            return layer_id, {'reason': 'Spatial source unavailable, incomplete, oversized or invalid; no model-sample fill was substituted.'}
    # At most two sources in flight, two bounded requests per layer, seven
    # configured layers, and one credential refresh before starting workers.
    with ThreadPoolExecutor(max_workers=2) as executor:
        return dict(executor.map(retrieve, LAYERS))
