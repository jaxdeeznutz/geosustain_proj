import ee
import joblib
import requests
import os
import json
import pandas as pd
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta
from google.oauth2 import service_account

GEE_PROJECT = os.getenv('GEE_PROJECT_ID') or os.getenv('GEE_PROJECT') or 'capstone-493314'
GEE_SERVICE_ACCOUNT_JSON = os.getenv('GEE_SERVICE_ACCOUNT_JSON')
OPENWEATHER_KEY = os.getenv('OPENWEATHER_API_KEY', 'ef57d35102fa708513cde8222753838d')
BASE_DIR = os.path.dirname(os.path.abspath(__file__))


def _asset_path(filename):
    return os.path.join(BASE_DIR, filename)



def initialize_earth_engine():
    """Initialize Google Earth Engine for Render or local development.

    On Render, paste the full service-account JSON into the
    GEE_SERVICE_ACCOUNT_JSON environment variable and set GEE_PROJECT_ID.
    Do not commit the JSON key to GitHub.
    """
    if GEE_SERVICE_ACCOUNT_JSON:
        try:
            info = json.loads(GEE_SERVICE_ACCOUNT_JSON)
            credentials = service_account.Credentials.from_service_account_info(
                info,
                scopes=['https://www.googleapis.com/auth/earthengine'],
            )
            ee.Initialize(credentials, project=GEE_PROJECT)
            print(f'Earth Engine initialized with service account for project {GEE_PROJECT}.')
            return
        except Exception as exc:
            raise RuntimeError(f'Failed to initialize Earth Engine service account: {exc}') from exc

    try:
        ee.Initialize(project=GEE_PROJECT)
        print(f'Earth Engine initialized with local/default credentials for project {GEE_PROJECT}.')
    except Exception as exc:
        # Never call ee.Authenticate() on Render because it is interactive and will crash.
        raise RuntimeError(
            'Earth Engine is not initialized. Add GEE_SERVICE_ACCOUNT_JSON and '
            'GEE_PROJECT_ID in Render Environment, or authenticate Earth Engine locally.'
        ) from exc


_EE_INITIALIZED = False
_EE_INITIALIZATION_ERROR = None


def ensure_earth_engine_initialized():
    """Initialize Earth Engine only when an analysis actually needs it.

    Keeping this out of module import lets Uvicorn bind Render's $PORT
    immediately, even when Earth Engine credentials or the network are slow.
    """
    global _EE_INITIALIZED, _EE_INITIALIZATION_ERROR
    if _EE_INITIALIZED:
        return True
    try:
        initialize_earth_engine()
        _EE_INITIALIZED = True
        _EE_INITIALIZATION_ERROR = None
        return True
    except Exception as exc:
        _EE_INITIALIZATION_ERROR = exc
        print(f'Earth Engine initialization warning: {exc}')
        raise


MODEL              = joblib.load(_asset_path('crop_model.pkl'))
ANALYSIS_CACHE     = {}
CACHE_TTL_SECONDS  = 300
CROP_COMPAT_MIN    = 70.0

# ---------------------------------------------------------------------------
# PANABO CITY CONFIG  — single place for all fallback values
# ---------------------------------------------------------------------------
# NOTE: these are last-resort regional typical values, used only when every
# real data source has failed. Every getter that can fall back to one of
# these also returns a 'fallback_default' quality flag alongside it, so
# callers (and ultimately the Farmer) can tell a genuine measurement from
# an estimate rather than the estimate being silently presented as fact.
PANABO_CONFIG = {
    'rainfall_monthly_mm': 105.0,
    'temperature_c':        27.5,
    'elevation_m':          25.0,
    'soil_ph':               6.0,
    'nitrogen':             80,
    'phosphorus_default':   47,
    'potassium_default':    50,
}

# ---------------------------------------------------------------------------
# CROP CATALOG
# ---------------------------------------------------------------------------
PANABO_CROP_MAP = {
    'banana':      'Banana (Cavendish/Lakatan)',
    'coconut':     'Coconut',
    'abaca':       'Abaca',
    'cacao':       'Cacao',
    'durian':      'Durian',
    'cassava':     'Cassava',
    'sweet potato':'Sweet Potato',
    'rubber':      'Rubber',
    'pomelo':      'Pomelo',
    'papaya':      'Papaya',
    # 'mango' has no environmental profile in the approved GeoSustain crop
    # set (Section 9) — excluded (None) rather than left dangling, so it can
    # never surface as a recommendation.
    'mango':       None,
    'coffee':      'Cacao',
    # These raw training-dataset labels have no equivalent in the approved
    # local crop set either — excluded rather than mapped to a placeholder
    # ('Mung Bean'/'Legumes') that no longer has a real profile to score against.
    'mungbean':    None,
    'pigeonpeas':  None,
    'mothbeans':   None,
    'blackgram':   None,
    'lentil':      None,
    'chickpea':    None,
    'kidneybeans': None,
    'jute':        'Abaca',
    'cotton':      'Abaca',
    'rice':        'Rice',
    'maize':       'Corn (White/Yellow)',
    'watermelon':  'Watermelon',
    'muskmelon':   'Banana (Saba)',
    'apple':       None,
    'grapes':      None,
    'pomegranate': None,
    'orange':      None,
}

CROP_DETAILS = {
    'banana (cavendish/lakatan)': {
        'label': 'Cavendish Variety (Export Grade)',
        'growth_cycle': '9-12 Months',
        'est_yield': '35 Tons / Ha',
        'suitability_note': "Thrives in Panabo's high humidity and warm temperature.",
    },
    'banana (saba)': {
        'label': 'Saba Variety (Cooking Banana)',
        'growth_cycle': '10-12 Months',
        'est_yield': '28 Tons / Ha',
        'suitability_note': "Well-suited for Panabo's soil and rainfall profile.",
    },
    'coconut': {
        'label': 'Coconut Palm',
        'growth_cycle': '36-48 Months (first harvest)',
        'est_yield': '4-6 Tons Copra / Ha',
        'suitability_note': 'Thrives in coastal and lowland areas of Davao del Norte.',
    },
    'cacao': {
        'label': 'Cacao Plantation',
        'growth_cycle': '24-36 Months',
        'est_yield': '0.8 Tons / Ha',
        'suitability_note': 'High-value crop suited for shaded agroforestry systems.',
    },
    'papaya': {
        'label': 'Papaya (Solo / Red Lady)',
        'growth_cycle': '6-9 Months',
        'est_yield': '40 Tons / Ha',
        'suitability_note': 'Fast-growing; ideal for loamy soils with good drainage.',
    },
    'abaca': {
        'label': 'Abaca (Fiber Crop)',
        'growth_cycle': '18-24 Months',
        'est_yield': '1.2 Tons / Ha',
        'suitability_note': 'Davao Region is the top abaca producer in the Philippines.',
    },
    'rice': {
        'label': 'Rice (Lowland Variety)',
        'growth_cycle': '3-4 Months',
        'est_yield': '4-5 Tons / Ha',
        'suitability_note': 'Suitable for low-lying, high-rainfall areas of Panabo.',
    },
    'corn (white/yellow)': {
        'label': 'Corn (White/Yellow Variety)',
        'growth_cycle': '3 Months',
        'est_yield': '5-7 Tons / Ha',
        'suitability_note': 'Commonly grown in Davao del Norte upland barangays.',
    },
    'watermelon': {
        'label': 'Watermelon (Local/Hybrid)',
        'growth_cycle': '2-3 Months',
        'est_yield': '20-25 Tons / Ha',
        'suitability_note': 'Grows well during dry season with irrigation support.',
    },

    'durian': {
        'label': 'Durian (Davao Variety)',
        'growth_cycle': '4-6 Years (first harvest)',
        'est_yield': '8-15 Tons / Ha',
        'suitability_note': 'High-value Mindanao fruit crop suited to warm, humid, well-drained areas.',
    },
    'cassava': {
        'label': 'Cassava / Kamoteng Kahoy',
        'growth_cycle': '8-12 Months',
        'est_yield': '15-25 Tons / Ha',
        'suitability_note': 'Tolerates drier and less fertile soils; useful for food and feed production.',
    },
    'sweet potato': {
        'label': 'Sweet Potato / Kamote',
        'growth_cycle': '3-5 Months',
        'est_yield': '8-15 Tons / Ha',
        'suitability_note': 'Short-cycle root crop suited for diversified lowland and upland farming.',
    },
    'rubber': {
        'label': 'Rubber Tree',
        'growth_cycle': '5-7 Years (tapping starts)',
        'est_yield': '1-2 Tons Dry Rubber / Ha',
        'suitability_note': 'Suitable for humid Mindanao areas with stable rainfall and well-drained soils.',
    },
    'pomelo': {
        'label': 'Pomelo',
        'growth_cycle': '3-5 Years (first harvest)',
        'est_yield': '10-20 Tons / Ha',
        'suitability_note': 'A Davao-associated fruit crop suited for warm areas with moderate rainfall.',
    },
}


# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------
def _date_window(months_back=12):
    """Rolling date window — no hardcoded years."""
    end   = datetime.utcnow()
    start = end - timedelta(days=months_back * 30)
    return start.strftime('%Y-%m-%d'), end.strftime('%Y-%m-%d')


def get_panabo_season():
    month = datetime.now().month
    if 3 <= month <= 5:
        return ('DRY SEASON (Peak Sunlight)',
                'Increase irrigation frequency due to high evaporation rates.')
    if 6 <= month <= 11:
        return ('WET SEASON (High Rainfall)',
                'Monitor field drainage to prevent waterlogging and root rot.')
    return ('COOL-DRY SEASON',
            'Ideal for land preparation, soil amendment, and planting.')


# ---------------------------------------------------------------------------
# LIVE WEATHER
# ---------------------------------------------------------------------------
def get_live_weather(lat, lon):
    """Returns (humidity_pct, description, wind_speed_ms, cloud_cover_pct, quality).
    quality is 'measured' or 'fallback_default'."""
    url = (f'https://api.openweathermap.org/data/2.5/weather'
           f'?lat={lat}&lon={lon}&appid={OPENWEATHER_KEY}&units=metric')
    try:
        resp = requests.get(url, timeout=6).json()
        return (resp['main']['humidity'],
                resp['weather'][0]['description'],
                resp.get('wind', {}).get('speed', 0.0),
                resp.get('clouds', {}).get('all', 0),
                'measured')
    except Exception:
        return 80, 'Condition unavailable', 0.0, 0, 'fallback_default'


# ---------------------------------------------------------------------------
# GEE ACQUISITION
# ---------------------------------------------------------------------------
def _open_meteo_recent_monthly_rainfall(lat, lon):

    headers = {"User-Agent": "GeoSustainCapstone/1.0"}
    end_date = datetime.utcnow().date() - timedelta(days=1)
    start_date = end_date - timedelta(days=29)

    urls = [
        (
            "https://api.open-meteo.com/v1/forecast"
            f"?latitude={lat}&longitude={lon}"
            "&daily=precipitation_sum"
            "&past_days=31&forecast_days=1"
            "&timezone=Asia%2FManila"
        ),
        (
            "https://archive-api.open-meteo.com/v1/archive"
            f"?latitude={lat}&longitude={lon}"
            f"&start_date={start_date.isoformat()}&end_date={end_date.isoformat()}"
            "&daily=precipitation_sum&timezone=Asia%2FManila"
        ),
    ]

    for url in urls:
        try:
            resp = requests.get(url, headers=headers, timeout=15)
            if resp.status_code >= 400:
                print(f"Open-Meteo rainfall HTTP {resp.status_code}: {resp.text[:180]}")
                continue

            data = resp.json()
            daily = data.get("daily", {}) or {}
            vals = daily.get("precipitation_sum", []) or []

            numeric_vals = []
            for value in vals:
                if value is None:
                    continue
                try:
                    numeric_vals.append(float(value))
                except (TypeError, ValueError):
                    pass

            if numeric_vals:
                total = round(sum(numeric_vals[-30:]), 2)
                # 0 mm is a valid rainfall total, so do not treat it as failure.
                return max(0.0, total)
        except Exception as exc:
            print(f"Open-Meteo rainfall failed for {url.split('?')[0]}: {exc}")

    return None

def get_rainfall(lat, lon):
    """Recent rolling 30-day rainfall total in mm for the selected coordinate.

    Primary source: CHIRPS DAILY in Google Earth Engine. CHIRPS has a finer
    rainfall grid than Open-Meteo for small study areas, so it is better for
    Panabo barangay/parcel testing. Open-Meteo is only a backup.

    Returns (value_mm, quality, source_label). quality is 'measured' when a
    real source answered, 'fallback_default' when every real source failed
    and a fixed regional typical value had to be used instead.

    THREAD-SAFETY NOTE: this used to report its source via a shared module
    global (`LAST_RAINFALL_SOURCE`), which is unsafe — polygon analysis runs
    several of these concurrently (one per sampled point within a farm), so
    one thread's write could silently clobber another's before it was read,
    corrupting which sample a given source label actually described. This
    now returns everything the caller needs directly, with no shared state.
    """
    start = (datetime.utcnow() - timedelta(days=30)).strftime('%Y-%m-%d')
    end = datetime.utcnow().strftime('%Y-%m-%d')

    # 1) Primary: CHIRPS 30-day precipitation sum from Earth Engine
    try:
        ensure_earth_engine_initialized()
        chirps = ee.ImageCollection('UCSB-CHG/CHIRPS/DAILY')
        point  = ee.Geometry.Point([lon, lat])
        val    = (chirps.filterBounds(point).filterDate(start, end)
                        .sum().reduceRegion(
                            reducer=ee.Reducer.mean(),
                            geometry=point.buffer(750),
                            scale=5000,
                            bestEffort=True
                        ).get('precipitation').getInfo())
        if val is not None:
            total = round(float(val), 2)
            if total >= 0:
                return total, 'measured', 'CHIRPS Daily (Google Earth Engine), 30-day sum'
    except Exception as exc:
        print(f'CHIRPS rainfall failed: {exc}')

    # 2) Backup: Open-Meteo archive/reanalysis
    open_meteo_rain = _open_meteo_recent_monthly_rainfall(lat, lon)
    if open_meteo_rain is not None and open_meteo_rain >= 0:
        return open_meteo_rain, 'measured', 'Open-Meteo Archive (backup), 30-day sum'

    # 3) Last resort — an honest regional typical value, clearly flagged as
    # such rather than presented as a genuine reading.
    return PANABO_CONFIG['rainfall_monthly_mm'], 'fallback_default', 'Regional typical value — live rainfall source unavailable'


