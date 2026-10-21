"""New analysis path. Existing providers and forest retained; fallback values excluded."""
import logging
import math
from provider_cache import retrieve
from datetime import datetime, timezone
from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
from suitability import attach_assessment, number
from model_explainability import forest_snapshot
from model_ranking import attach_model_ranking, ModelRankingUnavailable
from nutrient_contract import legacy_inputs, model_values

logger = logging.getLogger('uvicorn.error')


def current_humidity(weather, lat, lon):
    """Use provider humidity, then a coordinate-specific weather model; never a constant."""
    value = number(weather[0]) if weather[4] == 'measured' else None
    source = 'OpenWeather current'
    if value is None or not 0 <= value <= 100:
        import requests
        value = None
        source = 'Open-Meteo current relative humidity (weather model)'
        try:
            response = requests.get('https://api.open-meteo.com/v1/forecast', params={
                'latitude': lat, 'longitude': lon, 'current': 'relative_humidity_2m'}, timeout=10)
            response.raise_for_status()
            value = number(response.json().get('current', {}).get('relative_humidity_2m'))
            if value is not None and not 0 <= value <= 100:
                value = None
        except Exception as exc:
            logger.warning('Humidity backup unavailable type=%s', type(exc).__name__)
    return {'value': value, 'unit': '%', 'period': 'current',
            'quality': 'modelled' if value is not None else 'unavailable', 'source': source}

def climate_normals(lat, lon):
    """Five complete calendar years, explicitly a short baseline, not a 30-year normal."""
    import rainfallDatasets as env
    env.ensure_earth_engine_initialized()
    ee = env.ee
    year = datetime.now(timezone.utc).year
    start, end = f'{year-5}-01-01', f'{year}-01-01'
    point = ee.Geometry.Point([lon, lat])
    rain = ee.ImageCollection('UCSB-CHG/CHIRPS/DAILY').filterDate(start,end)
    temp = ee.ImageCollection('ECMWF/ERA5_LAND/DAILY_AGGR').filterDate(start,end)
    data = ee.Dictionary({
        'rainfall': rain.sum().divide(5).reduceRegion(ee.Reducer.mean(), point.buffer(750), 5000).get('precipitation'),
        'rain_days': rain.size(),
        'temperature': temp.select('temperature_2m').mean().subtract(273.15).reduceRegion(ee.Reducer.mean(), point, 11132).get('temperature_2m'),
        'temp_days': temp.size(),
    }).getInfo()
    days = (datetime(year,1,1)-datetime(year-5,1,1)).days
    output = {}
    for key, unit, period, source, count in [
        ('rainfall','mm/year','annual_mean_total','CHIRPS daily: mean of five complete annual totals','rain_days'),
        ('temperature','C','annual_mean','ERA5-Land daily mean air temperature, Kelvin minus 273.15','temp_days')]:
        value = number(data.get(key)) if data.get(count) == days else None
        output[key] = {'value':value, 'unit':unit, 'period':period, 'quality':'modelled',
            'source':source, 'start':start, 'end_exclusive':end,
            'limitation':'Five-year screening baseline; not a 30-year climatological normal. Coarse grid does not resolve individual fields.'}
    return output

def terrain_slope(lat, lon):
    import rainfallDatasets as env
    env.ensure_earth_engine_initialized()
    ee = env.ee
    degrees = ee.Terrain.slope(ee.Image('USGS/SRTMGL1_003')).reduceRegion(
        ee.Reducer.mean(), ee.Geometry.Point([lon,lat]).buffer(30), 30).get('slope').getInfo()
    return math.tan(math.radians(float(degrees))) * 100 if degrees is not None else None

