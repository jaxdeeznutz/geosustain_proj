"""New analysis path. Existing providers and forest retained; fallback values excluded."""
import logging
import math
from datetime import datetime, timezone
from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
from suitability import attach_assessment, number
from model_explainability import forest_snapshot

logger = logging.getLogger('uvicorn.error')

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
             'climate': climate_normals, 'slope': terrain_slope, 'weather': env.get_live_weather}
    with ThreadPoolExecutor(max_workers=4) as pool:
        futures = {key:pool.submit(fn,lat,lon) for key,fn in tasks.items()}
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
    measurements['humidity_current'] = {'value':number(weather[0]) if weather[4]=='measured' else None,
        'unit':'%','period':'current','quality':weather[4],'source':'OpenWeather current; not used as climate humidity'}
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
    # Preserve actual inference as an explicitly separate legacy research output.
    # Synthetic training augmentation and nutrient proxies exclude it from ranking.
    try:
        if env.MODEL is not None:
            logger.info('Legacy model loaded version=%s', env.MODEL_VERSION)
            n,p,k,nq = env.get_soil_nutrients(lat,lon)
            values = [n,p,k,result['temperature_c'],result['live_humidity'],result['soil_ph'],
                      result['rainfall_mm'],result['ndvi'],result['elevation_m'],result['slope_pct']]
            if all(number(v) is not None for v in values):
                frame = env.pd.DataFrame([values],columns=list(env.MODEL.feature_names_in_))
                probabilities = env.MODEL.predict_proba(frame)[0]
                prediction = env.MODEL.predict(frame)[0]
                logger.info('Legacy model prediction completed')
                snapshot = forest_snapshot(env.MODEL, env.MODEL_VERSION, dict(zip(frame.columns,values)),
                    prediction, {str(c):float(p) for c,p in zip(env.MODEL.classes_,probabilities)})
                snapshot['role'] = 'legacy_research_only'
                snapshot['training_provenance'] = 'Kaggle crop data plus synthetic GIS features and local rows; no Panabo field validation established.'
                snapshot['samples'][0].update(location={'lat':lat,'lon':lon},data_quality=deepcopy(quality),nutrient_quality=nq)
                result['legacy_model_explanation'] = snapshot
    except Exception as exc:
        logger.warning('Legacy model explanation unavailable type=%s',type(exc).__name__)
    assessed = attach_assessment(result,measurements,active_crops)
    logger.info('Suitability scoring completed')
    return assessed

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
    result['legacy_model_samples'] = [s['legacy_model_explanation'] for s in samples if s.get('legacy_model_explanation')]
    result.pop('legacy_model_explanation',None)
    for field,key in [('soil_ph','soil_ph'),('temperature_c','temperature'),('annual_rainfall_mm','rainfall'),
                      ('rainfall_mm','rainfall_recent'),('elevation_m','elevation'),('slope_pct','slope'),('ndvi','ndvi')]:
        result[field] = measurements.get(key,{}).get('value')
    return attach_assessment(result,measurements,active_crops)