def get_temperature(lat, lon):
    """Returns (value_c, quality, source_label)."""
    start, end = _date_window(12)
    try:
        ensure_earth_engine_initialized()
        point  = ee.Geometry.Point([lon, lat])
        kelvin = (ee.ImageCollection('ECMWF/ERA5_LAND/DAILY_AGGR')
                    .filterBounds(point).filterDate(start, end)
                    .mean().sample(point, 30).first().get('temperature_2m'))
        val = ee.Number(kelvin).subtract(273.15).getInfo()
        if val:
            return float(val), 'measured', 'ERA5-Land Daily Aggregate (Google Earth Engine), 12-month mean'
        return PANABO_CONFIG['temperature_c'], 'fallback_default', 'Regional typical value — live temperature source unavailable'
    except Exception:
        return PANABO_CONFIG['temperature_c'], 'fallback_default', 'Regional typical value — live temperature source unavailable'


def get_elevation(lat, lon):
    """Returns (value_m, quality, source_label)."""
    try:
        ensure_earth_engine_initialized()
        point = ee.Geometry.Point([lon, lat])
        val   = (ee.Image('USGS/SRTMGL1_003')
                   .sample(point, 30).first().get('elevation').getInfo())
        if val:
            return float(val), 'measured', 'SRTM 30m DEM (Google Earth Engine)'
        return PANABO_CONFIG['elevation_m'], 'fallback_default', 'Regional typical value — elevation source unavailable'
    except Exception:
        return PANABO_CONFIG['elevation_m'], 'fallback_default', 'Regional typical value — elevation source unavailable'


def get_ndvi(lat, lon):
    """Rolling 18-month window, most recent low-cloud Sentinel-2.
    Returns (value, quality, source_label)."""
    start, end = _date_window(18)
    try:
        ensure_earth_engine_initialized()
        s2    = ee.ImageCollection('COPERNICUS/S2_SR_HARMONIZED')
        point = ee.Geometry.Point([lon, lat])
        image = (s2.filterBounds(point).filterDate(start, end)
                   .filter(ee.Filter.lt('CLOUDY_PIXEL_PERCENTAGE', 20))
                   .sort('system:time_start', False).first())
        if image is None:
            return 0.45, 'fallback_default', 'Regional typical value — no cloud-free Sentinel-2 scene in window'
        val = (image.normalizedDifference(['B8', 'B4'])
                    .rename('NDVI').sample(point, 10).first().get('NDVI').getInfo())
        if val:
            return float(val), 'measured', 'Sentinel-2 SR Harmonized (Google Earth Engine), most recent low-cloud scene'
        return 0.45, 'fallback_default', 'Regional typical value — NDVI source unavailable'
    except Exception:
        return 0.45, 'fallback_default', 'Regional typical value — NDVI source unavailable'


def get_soil_ph(lat, lon):
    """Returns (value, quality, source_label)."""
    try:
        ensure_earth_engine_initialized()
        point  = ee.Geometry.Point([lon, lat])
        sample = (ee.Image('OpenLandMap/SOL/SOL_PH-H2O_USDA-4C1A2A_M/v02')
                    .sample(point, 250).first())
        ph_band = sample.get('b0') if sample else None
        val     = ee.Number(ph_band).divide(10).getInfo() if ph_band else None
        if val:
            return float(val), 'measured', 'OpenLandMap Soil pH (Google Earth Engine)'
        return PANABO_CONFIG['soil_ph'], 'fallback_default', 'Regional typical value — soil pH source unavailable'
    except Exception:
        return PANABO_CONFIG['soil_ph'], 'fallback_default', 'Regional typical value — soil pH source unavailable'


def get_soil_nitrogen(lat, lon):
    """Returns (value, quality, source_label)."""
    try:
        ensure_earth_engine_initialized()
        point = ee.Geometry.Point([lon, lat])
    except Exception:
        return PANABO_CONFIG['nitrogen'], 'fallback_default', 'Regional typical value — soil nitrogen source unavailable'

    # Primary: SoilGrids 2.0
    try:
        n_raw = (ee.Image('projects/soilgrids-isric/nitrogen_mean')
                   .select('nitrogen_0-5cm_mean')
                   .sample(point, 250).first().get('nitrogen_0-5cm_mean'))
        val = ee.Number(n_raw).getInfo() if n_raw else None
        if val is not None:
            n_gkg    = float(val) / 100.0
            nitrogen = max(20, min(120, round(n_gkg * 6)))
            return nitrogen, 'measured', 'SoilGrids 2.0 nitrogen (Google Earth Engine), 0-5cm'
    except Exception:
        pass

    try:
        n_raw = (ee.Image('OpenLandMap/SOL/SOL_STN_USDA-4C1A2A_M/v02')
                   .sample(point, 250).first().get('b0'))
        val = float(ee.Number(n_raw).getInfo()) if n_raw else None
        if val is not None:
            return max(20, min(120, round(float(val) * 0.7))), 'measured', 'OpenLandMap Soil Nitrogen (Google Earth Engine, backup)'
    except Exception:
        pass

    return PANABO_CONFIG['nitrogen'], 'fallback_default', 'Regional typical value — soil nitrogen source unavailable'


def estimate_phosphorus_potassium(ndvi_val, ph_val, elev_val):
    """
    Estimate P and K from observable proxies (NDVI, pH, elevation).

    IMPORTANT: This function must stay crop-neutral. The previous version used a
    high-NDVI + pH condition that returned a banana-like P/K profile (P=81,K=50),
    causing the ML model to recommend banana too often. This version estimates
    nutrient availability continuously from land/soil signals only, without
    implying any crop class.
    """
    try:
        ndvi_val = float(ndvi_val)
        ph_val = float(ph_val)
        elev_val = float(elev_val)
    except Exception:
        return PANABO_CONFIG['phosphorus_default'], PANABO_CONFIG['potassium_default']

    # Base values for ordinary Panabo agricultural land.
    p = 48.0
    k = 42.0

    # Vegetation vigor affects expected nutrient availability, but not as a crop label.
    if ndvi_val >= 0.75:
        p += 14
        k += 10
    elif ndvi_val >= 0.55:
        p += 8
        k += 6
    elif ndvi_val >= 0.40:
        p += 2
        k += 2
    else:
        p -= 8
        k -= 6

    # Upland/steeper areas often have lower available P/K due to erosion/leaching.
    if elev_val > 150:
        p -= 8
        k -= 8
    elif elev_val > 80:
        p -= 4
        k -= 4

    # Very acidic or alkaline pH lowers nutrient availability.
    if ph_val < 5.3 or ph_val > 7.3:
        p -= 6
        k -= 4
    elif 5.8 <= ph_val <= 6.8:
        p += 3
        k += 2

    return int(max(20, min(72, round(p)))), int(max(25, min(65, round(k))))


def get_soil_nutrients(lat, lon):
    """Returns (nitrogen, phosphorus, potassium, quality_info).
    quality_info = {'nitrogen': 'measured'|'fallback_default',
                     'phosphorus': 'estimated_proxy', 'potassium': 'estimated_proxy'}
    Phosphorus/potassium are ALWAYS a formula-based estimate from NDVI/pH/
    elevation proxies — GeoSustain has no direct soil P/K test integration —
    so they are honestly labeled 'estimated_proxy' rather than presented as
    a genuine lab measurement."""
    nitrogen, nitrogen_quality, nitrogen_source = get_soil_nitrogen(lat, lon)

    # Fetch observable proxies for P/K estimation
    try:
        ndvi_pk, _, _ = get_ndvi(lat, lon)
    except Exception:
        ndvi_pk = 0.45
    try:
        ph_pk, _, _ = get_soil_ph(lat, lon)
    except Exception:
        ph_pk = PANABO_CONFIG['soil_ph']
    try:
        elev_pk, _, _ = get_elevation(lat, lon)
    except Exception:
        elev_pk = PANABO_CONFIG['elevation_m']

    phosphorus, potassium = estimate_phosphorus_potassium(ndvi_pk, ph_pk, elev_pk)
    quality_info = {
        'nitrogen': nitrogen_quality,
        'nitrogen_source': nitrogen_source,
        'phosphorus': 'estimated_proxy',
        'potassium': 'estimated_proxy',
    }
    return nitrogen, phosphorus, potassium, quality_info


