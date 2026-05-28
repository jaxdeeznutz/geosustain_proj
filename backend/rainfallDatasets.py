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

# ---------------------------------------------------------------------------
# INITIALIZATION
# ---------------------------------------------------------------------------
# Render/production uses GEE_SERVICE_ACCOUNT_JSON + GEE_PROJECT_ID.
# Local development can still use your local Earth Engine credentials.
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


initialize_earth_engine()

MODEL              = joblib.load(_asset_path('crop_model.pkl'))
ANALYSIS_CACHE     = {}
CACHE_TTL_SECONDS  = 300
CROP_COMPAT_MIN    = 70.0

# ---------------------------------------------------------------------------
# PANABO CITY CONFIG  — single place for all fallback values
# ---------------------------------------------------------------------------
LAST_RAINFALL_SOURCE = 'Unknown'

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
    'mango':       'Mango',
    'coffee':      'Cacao',
    'mungbean':    'Mung Bean',
    'pigeonpeas':  'Mung Bean',
    'mothbeans':   'Legumes',
    'blackgram':   'Legumes',
    'lentil':      'Legumes',
    'chickpea':    'Legumes',
    'kidneybeans': 'Legumes',
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
    'mango': {
        'label': 'Mango (Carabao / Katchamita)',
        'growth_cycle': '3-5 Years (first harvest)',
        'est_yield': '10-20 Tons / Ha',
        'suitability_note': 'Suited for well-drained upland areas of Panabo.',
    },
    'abaca': {
        'label': 'Abaca (Fiber Crop)',
        'growth_cycle': '18-24 Months',
        'est_yield': '1.2 Tons / Ha',
        'suitability_note': 'Davao Region is the top abaca producer in the Philippines.',
    },
    'mung bean': {
        'label': 'Mung Bean (Short-cycle Legume)',
        'growth_cycle': '2-3 Months',
        'est_yield': '0.9 Tons / Ha',
        'suitability_note': 'Ideal rotation crop to restore nitrogen in depleted soil.',
    },
    'legumes': {
        'label': 'Legume Blend (Nitrogen-fixing)',
        'growth_cycle': '3-4 Months',
        'est_yield': '1.1 Tons / Ha',
        'suitability_note': 'Improves soil fertility; recommended before planting banana.',
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
    'eggplant': {
        'label': 'Eggplant / Talong',
        'growth_cycle': '3-4 Months',
        'est_yield': '12-20 Tons / Ha',
        'suitability_note': 'Vegetable crop for warm lowland areas with moderate rainfall and drainage.',
    },
    'tomato': {
        'label': 'Tomato',
        'growth_cycle': '3-4 Months',
        'est_yield': '15-25 Tons / Ha',
        'suitability_note': 'Best for well-drained plots with moderate humidity and balanced soil pH.',
    },
    'okra': {
        'label': 'Okra',
        'growth_cycle': '2-3 Months',
        'est_yield': '8-12 Tons / Ha',
        'suitability_note': 'Heat-tolerant vegetable suited for diversified farm plots.',
    },
    'peanut': {
        'label': 'Peanut',
        'growth_cycle': '3-4 Months',
        'est_yield': '1.5-2.5 Tons / Ha',
        'suitability_note': 'Good rotation crop for drier, well-drained soils.',
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
    url = (f'https://api.openweathermap.org/data/2.5/weather'
           f'?lat={lat}&lon={lon}&appid={OPENWEATHER_KEY}&units=metric')
    try:
        resp = requests.get(url, timeout=6).json()
        return (resp['main']['humidity'],
                resp['weather'][0]['description'],
                resp.get('wind', {}).get('speed', 0.0),
                resp.get('clouds', {}).get('all', 0))
    except Exception:
        return 80, 'Condition unavailable', 0.0, 0


# ---------------------------------------------------------------------------
# GEE ACQUISITION
# ---------------------------------------------------------------------------
def _open_meteo_recent_monthly_rainfall(lat, lon):
    """Use Open-Meteo recent daily precipitation as a Render-safe rainfall backup.

    This does not need an API key and works even when Google Earth Engine/CHIRPS
    is unavailable on Render. It first tries the forecast endpoint with
    past_days, then the archive endpoint.
    """
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
    """
    global LAST_RAINFALL_SOURCE
    start = (datetime.utcnow() - timedelta(days=30)).strftime('%Y-%m-%d')
    end = datetime.utcnow().strftime('%Y-%m-%d')

    # 1) Primary: CHIRPS 30-day precipitation sum from Earth Engine
    try:
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
                LAST_RAINFALL_SOURCE = 'CHIRPS DAILY 30-day rainfall via Google Earth Engine'
                return total
    except Exception as exc:
        print(f'CHIRPS rainfall failed: {exc}')

    # 2) Backup: Open-Meteo archive/reanalysis
    open_meteo_rain = _open_meteo_recent_monthly_rainfall(lat, lon)
    if open_meteo_rain is not None and open_meteo_rain >= 0:
        LAST_RAINFALL_SOURCE = 'Open-Meteo Archive 30-day rainfall backup'
        return open_meteo_rain

    # 3) Last resort fallback
    LAST_RAINFALL_SOURCE = 'Panabo fallback rainfall; live source unavailable'
    return PANABO_CONFIG['rainfall_monthly_mm']


def get_temperature(lat, lon):
    start, end = _date_window(12)
    try:
        point  = ee.Geometry.Point([lon, lat])
        kelvin = (ee.ImageCollection('ECMWF/ERA5_LAND/DAILY_AGGR')
                    .filterBounds(point).filterDate(start, end)
                    .mean().sample(point, 30).first().get('temperature_2m'))
        val = ee.Number(kelvin).subtract(273.15).getInfo()
        return float(val) if val else PANABO_CONFIG['temperature_c']
    except Exception:
        return PANABO_CONFIG['temperature_c']


def get_elevation(lat, lon):
    try:
        point = ee.Geometry.Point([lon, lat])
        val   = (ee.Image('USGS/SRTMGL1_003')
                   .sample(point, 30).first().get('elevation').getInfo())
        return float(val) if val else PANABO_CONFIG['elevation_m']
    except Exception:
        return PANABO_CONFIG['elevation_m']


def get_ndvi(lat, lon):
    """Rolling 18-month window, most recent low-cloud Sentinel-2."""
    start, end = _date_window(18)
    try:
        s2    = ee.ImageCollection('COPERNICUS/S2_SR_HARMONIZED')
        point = ee.Geometry.Point([lon, lat])
        image = (s2.filterBounds(point).filterDate(start, end)
                   .filter(ee.Filter.lt('CLOUDY_PIXEL_PERCENTAGE', 20))
                   .sort('system:time_start', False).first())
        if image is None:
            return 0.45
        val = (image.normalizedDifference(['B8', 'B4'])
                    .rename('NDVI').sample(point, 10).first().get('NDVI').getInfo())
        return float(val) if val else 0.45
    except Exception:
        return 0.45


def get_soil_ph(lat, lon):
    try:
        point  = ee.Geometry.Point([lon, lat])
        sample = (ee.Image('OpenLandMap/SOL/SOL_PH-H2O_USDA-4C1A2A_M/v02')
                    .sample(point, 250).first())
        ph_band = sample.get('b0') if sample else None
        val     = ee.Number(ph_band).divide(10).getInfo() if ph_band else None
        return float(val) if val else PANABO_CONFIG['soil_ph']
    except Exception:
        return PANABO_CONFIG['soil_ph']


def get_soil_nitrogen(lat, lon):
    """
    N from SoilGrids 250m v2.0 (ISRIC, Poggio et al. 2021) — primary source.
    Fallback: OpenLandMap SOL_STN.
    Unit conversion: SoilGrids cg/kg -> g/kg -> scaled to dataset range 0-140.
    """
    point = ee.Geometry.Point([lon, lat])

    # Primary: SoilGrids 2.0
    try:
        n_raw = (ee.Image('projects/soilgrids-isric/nitrogen_mean')
                   .select('nitrogen_0-5cm_mean')
                   .sample(point, 250).first().get('nitrogen_0-5cm_mean'))
        val = ee.Number(n_raw).getInfo() if n_raw else None
        if val is not None:
            n_gkg    = float(val) / 100.0            # cg/kg -> g/kg
            # Calibrated conversion to the 0-140 training scale.
            # The older multiplier often saturated Panabo samples at 140,
            # which made the classifier over-favor one crop.
            nitrogen = max(20, min(120, round(n_gkg * 6)))
            return nitrogen
    except Exception:
        pass

    # Fallback: OpenLandMap
    try:
        n_raw = (ee.Image('OpenLandMap/SOL/SOL_STN_USDA-4C1A2A_M/v02')
                   .sample(point, 250).first().get('b0'))
        val = float(ee.Number(n_raw).getInfo()) if n_raw else None
        if val is not None:
            return max(20, min(120, round(float(val) * 0.7)))
    except Exception:
        pass

    return PANABO_CONFIG['nitrogen']


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
    """
    Return (N, P, K) in units matching training dataset.
    N: GEE SoilGrids 2.0 (ISRIC). P/K: estimated from NDVI+pH+elevation.
    """
    nitrogen = get_soil_nitrogen(lat, lon)

    # Fetch observable proxies for P/K estimation
    try:
        ndvi_pk = get_ndvi(lat, lon)
    except Exception:
        ndvi_pk = 0.45
    try:
        ph_pk = get_soil_ph(lat, lon)
    except Exception:
        ph_pk = PANABO_CONFIG['soil_ph']
    try:
        elev_pk = get_elevation(lat, lon)
    except Exception:
        elev_pk = PANABO_CONFIG['elevation_m']

    phosphorus, potassium = estimate_phosphorus_potassium(ndvi_pk, ph_pk, elev_pk)
    return nitrogen, phosphorus, potassium


# ---------------------------------------------------------------------------
# AI PREDICTION
# ---------------------------------------------------------------------------
def get_panabo_recommendation(raw_prediction):
    return PANABO_CROP_MAP.get(raw_prediction.lower().strip())


def _suitability_label(pct):
    # Calibrated suitability scale used by the mobile UI/report.
    # 85-100 = highly suitable, 70-84 = suitable, 50-69 = moderate, below 50 = low.
    if pct >= 85:  return 'HIGHLY SUITABLE'
    if pct >= 70:  return 'SUITABLE'
    if pct >= 50:  return 'MODERATELY SUITABLE'
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
    'mung bean': {
        'temp': (25, 35, 20, 39), 'humidity': (45, 80, 30, 94), 'ph': (6.0, 7.5, 5.2, 8.2),
        'rain': (35, 110, 5, 200), 'ndvi': (0.22, 0.62, 0.10, 0.82), 'elevation': (0, 300, 0, 650), 'slope': (0, 10, 0, 22),
    },
    'legumes': {
        'temp': (24, 34, 19, 39), 'humidity': (45, 82, 30, 96), 'ph': (5.8, 7.5, 5.0, 8.3),
        'rain': (35, 130, 5, 220), 'ndvi': (0.22, 0.65, 0.10, 0.85), 'elevation': (0, 320, 0, 700), 'slope': (0, 12, 0, 24),
    },
    'cassava': {
        'temp': (24, 34, 19, 39), 'humidity': (50, 85, 30, 98), 'ph': (5.0, 7.2, 4.3, 8.2),
        'rain': (45, 170, 10, 300), 'ndvi': (0.25, 0.72, 0.10, 0.9), 'elevation': (0, 350, 0, 800), 'slope': (0, 14, 0, 28),
    },
    'sweet potato': {
        'temp': (22, 32, 18, 38), 'humidity': (50, 85, 30, 98), 'ph': (5.5, 6.8, 4.8, 7.8),
        'rain': (45, 150, 10, 260), 'ndvi': (0.25, 0.70, 0.10, 0.88), 'elevation': (0, 350, 0, 750), 'slope': (0, 12, 0, 26),
    },
    'eggplant': {
        'temp': (23, 32, 18, 37), 'humidity': (55, 85, 35, 98), 'ph': (5.5, 7.0, 4.8, 7.8),
        'rain': (45, 160, 15, 260), 'ndvi': (0.28, 0.72, 0.12, 0.88), 'elevation': (0, 250, 0, 550), 'slope': (0, 10, 0, 22),
    },
    'tomato': {
        'temp': (21, 30, 17, 35), 'humidity': (50, 82, 30, 95), 'ph': (5.8, 7.2, 5.0, 8.0),
        'rain': (35, 130, 8, 230), 'ndvi': (0.25, 0.68, 0.10, 0.84), 'elevation': (0, 280, 0, 650), 'slope': (0, 10, 0, 22),
    },
    'okra': {
        'temp': (24, 35, 20, 39), 'humidity': (50, 85, 30, 98), 'ph': (6.0, 7.5, 5.0, 8.2),
        'rain': (35, 150, 8, 260), 'ndvi': (0.25, 0.70, 0.10, 0.86), 'elevation': (0, 300, 0, 700), 'slope': (0, 12, 0, 24),
    },
    'peanut': {
        'temp': (24, 33, 19, 38), 'humidity': (45, 78, 28, 92), 'ph': (5.8, 7.2, 5.0, 8.0),
        'rain': (30, 115, 5, 210), 'ndvi': (0.20, 0.62, 0.08, 0.80), 'elevation': (0, 320, 0, 700), 'slope': (0, 10, 0, 22),
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
    """Small agronomic adjustments so one crop does not dominate every nearby parcel.

    Live weather is useful context, but crop recommendation should be based on
    field suitability. These rules reduce over-favoring short-cycle dry crops
    like watermelon when the area is humid/vegetated, and allow wetland/fruit/
    upland crops to win when their field signals fit better.
    """
    crop = str(crop_name).lower()
    adj = 0.0

    if ndvi >= 0.62:
        if 'watermelon' in crop:
            adj -= 15.0
        elif any(x in crop for x in ['banana', 'cacao', 'coconut']):
            adj += 5.0
        elif crop == 'rice':
            adj += 3.0

    if humidity >= 85:
        if 'watermelon' in crop:
            adj -= 10.0
        elif any(x in crop for x in ['banana', 'rice', 'cacao', 'coconut']):
            adj += 4.0

    if rain > 130:
        if 'watermelon' in crop:
            adj -= 12.0
        elif any(x in crop for x in ['rice', 'banana', 'cacao', 'coconut']):
            adj += 5.0
    elif rain < 60:
        if crop == 'rice':
            adj -= 8.0
        elif 'banana' in crop:
            adj -= 5.0
        elif any(x in crop for x in ['watermelon', 'mung bean', 'legumes']):
            adj += 3.0

    if slope > 7:
        if crop == 'rice':
            adj -= 8.0
        elif 'watermelon' in crop:
            adj -= 4.0
        elif any(x in crop for x in ['cassava', 'corn', 'cacao']):
            adj += 3.0

    if ph < 5.8:
        if 'watermelon' in crop:
            adj -= 8.0
        elif any(x in crop for x in ['cassava', 'coconut']):
            adj += 3.0

    return adj


def get_ai_prediction(n, p, k, temp, humidity, ph, rain, ndvi, elevation, slope):
    # Keep the ML model as a candidate source, but do not let today's/this month's
    # weather pattern make one crop win everywhere. Crop recommendation now blends:
    # 1) model confidence, 2) local field fit, and 3) crop-specific agronomic rules.
    input_df = pd.DataFrame([{
        'N': n, 'P': p, 'K': k,
        'temperature': temp, 'humidity': humidity, 'ph': ph, 'rainfall': rain,
        'ndvi': ndvi, 'elevation': elevation, 'slope': slope,
    }])
    raw_prediction = MODEL.predict(input_df)[0]

    # Use a conservative agro-climate rainfall for crop scoring. The live/30-day
    # rainfall is still displayed to users and used for alerts, but crop choice
    # should not swing too much just because today's weather is dry or rainy.
    baseline_rain = float(PANABO_CONFIG.get('rainfall_monthly_mm', 105.0))
    crop_rain = (0.65 * baseline_rain) + (0.35 * float(rain or baseline_rain))

    ml_relative_by_crop = {}
    if hasattr(MODEL, 'predict_proba'):
        probs = MODEL.predict_proba(input_df)[0]
        ranked = sorted(zip(MODEL.classes_, probs), key=lambda x: -x[1])
        top_prob = max(float(ranked[0][1]), 0.0001) if ranked else 0.0001
        for crop_label, prob in ranked:
            panabo_crop = get_panabo_recommendation(crop_label) or str(crop_label).title()
            key = str(panabo_crop).lower()
            ml_relative_by_crop[key] = max(ml_relative_by_crop.get(key, 0.0), max(0.0, min(1.0, float(prob) / top_prob)))

    candidates = {}
    # Score every local supported crop, not only the ML top candidates. This makes
    # alternatives like rice, banana, corn, coconut, cassava, and cacao able to win
    # when their field conditions fit better.
    for key, profile in CROP_ENV_PROFILES.items():
        crop_name = key.title()
        # Preserve nicer capitalization for banana variants.
        for pretty in CROP_DETAILS.keys():
            if pretty == key:
                crop_name = CROP_DETAILS[pretty].get('display_name', pretty.title())
        if key in CROP_DETAILS:
            crop_name = key.title()

        env_score = _environment_score(key, temp, humidity, ph, crop_rain, ndvi, elevation, slope)
        rel = ml_relative_by_crop.get(key, 0.10)
        ml_score = 42.0 + (38.0 * (rel ** 0.75))
        # Field fit is now dominant. The ML model can suggest candidates, but it
        # cannot force the same crop to win on every nearby parcel.
        final_score = (0.10 * ml_score) + (0.90 * env_score)
        final_score += _crop_adjustment(key, crop_rain, humidity, ndvi, slope, ph)

        # Extra local-fit boosts so humid/vegetated Panabo parcels can choose
        # banana/rice/cacao/coconut when they are agronomically better than
        # watermelon. Alternatives remain fully dynamic because all crops are
        # scored and sorted below.
        if ndvi >= 0.50 and humidity >= 72:
            if any(x in key for x in ['banana', 'cacao', 'coconut']):
                final_score += 5.0
            if key == 'rice' and slope <= 4.5:
                final_score += 4.0
        if elevation <= 80 and slope <= 3.5 and crop_rain >= 95 and key == 'rice':
            final_score += 6.0
        if 40 <= crop_rain <= 150 and slope <= 9 and any(x in key for x in ['corn', 'cassava', 'papaya']):
            final_score += 2.5

        # Watermelon is still possible, but it should not score high unless
        # the field is clearly a dry, well-drained, moderate-vegetation site.
        watermelon_perfect = (
            key == 'watermelon' and
            35 <= crop_rain <= 105 and
            humidity <= 82 and
            0.28 <= ndvi <= 0.58 and
            6.0 <= ph <= 7.5 and
            slope <= 6
        )
        if key == 'watermelon' and not watermelon_perfect:
            final_score -= 12.0

        # Keep the raw score for ranking, but do not display everything as 90%.
        # The previous version capped many crops at 90, so the top 5 looked tied
        # even when the ranking was different. We calibrate display scores after
        # sorting so users see clear, fair differences.
        raw_score = round(max(15.0, min(100.0, final_score)), 2)
        candidates[key] = {
            'crop': crop_name,
            'compatibility_pct': raw_score,
            'raw_score': raw_score,
            'model_probability_pct': round(rel * 100, 2),
            'environment_fit_pct': env_score,
        }

    ranked_crops = sorted(candidates.values(), key=lambda x: -x['raw_score'])
    top_crops = ranked_crops[:5]

    # Convert raw suitability into presentation scores with realistic separation.
    # Ranking stays data-driven; only the displayed percentages are calibrated.
    # This prevents the top five from all appearing as 90% while preserving the
    # best crop order chosen from rainfall, NDVI, elevation, slope, pH, nutrients,
    # temperature, humidity, and the ML model signal.
    if top_crops:
        top_raw = float(top_crops[0]['raw_score'])
        floor_raw = float(top_crops[-1]['raw_score'])
        spread = max(1.0, top_raw - floor_raw)
        calibrated = []
        # Larger spacing keeps rankings believable and avoids every crop
        # looking equally strong.
        rank_steps = [0.0, 12.0, 20.0, 28.0, 36.0]

        # Restore more realistic suitability ranges similar to the earlier build.
        # Most good agricultural parcels should land around 50-72 instead of 90.
        top_display = 52.0 + min(18.0, max(0.0, (top_raw - 42.0) * 0.28))
        top_display = max(50.0, min(74.0, top_display))
        for idx, crop in enumerate(top_crops):
            raw = float(crop['raw_score'])
            normalized = (raw - floor_raw) / spread
            separation = rank_steps[min(idx, len(rank_steps) - 1)]
            # Small raw bonus keeps real data differences visible inside each rank.
            display = top_display - separation + (normalized * 1.8)
            if idx == 0:
                display = top_display
            # No alternative should tie the best crop visually.
            if idx > 0:
                display = min(display, top_display - (9.0 + (idx * 2.0)))
            crop = dict(crop)
            crop['compatibility_pct'] = round(max(28.0, min(78.0, display)), 1)
            calibrated.append(crop)
        top_crops = sorted(calibrated, key=lambda x: -x['compatibility_pct'])
    if not top_crops:
        mapped = get_panabo_recommendation(raw_prediction) or str(raw_prediction).title()
        top_crops.append({'crop': mapped, 'compatibility_pct': 50.0, 'model_probability_pct': None})
    return raw_prediction, top_crops

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
    """
    try:
        center = center_elev if center_elev is not None else get_elevation(lat, lon)
        north = get_elevation(lat + 0.001, lon)
        east = get_elevation(lat, lon + 0.001)
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
def analyze_location(lat, lon):
    cache_key = (round(lat, 4), round(lon, 4))
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

        live_hum, weather_desc, wind_speed, cloud_cover = weather_f.result()
        rain_val = rain_f.result()
        temp_val = temp_f.result()
        elev_val = elev_f.result()
        ndvi_val = ndvi_f.result()
        ph_val   = ph_f.result()
        n_val, p_val, k_val = nutrient_f.result()

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
            ndvi_val, elev_val, slope_pct)
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
    display_crop   = primary_crop if is_crop_possible else land_profile['recommendation_title']
    recommendation = primary_crop.upper() if is_crop_possible else land_profile['recommendation']
    crop_key       = (primary_crop or '').lower()
    crop_meta      = CROP_DETAILS.get(crop_key, {
        'label': 'Localized crop recommendation',
        'growth_cycle': '--', 'est_yield': '--', 'suitability_note': '',
    })

    alternative_crops = top3_crops[1:] if is_crop_possible and len(top3_crops) > 1 else []

    result = {
        'lat': lat, 'lon': lon,
        'live_humidity': live_hum, 'weather_description': weather_desc,
        'rainfall_mm': rain_val, 'rainfall_monthly_mm': rain_val, 'monthly_rainfall_mm': rain_val, 'rainfall_30d_mm': rain_val, 'rainfall_source': LAST_RAINFALL_SOURCE, 'temperature_c': temp_val, 'surface_temp_c': temp_val,
        'elevation_m': elev_val, 'slope_pct': slope_pct, 'wind_speed_ms': wind_speed, 'cloud_cover_pct': cloud_cover,
        'ndvi': ndvi_val, 'biomass': max(0.0, ndvi_val * 1.2),
        'soil_ph': ph_val, 'nitrogen': n_val, 'phosphorus': p_val, 'potassium': k_val,
        'nitrogen_index_pct': max(0.0, min(100.0, (n_val / 140) * 100)),
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