def analyze_location(lat, lon, active_crops=None):
    import rainfallDatasets as env
    logger.info('Environmental retrieval started')
    measurements, raw, quality = {}, {}, {}
    tasks = {'soil_ph': env.get_soil_ph, 'elevation': env.get_elevation,
             'ndvi': env.get_ndvi, 'rainfall_recent': env.get_rainfall,
             'climate': climate_normals, 'slope': terrain_slope, 'weather': env.get_live_weather, 'nitrogen': env.get_soil_nitrogen}
    with ThreadPoolExecutor(max_workers=4) as pool:
        ttls = {'soil_ph': 86400, 'elevation': 86400, 'slope': 86400,
                'climate': 21600, 'ndvi': 3600, 'rainfall_recent': 900,
                'weather': 300, 'nitrogen': 86400}
        futures = {key:pool.submit(retrieve,key,fn,lat,lon,ttls[key]) for key,fn in tasks.items()}
        for key, future in futures.items():
            try: raw[key] = future.result()
            except Exception as exc:
                logger.warning('Environmental source unavailable factor=%s type=%s', key,type(exc).__name__)
    logger.info('Environmental retrieval completed available_sources=%s requested_sources=%s', len(raw), len(tasks))
    measurements.update(raw.get('climate') or {})
    for key, unit, period in [('soil_ph','pH','soil_surface'),('elevation','m','terrain'),
                              ('ndvi','index','latest_scene'),('rainfall_recent','mm','rolling_30_days')]:
        value, flag, source = raw.get(key, (None,'unavailable','Source unavailable'))
        value = number(value) if flag == 'measured' else None
        measurements[key] = {'value':value,'unit':unit,'period':period,'quality':'modelled' if value is not None else 'unavailable','source':source}
    measurements['slope'] = {'value':number(raw.get('slope')),'unit':'%','period':'terrain',
        'quality':'modelled','source':'SRTM 30m / ee.Terrain.slope; tan(degrees*pi/180)*100'}
    weather = raw.get('weather') or (None,None,None,None,'unavailable')
    measurements['humidity_current'] = current_humidity(weather, lat, lon)
    if not any(m.get('value') is not None for k,m in measurements.items() if k in ('soil_ph','elevation','ndvi','temperature','rainfall')):
        raise RuntimeError('environmental_datasets_unavailable')
    for key, m in measurements.items():
        quality[key] = {'quality':m['quality'], 'source':m.get('source'), 'unit':m['unit'], 'period':m['period']}
    result = {'lat':lat,'lon':lon,'environmental_measurements':measurements,'data_quality':quality,
        'data_quality_warnings':['Missing data is not replaced with regional defaults. Field verification is required.'],
        'soil_ph': measurements['soil_ph']['value'], 'elevation_m':measurements['elevation']['value'],
        'slope_pct':measurements['slope']['value'], 'ndvi':measurements['ndvi']['value'],
        'temperature_c':(measurements.get('temperature') or {}).get('value'),
        'rainfall_mm':measurements['rainfall_recent']['value'],
        'annual_rainfall_mm':(measurements.get('rainfall') or {}).get('value'),
        'live_humidity':measurements['humidity_current']['value'],
        'land_type':'Vegetation observation only', 'land_status':'Environmental screening',
        'model_explanation':None}
    # Rank with the existing model; retain input quality and training limitations.
    snapshot = None
    try:
        if env.MODEL is not None:
            logger.info('Crop model loaded version=%s', env.MODEL_VERSION)
            # Reuse the same observations already fetched for this sample.
            n, nitrogen_quality, nitrogen_source = raw.get('nitrogen', (None, 'unavailable', 'Unavailable'))
            p,k = env.estimate_phosphorus_potassium(result['ndvi'], result['soil_ph'], result['elevation_m'])
            nutrients = legacy_inputs(n, p, k, nitrogen_quality, nitrogen_source)
            nutrient_values = model_values(nutrients)
            nq = {'nitrogen': nutrients['N']['quality'], 'nitrogen_source': nitrogen_source,
                  'phosphorus': 'estimated_proxy', 'potassium': 'estimated_proxy'}
            inputs = {**nutrient_values, 'temperature': result['temperature_c'],
                      'humidity': result['live_humidity'], 'ph': result['soil_ph'],
                      'rainfall': result['rainfall_mm'], 'ndvi': result['ndvi'],
                      'elevation': result['elevation_m'], 'slope': result['slope_pct']}
            names = list(env.MODEL.feature_names_in_)
            if set(names) != set(inputs):
                raise ModelRankingUnavailable('The saved model feature contract does not match the environmental inputs.')
            missing = [name for name, value in inputs.items() if number(value) is None]
            if missing:
                logger.warning('Model inputs unavailable features=%s', ', '.join(missing))
                raise ModelRankingUnavailable('Required model inputs unavailable: ' + ', '.join(missing) + '. Please retry when environmental services recover.')
            if all(number(v) is not None for v in inputs.values()):
                inputs = {name: float(inputs[name]) for name in names}
                frame = env.pd.DataFrame([inputs], columns=names)
                probabilities = env.MODEL.predict_proba(frame)[0]
                prediction = env.MODEL.predict(frame)[0]
                logger.info('Crop model prediction completed')
                snapshot = forest_snapshot(env.MODEL, env.MODEL_VERSION, inputs,
                    prediction, {str(c):float(p) for c,p in zip(env.MODEL.classes_,probabilities)})
                snapshot['role'] = 'crop_ranking'
                snapshot['training_provenance'] = 'Kaggle crop data plus synthetic GIS features and local rows; no Panabo field validation established.'
                snapshot['samples'][0].update(location={'lat':lat,'lon':lon},data_quality=deepcopy(quality),nutrient_quality=nq)
                snapshot['samples'][0]['model_nutrient_inputs'] = nutrients
    except ModelRankingUnavailable:
        raise
    except Exception as exc:
        logger.exception('Model prediction failed type=%s',type(exc).__name__)
        raise ModelRankingUnavailable('The trained crop model could not complete this analysis. Please retry.') from exc
    if snapshot is None:
        raise ModelRankingUnavailable('The trained model or one of its required inputs is unavailable. Please retry when environmental services are available.')
    assessed = attach_assessment(result,measurements,active_crops)
    logger.info('Model ranking completed')
    return attach_model_ranking(assessed, [snapshot], active_crops)

def merge_results(samples, active_crops=None):
    """Assess parcel mean inputs; preserve samples and expose spatial limitations."""
    result = deepcopy(samples[0])
    measurements = {}
    for key in set().union(*(s['environmental_measurements'] for s in samples)):
        entries = [s['environmental_measurements'].get(key,{}) for s in samples]
        valid = [e for e in entries if number(e.get('value')) is not None]
        m = deepcopy(valid[0] if valid else entries[0])
        # Full coverage required; a sample failure cannot masquerade as complete data.
        m['value'] = sum(e['value'] for e in valid)/len(valid) if len(valid)==len(samples) else None
        m['spatial_method'] = 'Arithmetic mean of all interior samples; missing sample makes factor unavailable'
        m['samples'] = entries
        measurements[key] = m
    result['environmental_samples'] = [s['environmental_measurements'] for s in samples]
    snapshots = [s.get('model_explanation') for s in samples]
    for field,key in [('soil_ph','soil_ph'),('temperature_c','temperature'),('annual_rainfall_mm','rainfall'),
                      ('rainfall_mm','rainfall_recent'),('elevation_m','elevation'),('slope_pct','slope'),('ndvi','ndvi')]:
        result[field] = measurements.get(key,{}).get('value')
    return attach_model_ranking(attach_assessment(result,measurements,active_crops), snapshots, active_crops)