# ---------------------------------------------------------------------------
# AI PREDICTION
# ---------------------------------------------------------------------------
def get_panabo_recommendation(raw_prediction):
    return PANABO_CROP_MAP.get(raw_prediction.lower().strip())


def _suitability_label(pct):
    if pct >= 75:  return 'HIGHLY SUITABLE'
    if pct >= 50:  return 'SUITABLE'
    if pct >= 25:  return 'MODERATELY SUITABLE'
    return 'LOW SUITABILITY'


def _range_fit(value, ideal_min, ideal_max, hard_min=None, hard_max=None):
    """Return 0-1 suitability for one environmental variable.
    Ideal range gets full score, then it gradually drops outside the ideal range.
    """
    try:
        v = float(value)
    except Exception:
        return 0.55
    if hard_min is None:
        hard_min = ideal_min - (ideal_max - ideal_min)
    if hard_max is None:
        hard_max = ideal_max + (ideal_max - ideal_min)
    if ideal_min <= v <= ideal_max:
        return 1.0
    if v < ideal_min:
        if v <= hard_min:
            return 0.0
        return (v - hard_min) / max(0.0001, ideal_min - hard_min)
    if v >= hard_max:
        return 0.0
    return (hard_max - v) / max(0.0001, hard_max - ideal_max)


# Localized crop profiles used only to rank/score the model output fairly.
# This prevents one crop from dominating everywhere while still keeping the ML model
# as the main source of crop candidates.
CROP_ENV_PROFILES = {
    'banana (cavendish/lakatan)': {
        'temp': (25, 31, 20, 36), 'humidity': (70, 95, 55, 100), 'ph': (5.5, 7.0, 4.8, 7.8),
        'rain': (90, 260, 35, 380), 'ndvi': (0.45, 0.85, 0.25, 0.95), 'elevation': (0, 220, 0, 450), 'slope': (0, 8, 0, 18),
    },
    'banana (saba)': {
        'temp': (24, 32, 20, 37), 'humidity': (65, 95, 50, 100), 'ph': (5.5, 7.2, 4.8, 8.0),
        'rain': (80, 240, 30, 360), 'ndvi': (0.42, 0.85, 0.22, 0.95), 'elevation': (0, 260, 0, 500), 'slope': (0, 10, 0, 20),
    },
    'rice': {
        'temp': (23, 32, 18, 38), 'humidity': (70, 98, 55, 100), 'ph': (5.5, 7.0, 4.8, 8.0),
        'rain': (120, 360, 60, 520), 'ndvi': (0.38, 0.82, 0.18, 0.95), 'elevation': (0, 120, 0, 260), 'slope': (0, 3.5, 0, 9),
    },
    'watermelon': {
        'temp': (24, 32, 20, 36), 'humidity': (55, 82, 35, 95), 'ph': (6.0, 7.5, 5.2, 8.2),
        'rain': (25, 105, 5, 180), 'ndvi': (0.28, 0.65, 0.12, 0.82), 'elevation': (0, 160, 0, 320), 'slope': (0, 6, 0, 14),
    },
    'corn (white/yellow)': {
        'temp': (22, 32, 18, 38), 'humidity': (55, 88, 35, 100), 'ph': (5.5, 7.5, 4.8, 8.3),
        'rain': (60, 180, 20, 300), 'ndvi': (0.32, 0.75, 0.15, 0.9), 'elevation': (0, 300, 0, 650), 'slope': (0, 10, 0, 22),
    },
    'cacao': {
        'temp': (22, 31, 18, 35), 'humidity': (70, 95, 55, 100), 'ph': (5.5, 7.0, 4.8, 7.8),
        'rain': (100, 280, 45, 420), 'ndvi': (0.45, 0.88, 0.25, 0.98), 'elevation': (20, 350, 0, 650), 'slope': (0, 12, 0, 26),
    },
    'coconut': {
        'temp': (24, 33, 20, 38), 'humidity': (65, 95, 50, 100), 'ph': (5.2, 7.8, 4.5, 8.5),
        'rain': (80, 260, 30, 400), 'ndvi': (0.38, 0.85, 0.18, 0.95), 'elevation': (0, 160, 0, 320), 'slope': (0, 8, 0, 18),
    },
    'papaya': {
        'temp': (24, 32, 20, 37), 'humidity': (60, 88, 40, 98), 'ph': (5.8, 7.2, 5.0, 8.0),
        'rain': (55, 170, 20, 280), 'ndvi': (0.34, 0.76, 0.16, 0.9), 'elevation': (0, 220, 0, 450), 'slope': (0, 8, 0, 18),
    },
    'abaca': {
        'temp': (20, 32, 16, 36), 'humidity': (75, 100, 60, 100), 'ph': (5.0, 6.5, 4.3, 7.3),
        'rain': (150, 350, 70, 480), 'ndvi': (0.45, 0.90, 0.25, 0.98), 'elevation': (0, 600, 0, 1000), 'slope': (0, 20, 0, 35),
    },
    'durian': {
        'temp': (24, 32, 20, 36), 'humidity': (75, 100, 55, 100), 'ph': (5.5, 6.5, 4.8, 7.3),
        'rain': (150, 380, 60, 500), 'ndvi': (0.45, 0.90, 0.25, 0.98), 'elevation': (0, 500, 0, 900), 'slope': (0, 15, 0, 28),
    },
    'rubber': {
        'temp': (24, 32, 20, 36), 'humidity': (70, 95, 55, 100), 'ph': (4.5, 6.5, 3.8, 7.3),
        'rain': (150, 300, 60, 420), 'ndvi': (0.45, 0.88, 0.25, 0.98), 'elevation': (0, 400, 0, 700), 'slope': (0, 25, 0, 40),
    },
    'pomelo': {
        'temp': (22, 32, 18, 36), 'humidity': (60, 90, 40, 98), 'ph': (5.5, 6.5, 4.8, 7.3),
        'rain': (60, 200, 20, 320), 'ndvi': (0.35, 0.78, 0.16, 0.9), 'elevation': (0, 600, 0, 950), 'slope': (0, 15, 0, 28),
    },
    'cassava': {
        'temp': (24, 34, 19, 39), 'humidity': (50, 85, 30, 98), 'ph': (5.0, 7.2, 4.3, 8.2),
        'rain': (45, 170, 10, 300), 'ndvi': (0.25, 0.72, 0.10, 0.9), 'elevation': (0, 350, 0, 800), 'slope': (0, 14, 0, 28),
    },
    'sweet potato': {
        'temp': (22, 32, 18, 38), 'humidity': (50, 85, 30, 98), 'ph': (5.5, 6.8, 4.8, 7.8),
        'rain': (45, 150, 10, 260), 'ndvi': (0.25, 0.70, 0.10, 0.88), 'elevation': (0, 350, 0, 750), 'slope': (0, 12, 0, 26),
    },
}


def _environment_score(crop_name, temp, humidity, ph, rain, ndvi, elevation, slope):
    profile = CROP_ENV_PROFILES.get(str(crop_name).lower())
    if not profile:
        return 58.0
    values = {
        'temp': temp, 'humidity': humidity, 'ph': ph, 'rain': rain,
        'ndvi': ndvi, 'elevation': elevation, 'slope': slope,
    }
    weights = {
        'rain': 1.35, 'ndvi': 1.25, 'temp': 1.05, 'humidity': 0.95,
        'ph': 0.95, 'elevation': 0.8, 'slope': 0.75,
    }
    total = 0.0
    weight_sum = 0.0
    for key, weight in weights.items():
        ideal_min, ideal_max, hard_min, hard_max = profile[key]
        total += _range_fit(values[key], ideal_min, ideal_max, hard_min, hard_max) * weight
        weight_sum += weight
    return round((total / weight_sum) * 100.0, 1)


def _crop_adjustment(crop_name, rain, humidity, ndvi, slope, ph):
    """Penalty-only checks for clear agronomic mismatches (no crop gets a bonus)."""
    crop = str(crop_name).lower()
    adj = 0.0

    if 'watermelon' in crop:
        if ndvi >= 0.52:
            adj -= 10.0
        if humidity >= 78:
            adj -= 8.0
        if rain > 115:
            adj -= 8.0

    if crop == 'rice':
        if rain < 55:
            adj -= 10.0
        if slope > 6:
            adj -= 8.0

    if 'banana' in crop and rain < 45:
        adj -= 8.0

    if 'corn' in crop and rain > 200:
        adj -= 6.0

    if slope > 14:
        adj -= 6.0

    if ph < 5.2 or ph > 8.0:
        adj -= 4.0

    return max(-20.0, min(0.0, adj))


def get_ai_prediction(n, p, k, temp, humidity, ph, rain, ndvi, elevation, slope, active_crops=None):
    # Fair blend: trained model (soil + weather + GIS features) and satellite/weather
    # field fit are weighted equally. No manual bonus for any single crop.
    # `active_crops`, if given, is a set of crop_key strings (from the Super
    # Administrator's crop reference table) — when present, only those crops
    # are considered as candidates. This can only ever NARROW the approved
    # crop set (Section 9); it is never a way to add a crop outside
    # CROP_ENV_PROFILES, since candidates are still built strictly from that
    # dict below.
    ML_WEIGHT = 0.50
    ENV_WEIGHT = 0.50

    input_df = pd.DataFrame([{
        'N': n, 'P': p, 'K': k,
        'temperature': temp, 'humidity': humidity, 'ph': ph, 'rainfall': rain,
        'ndvi': ndvi, 'elevation': elevation, 'slope': slope,
    }])
    raw_prediction = MODEL.predict(input_df)[0]

    baseline_rain = float(PANABO_CONFIG.get('rainfall_monthly_mm', 105.0))
    crop_rain = (0.65 * baseline_rain) + (0.35 * float(rain or baseline_rain))

    ml_relative_by_crop = {}
    ml_probability_pct_by_crop = {}
    if hasattr(MODEL, 'predict_proba'):
        probs = MODEL.predict_proba(input_df)[0]
        ranked = sorted(zip(MODEL.classes_, probs), key=lambda x: -x[1])
        top_prob = max(float(ranked[0][1]), 0.0001) if ranked else 0.0001
        for crop_label, prob in ranked:
            panabo_crop = get_panabo_recommendation(crop_label)
            if panabo_crop is None:
                # No mapping to an approved local crop (Section 9) — this raw
                # training-set label is excluded entirely rather than
                # resurrected under its own (unapproved) name.
                continue
            key = str(panabo_crop).lower()
            rel = max(0.0, min(1.0, float(prob) / top_prob))
            ml_relative_by_crop[key] = max(ml_relative_by_crop.get(key, 0.0), rel)
            ml_probability_pct_by_crop[key] = max(
                ml_probability_pct_by_crop.get(key, 0.0),
                round(float(prob) * 100.0, 2),
            )

    candidates = {}
    for key, profile in CROP_ENV_PROFILES.items():
        if active_crops is not None and key not in active_crops:
            continue  # temporarily disabled by a Super Administrator
        crop_name = key.title()
        for pretty in CROP_DETAILS.keys():
            if pretty == key:
                crop_name = CROP_DETAILS[pretty].get('display_name', pretty.title())
        if key in CROP_DETAILS:
            crop_name = key.title()

        env_score = _environment_score(key, temp, humidity, ph, crop_rain, ndvi, elevation, slope)
        rel = ml_relative_by_crop.get(key)
        if rel is not None:
            ml_score = 25.0 + (70.0 * rel)
        else:
            # Crop not in training labels: neutral ML contribution, env still applies.
            ml_score = 50.0
        final_score = (ML_WEIGHT * ml_score) + (ENV_WEIGHT * env_score)
        final_score += _crop_adjustment(key, crop_rain, humidity, ndvi, slope, ph)

        raw_score = round(max(15.0, min(100.0, final_score)), 2)
        prob_pct = ml_probability_pct_by_crop.get(key)
        candidates[key] = {
            'crop': crop_name,
            'compatibility_pct': raw_score,
            'raw_score': raw_score,
            'model_probability_pct': prob_pct,
            'environment_fit_pct': env_score,
            'ml_score_component': round(ml_score, 1),
        }

    ranked_crops = sorted(candidates.values(), key=lambda x: -x['raw_score'])
    top_crops = ranked_crops[:5]

    # Presentation scores follow raw field fit so different parcels show
    # different percentages (avoids every top crop displaying as ~68.2%).
    if top_crops:
        top_raw = float(top_crops[0]['raw_score'])
        floor_raw = float(top_crops[-1]['raw_score'])
        spread = max(1.0, top_raw - floor_raw)
        calibrated = []
        rank_steps = [0.0, 10.0, 18.0, 26.0, 34.0]
        # Map raw score to display: weak sites ~45%, strong sites up to ~88%.
        top_display = 38.0 + (top_raw * 0.50)
        top_display = max(45.0, min(88.0, top_display))
        for idx, crop in enumerate(top_crops):
            raw = float(crop['raw_score'])
            normalized = (raw - floor_raw) / spread
            separation = rank_steps[min(idx, len(rank_steps) - 1)]
            if idx == 0:
                display = top_display
            else:
                display = top_display - separation + (normalized * 2.2)
                display = min(display, top_display - (7.0 + (idx * 2.5)))
            crop = dict(crop)
            crop['compatibility_pct'] = round(max(25.0, min(92.0, display)), 1)
            calibrated.append(crop)
        top_crops = sorted(calibrated, key=lambda x: -x['compatibility_pct'])
    if not top_crops:
        # Defensive fallback — CROP_ENV_PROFILES always has entries, so this
        # branch should be unreachable in practice. If it is ever reached,
        # fall back to an approved crop rather than risk surfacing a raw,
        # unapproved training-set label (Section 9).
        fallback_key = next(iter(CROP_ENV_PROFILES), None)
        fallback_name = fallback_key.title() if fallback_key else 'No suitable crop match'
        top_crops.append({'crop': fallback_name, 'compatibility_pct': 50.0, 'model_probability_pct': None})
    return raw_prediction, top_crops


def build_xai_explanation(crop_name, crop_score, top_crops, temp, humidity, ph, rain, ndvi, elevation, slope):
    """Create a local, model-grounded explanation for the selected parcel.

    The explanation combines the trained model's ranked output with per-feature
    environmental fit for the winning crop. This is intentionally transparent:
    each statement is tied to a measured input and the crop's learned/localized
    suitability range rather than a generic sentence.
    """
    key = str(crop_name or '').lower()
    profile = CROP_ENV_PROFILES.get(key)
    if not profile:
        return {
            'method': 'Model ranking with local environmental feature analysis',
            'summary': f'{crop_name} ranked first with an estimated suitability of {crop_score:.1f}%.',
            'plain_summary': f'{crop_name} looks like a solid option for this land.',
            'supporting_factors': [],
            'limiting_factors': [],
            'comparison': '',
        }

    values = {
        'rain': float(rain), 'ndvi': float(ndvi), 'temp': float(temp),
        'humidity': float(humidity), 'ph': float(ph),
        'elevation': float(elevation), 'slope': float(slope),
    }
    labels = {
        'rain': ('30-day rainfall', 'mm'), 'ndvi': ('vegetation index (NDVI)', ''),
        'temp': ('temperature', '°C'), 'humidity': ('humidity', '%'),
        'ph': ('soil pH', ''), 'elevation': ('elevation', 'm'),
        'slope': ('slope', '%'),
    }
    weights = {'rain': 1.35, 'ndvi': 1.25, 'temp': 1.05, 'humidity': 0.95,
               'ph': 0.95, 'elevation': 0.8, 'slope': 0.75}
    ranked_features = []
    for feature, value in values.items():
        ideal_min, ideal_max, hard_min, hard_max = profile[feature]
        fit = _range_fit(value, ideal_min, ideal_max, hard_min, hard_max)
        ranked_features.append((fit * weights[feature], fit, feature, value, ideal_min, ideal_max))

    ranked_features.sort(reverse=True)
    supporting = []
    limiting = []
    for _, fit, feature, value, ideal_min, ideal_max in ranked_features:
        label, unit = labels[feature]
        value_text = f'{value:.2f}'.rstrip('0').rstrip('.')
        range_text = f'{ideal_min:g}–{ideal_max:g}{unit}'
        if fit >= 0.78 and len(supporting) < 4:
            supporting.append(
                f'{label.capitalize()} is {value_text}{unit}, which is within or close to the preferred {range_text} range for {crop_name}.'
            )
        elif fit < 0.55 and len(limiting) < 2:
            limiting.append(
                f'{label.capitalize()} at {value_text}{unit} is outside the strongest {range_text} range and reduced the final suitability score.'
            )

    comparison = ''
    if top_crops and len(top_crops) > 1:
        second = top_crops[1]
        gap = max(0.0, float(crop_score) - float(second.get('compatibility_pct') or 0))
        comparison = (
            f'{crop_name} ranked above {second.get("crop", "the next crop")} by {gap:.1f} percentage points '
            'because its combined model score and local environmental fit were higher for this parcel.'
        )

    # A short, plain-language version for the Farmer-facing app (Section 11:
    # "keep wording understandable for non-technical Farmers"). Built from
    # the SAME ranked_features computed above rather than recomputing —
    # just worded in everyday language with no raw decimal numbers, and
    # using simpler labels than the technical factor sentences above
    # (e.g. "greenery" instead of "vegetation index (NDVI)").
    plain_labels = {
        'rain': 'rainfall', 'ndvi': 'greenery', 'temp': 'temperature',
        'humidity': 'humidity', 'ph': 'soil', 'elevation': 'land height', 'slope': 'slope',
    }
    good_labels = [plain_labels[f] for _, fit, f, *_ in ranked_features if fit >= 0.78][:2]
    bad_labels = [plain_labels[f] for _, fit, f, *_ in ranked_features if fit < 0.55][:1]
    if good_labels:
        plain_summary = f"Good match — your {' and '.join(good_labels)} suit {crop_name} well."
    else:
        plain_summary = f"{crop_name} is the best option here, though conditions are only an average match."
    if bad_labels:
        plain_summary += f" One thing to watch: {bad_labels[0]} isn't quite ideal for this crop."

    return {
        'method': 'Local feature-contribution explanation using the trained crop model ranking and parcel-specific environmental fit',
        'summary': (
            f'{crop_name} was selected as the best match with {float(crop_score):.1f}% suitability. '
            'The explanation below shows the measured conditions that contributed most to that result.'
        ),
        'plain_summary': plain_summary,
        'supporting_factors': supporting,
        'limiting_factors': limiting,
        'comparison': comparison,
    }



def build_land_assessment_explanation(land_profile, ndvi, elevation, slope, rainfall, infrastructure_profile):
    """Create a concise Explainable-AI style explanation for non-arable results.

    This is not a crop explanation. It explains why crop prediction was stopped
    and how the infrastructure/risk score should be interpreted by planners.
    """
    land_type = str(land_profile.get('land_type') or 'non-arable').lower()
    land_status = str(land_profile.get('land_status') or 'NON-ARABLE AREA')
    infra_score = float(infrastructure_profile.get('infrastructure_score') or 0)
    infra_label = str(infrastructure_profile.get('infrastructure_suitability') or 'REVIEW REQUIRED')

    if land_type == 'water':
        summary = (
            'Crop recommendation was stopped because the selected location shows an extremely low vegetation index '
            'consistent with water, flooded ground, or another non-arable surface.'
        )
        plain_summary = "This spot looks like it's underwater or flooded, so we can't suggest a crop for it right now."
        reasons = [
            f'NDVI is {float(ndvi):.3f}, which is below the threshold used for vegetated agricultural land.',
            'Permanent crop establishment is not recommended until the site is confirmed as dry, stable, and legally available for cultivation.',
        ]
        advice = 'Confirm the boundary on site and review drainage, flood exposure, riparian setbacks, and possible aquaculture or water-management use.'
    elif land_type == 'infrastructure':
        summary = (
            'Crop recommendation was stopped because the selected area has very low vegetation and is more consistent '
            'with a built-up, paved, bare, or infrastructure-dominated surface.'
        )
        plain_summary = "This looks like bare or built-up land rather than farmland, so we can't suggest a crop here."
        reasons = [
            f'NDVI is {float(ndvi):.3f}, indicating limited active vegetation inside the selected area.',
            f'The preliminary infrastructure score is {infra_score:.0f}% ({infra_label.title()}).',
        ]
        advice = 'Review zoning, land conversion, drainage, access, ownership, and environmental constraints before any agricultural or infrastructure development.'
    else:
        summary = (
            'Crop recommendation was stopped because vegetation is too weak for a reliable crop match and the parcel '
            'needs rehabilitation or field validation first.'
        )
        plain_summary = "This land has very little plant cover right now, so the soil likely needs some improvement before planting."
        reasons = [
            f'NDVI is {float(ndvi):.3f}, showing low vegetation cover or stressed ground conditions.',
            f'Slope is {float(slope):.1f}% and recent rainfall is {float(rainfall):.1f} mm; these conditions should be reviewed together with soil condition.',
        ]
        advice = 'Use cover crops, organic amendments, erosion control, and a local soil test before repeating the crop analysis.'

    return {
        'method': 'Land-condition and infrastructure-risk explanation based on measured NDVI, terrain, rainfall, and the preliminary infrastructure score',
        'summary': summary,
        'plain_summary': plain_summary,
        'supporting_factors': reasons,
        'limiting_factors': [],
        'comparison': '',
        'planning_advice': advice,
        'land_status': land_status,
    }

def classify_land(ndvi_val, elev_val):
    # Water detection: NDVI ≤ 0.08 reliably covers open water, rivers, coastal sea,
    # and shallow flooded areas. SRTM elevation is unreliable over water bodies
    # (can return non-zero values from bathymetry artifacts), so elevation is NOT
    # used as a gating condition here.
    if ndvi_val <= 0.08:
        return {'land_type': 'water', 'recommendation_title': 'WATER AREA ADVISORY',
                'land_status': 'WATER / FLOODED AREA', 'recommendation': 'NO CROP RECOMMENDED',
                'land_use_recommendations': ['Aquaculture zones (bangus, tilapia)',
                    'Water storage and irrigation reserve', 'Riparian buffer restoration'],
                'is_crop_recommended': False}
    if ndvi_val < 0.20:
        return {'land_type': 'infrastructure', 'recommendation_title': 'LAND USE RECOMMENDATION',
                'land_status': 'INFRASTRUCTURE / BARE LAND', 'recommendation': 'NON-CROP LAND USE PRIORITIZED',
                'land_use_recommendations': ['Solar-ready utility or storage area',
                    'Post-harvest / processing facilities', 'Container-based urban farming trials'],
                'is_crop_recommended': False}
    if ndvi_val < 0.35:
        return {'land_type': 'degraded', 'recommendation_title': 'LAND REHABILITATION RECOMMENDATION',
                'land_status': 'DEGRADED / LOW VEGETATION', 'recommendation': 'SOIL REHABILITATION REQUIRED FIRST',
                'land_use_recommendations': ['Cover crops and green manure (legume blend)',
                    'Vetiver or napier grass for soil binding', 'Nitrogen-fixing legumes as first rotation'],
                'is_crop_recommended': False}
    return {'land_type': 'arable', 'recommendation_title': 'RECOMMENDED CROP MATCH',
            'land_status': 'ARABLE / VEGETATED', 'recommendation': '',
            'land_use_recommendations': [], 'is_crop_recommended': True}


def estimate_slope_percent(lat, lon, center_elev=None):
    """Approximate terrain slope from small nearby elevation samples.
    This avoids adding a new dataset while still supporting the panel's
    requested infrastructure suitability feature.

    `center_elev`, if provided, must be a plain elevation value in metres
    (already unwrapped from get_elevation's (value, quality, source) tuple).
    """
    try:
        center = center_elev if center_elev is not None else get_elevation(lat, lon)[0]
        north = get_elevation(lat + 0.001, lon)[0]
        east = get_elevation(lat, lon + 0.001)[0]
        # 0.001 degree latitude/longitude is roughly 111 meters near Panabo.
        rise = max(abs(north - center), abs(east - center))
        return round((rise / 111.0) * 100.0, 2)
    except Exception:
        return 0.0


def assess_infrastructure_suitability(elevation_m, slope_pct, ndvi, rainfall_mm):
    """Flexible preliminary infrastructure suitability assessment.

    Older logic returned fixed 65 for most vegetated places. This version
    calculates a score using softer penalties so different parcels produce
    different values while still keeping water/flood/steep-slope safeguards.
    """
    score = 92.0
    reasons = []

    if ndvi <= 0.08:
        score -= 55
        reasons.append('water or flooded area detected')
    elif ndvi >= 0.65:
        score -= 14
        reasons.append('dense vegetation / possible agricultural value')
    elif ndvi >= 0.45:
        score -= 8
        reasons.append('vegetated land')
    elif ndvi < 0.25:
        score += 4
        reasons.append('open or low vegetation area')

    if elevation_m < 3:
        score -= 28
        reasons.append('very low elevation')
    elif elevation_m < 8:
        score -= 12
        reasons.append('low elevation')
    elif elevation_m > 120:
        score -= 8
        reasons.append('upland terrain')

    if slope_pct > 18:
        score -= 35
        reasons.append('very steep slope')
    elif slope_pct > 12:
        score -= 22
        reasons.append('steep slope')
    elif slope_pct > 7:
        score -= 10
        reasons.append('moderate slope')
    elif slope_pct <= 3:
        score += 3
        reasons.append('stable/flat terrain')

    if rainfall_mm > 350:
        score -= 18
        reasons.append('very high 30-day rainfall')
    elif rainfall_mm > 250:
        score -= 10
        reasons.append('high 30-day rainfall')
    elif rainfall_mm < 40:
        score -= 3
        reasons.append('low recent rainfall')

    score = int(max(15, min(95, round(score))))

    if score >= 78:
        suitability = 'HIGHLY SUITABLE'
        risk = 'Low terrain constraint'
        recommendation = 'Suitable for preliminary infrastructure planning, subject to zoning, drainage, and site validation.'
    elif score >= 50:
        suitability = 'MODERATELY SUITABLE'
        risk = 'Some site preparation or review required'
        recommendation = 'Possible infrastructure site, but drainage, land conversion, and environmental impact should be reviewed first.'
    elif score >= 35:
        suitability = 'CONDITIONALLY SUITABLE'
        risk = 'Flooding, slope, or land conversion risk'
        recommendation = 'Proceed only with drainage planning, engineering review, and local validation.'
    else:
        suitability = 'NOT SUITABLE'
        risk = 'High terrain or water exposure risk'
        recommendation = 'Avoid permanent infrastructure unless a detailed engineering and environmental assessment supports it.'

    if not reasons:
        reasons = ['stable terrain']
    status = ', '.join(reasons[:2]).capitalize()

    return {
        'infrastructure_suitability': suitability,
        'infrastructure_status': status,
        'infrastructure_risk': risk,
        'infrastructure_recommendation': recommendation,
        'infrastructure_score': score,
    }


# ---------------------------------------------------------------------------
# MAIN ANALYSIS
# ---------------------------------------------------------------------------
def analyze_location(lat, lon, active_crops=None):
    # active_crops must be hashed as part of the cache key too — otherwise a
    # result computed under one Super-Administrator crop configuration could
    # be incorrectly served after that configuration changes.
    active_crops_key = tuple(sorted(active_crops)) if active_crops is not None else None
    cache_key = (round(lat, 4), round(lon, 4), active_crops_key)
    now_ts    = time.time()
    cached    = ANALYSIS_CACHE.get(cache_key)
    if cached and now_ts - cached['ts'] < CACHE_TTL_SECONDS:
        return cached['data']

    with ThreadPoolExecutor(max_workers=7) as ex:
        weather_f  = ex.submit(get_live_weather,  lat, lon)
        rain_f     = ex.submit(get_rainfall,       lat, lon)
        temp_f     = ex.submit(get_temperature,    lat, lon)
        elev_f     = ex.submit(get_elevation,      lat, lon)
        ndvi_f     = ex.submit(get_ndvi,           lat, lon)
        ph_f       = ex.submit(get_soil_ph,        lat, lon)
        nutrient_f = ex.submit(get_soil_nutrients, lat, lon)

        live_hum, weather_desc, wind_speed, cloud_cover, hum_quality = weather_f.result()
        rain_val, rain_quality, rain_source = rain_f.result()
        temp_val, temp_quality, temp_source = temp_f.result()
        elev_val, elev_quality, elev_source = elev_f.result()
        ndvi_val, ndvi_quality, ndvi_source = ndvi_f.result()
        ph_val, ph_quality, ph_source = ph_f.result()
        n_val, p_val, k_val, npk_quality = nutrient_f.result()

    # Per-variable data quality/provenance. Every value that could not be
    # retrieved from a real source is explicitly flagged 'fallback_default'
    # here rather than being silently indistinguishable from a genuine
    # measurement — this is threaded all the way into the result below so
    # the Farmer-facing analysis and the Analyst's review both see it.
    data_quality = {
        'rainfall':    {'quality': rain_quality, 'source': rain_source},
        'temperature': {'quality': temp_quality, 'source': temp_source},
        'elevation':   {'quality': elev_quality, 'source': elev_source},
        'ndvi':        {'quality': ndvi_quality, 'source': ndvi_source},
        'soil_ph':     {'quality': ph_quality, 'source': ph_source},
        'humidity':    {'quality': hum_quality, 'source': 'OpenWeatherMap current conditions' if hum_quality == 'measured' else 'Regional typical value — live weather source unavailable'},
        'nitrogen':    {'quality': npk_quality['nitrogen'], 'source': npk_quality['nitrogen_source']},
        'phosphorus':  {'quality': npk_quality['phosphorus'], 'source': 'Estimated from NDVI/pH/elevation proxies — no direct soil test'},
        'potassium':   {'quality': npk_quality['potassium'], 'source': 'Estimated from NDVI/pH/elevation proxies — no direct soil test'},
    }
    _quality_labels = {
        'rainfall': 'Rainfall', 'temperature': 'Temperature', 'elevation': 'Elevation',
        'ndvi': 'NDVI (vegetation index)', 'soil_ph': 'Soil pH', 'humidity': 'Humidity',
        'nitrogen': 'Soil nitrogen',
    }
    data_quality_warnings = [
        f"{_quality_labels.get(name, name)} could not be retrieved from a live source — a regional typical value was used instead."
        for name, info in data_quality.items() if info['quality'] == 'fallback_default'
    ]

    slope_pct = estimate_slope_percent(lat, lon, elev_val)
    infrastructure_profile = assess_infrastructure_suitability(elev_val, slope_pct, ndvi_val, rain_val)

    land_profile     = classify_land(ndvi_val, elev_val)
    is_crop_possible = land_profile['is_crop_recommended']

    raw_crop = None
    top3_crops = []
    primary_crop = primary_compat = suitability_lvl = None

    if is_crop_possible:
        raw_crop, top3_crops = get_ai_prediction(
            n_val, p_val, k_val, temp_val, live_hum, ph_val, rain_val,
            ndvi_val, elev_val, slope_pct, active_crops=active_crops)
        if top3_crops:
            primary_crop    = top3_crops[0]['crop']
            primary_compat  = top3_crops[0]['compatibility_pct']
            suitability_lvl = _suitability_label(primary_compat)
        else:
            is_crop_possible = False
            land_profile = {
                'land_type': 'low-confidence',
                'recommendation_title': 'CROP ADVISORY (LOW CONFIDENCE)',
                'land_status': 'VEGETATED BUT LOW CROP MATCH',
                'recommendation': 'NO HIGH-CONFIDENCE CROP MATCH',
                'land_use_recommendations': [
                    'Run soil verification sampling before deployment',
                    'Improve soil fertility then re-analyze this parcel',
                    'Trial mixed short-cycle crops on a small block first',
                ],
            }

    season_name, season_advice = get_panabo_season()
    display_crop   = primary_crop if is_crop_possible else land_profile['land_status']
    recommendation = primary_crop.upper() if is_crop_possible else land_profile['recommendation']
    crop_key       = (primary_crop or '').lower()
    crop_meta      = CROP_DETAILS.get(crop_key, {
        'label': 'Localized crop recommendation',
        'growth_cycle': '--', 'est_yield': '--', 'suitability_note': '',
    })

    alternative_crops = top3_crops[1:] if is_crop_possible and len(top3_crops) > 1 else []
    ml_model_top_crop = (
        get_panabo_recommendation(str(raw_crop)) if raw_crop is not None else None
    )
    xai_explanation = (
        build_xai_explanation(primary_crop, primary_compat, top3_crops, temp_val, live_hum,
                              ph_val, rain_val, ndvi_val, elev_val, slope_pct)
        if is_crop_possible and primary_crop and primary_compat is not None
        else build_land_assessment_explanation(
            land_profile, ndvi_val, elev_val, slope_pct, rain_val, infrastructure_profile
        )
    )

    result = {
        'lat': lat, 'lon': lon,
        'live_humidity': live_hum, 'weather_description': weather_desc,
        'rainfall_mm': rain_val, 'rainfall_monthly_mm': rain_val, 'monthly_rainfall_mm': rain_val, 'rainfall_30d_mm': rain_val, 'rainfall_source': rain_source, 'temperature_c': temp_val, 'surface_temp_c': temp_val,
        'elevation_m': elev_val, 'slope_pct': slope_pct, 'wind_speed_ms': wind_speed, 'cloud_cover_pct': cloud_cover,
        'ndvi': ndvi_val, 'biomass': max(0.0, ndvi_val * 1.2),
        'soil_ph': ph_val, 'nitrogen': n_val, 'phosphorus': p_val, 'potassium': k_val,
        'nitrogen_index_pct': max(0.0, min(100.0, (n_val / 140) * 100)),
        'data_quality': data_quality,
        'data_quality_warnings': data_quality_warnings,
        'season_name': season_name, 'season_advice': season_advice,
        'land_type': land_profile['land_type'],
        'land_status': land_profile['land_status'],
        'recommendation_title': land_profile['recommendation_title'],
        'land_use_recommendations': land_profile.get('land_use_recommendations', []),
        **infrastructure_profile,
        'raw_predicted_crop': raw_crop,
        'is_crop_recommended': is_crop_possible,
        'predicted_crop': display_crop, 'recommendation': recommendation,
        'crop_compatibility_pct': primary_compat, 'suitability_level': suitability_lvl,
        'crop_label':            crop_meta['label']            if is_crop_possible else '',
        'crop_growth_cycle':     crop_meta['growth_cycle']     if is_crop_possible else '',
        'crop_est_yield':        crop_meta['est_yield']        if is_crop_possible else '',
        'crop_suitability_note': crop_meta['suitability_note'] if is_crop_possible else '',
        'best_crop': {'crop': primary_crop, 'compatibility_pct': primary_compat} if is_crop_possible else None,
        'top_crop_recommendations': top3_crops,
        'alternative_crops': alternative_crops,
        'recommendation_scoring': (
            '50% trained crop model (N, P, K, weather, NDVI, elevation, slope) + '
            '50% field environment fit from satellite and live weather'
        ),
        'ml_model_top_crop': ml_model_top_crop,
        'xai_explanation': xai_explanation,
    }
    ANALYSIS_CACHE[cache_key] = {'ts': now_ts, 'data': result}
    return result


def print_analysis_report(result):
    print('\n' + '='*55)
    print('        GEOSUSTAIN: PANABO CITY AI ANALYSIS        ')
    print('='*55)
    print(f"LAND   : {result['land_status']} (NDVI: {result['ndvi']:.4f})")
    print(f"CROP   : {result['recommendation']}")
    if result['is_crop_recommended']:
        print(f"FIT    : {result['suitability_level']} ({result['crop_compatibility_pct']}%)")
        for alt in result['top_crop_recommendations'][1:]:
            print(f"  also: {alt['crop']} ({alt['compatibility_pct']}%)")
    print(f"RAIN   : {result['rainfall_mm']:.1f} mm/mo  TEMP: {result['temperature_c']:.1f}C  ELEV: {result['elevation_m']:.0f}m")
    print(f"SOIL   : N={result['nitrogen']} P={result['phosphorus']} K={result['potassium']} pH={result['soil_ph']:.1f}")
    print('='*55+'\n')


if __name__ == '__main__':
    result = analyze_location(7.2915, 125.6255)
    print_analysis_report(result)
