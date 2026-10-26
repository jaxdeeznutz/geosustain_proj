import os
import json
import hashlib
import secrets
import database as defense_db
import qa_closure
import email_verification
from defense_security import validate_profile_photo
import logging
import time
import urllib.parse
import urllib.request
from datetime import datetime, timedelta
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Any, Dict, List, Optional, Tuple

import bcrypt
from password_auth import verify_password, validate_new_password
from auth_security import AuthSecurityMiddleware, signing_key, production_mode
import requests
from fastapi import Request, Depends, HTTPException, status, Header, Query
from http_config import CorsFastAPI
from json_safe import json_safe
from model_ranking import ModelRankingUnavailable
from land_cover import screen_land_cover, advisory_result
from cagro_soil import nutrient_layers
from analysis_coverage import (require_analysis_coverage, require_point_coverage, coverage_catalog,
                               farm_coverage, CoverageUnavailable, VERSION as COVERAGE_VERSION,
                               HISTORICAL_NOTE)
from fastapi.exceptions import RequestValidationError
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from itsdangerous import BadSignature, SignatureExpired, URLSafeTimedSerializer
from pydantic import BaseModel, Field, field_validator
from email_validator import validate_email, EmailNotValidError
from geometry import normalize_polygon, polygon_area_m2, in_study_area
from model_explainability import merge_model_snapshots, finalize_explanation
from psycopg2 import Error as DatabaseError
from starlette.middleware.sessions import SessionMiddleware

from database import (
    init_db,
    create_user,
    get_user_by_email,
    get_user_by_id,
    save_analysis_session,
    get_user_history,
    save_analysis_for_user,
    submit_analysis_to_planner,
    create_report_for_user,
    get_saved_analyses,
    get_reports,
    get_user_counts,
    update_user_profile,
    deactivate_user,
    delete_user,
    get_planner_queue,
    get_planner_session_detail,
    verify_analysis_session,
    get_planner_queue_counts,
    admin_dashboard_stats, admin_list_users, admin_update_user, admin_list_analyses,
    create_farm_parcel, list_farm_parcels, get_farm_parcel, update_farm_parcel,
    get_climate_baseline, save_climate_baseline,
    validate_farm_polygon, get_active_crop_keys, list_crop_reference,
    update_crop_reference, get_audit_logs,
    get_user_analysis, find_analysis_request, change_user_password,
    analysis_request_lock, analysis_request_status,
)

try:
    from environmental_pipeline import analyze_location
    ANALYSIS_IMPORT_ERROR = None
except Exception as exc:
    analyze_location = None
    ANALYSIS_IMPORT_ERROR = exc
    print(f'GeoSustain analysis engine failed to load: {exc}')


BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SECRET_KEY = signing_key()
MOBILE_TOKEN_MAX_AGE = 60 * 60 * 24  # 24 hours; password changes revoke existing tokens



# ---------------------------------------------------------------------------
# LOCAL PANABO CROP SEASON CALENDAR
# ---------------------------------------------------------------------------
# This rule-based calendar complements the trained model. It is intentionally
# configurable so the City Agriculture Office can replace the month windows
# with an officially validated local planting calendar later.
CROP_SEASON_CALENDAR = {
    "rice": {"months": [5, 6, 7, 10, 11, 12], "window": "May–July or October–December", "type": "annual"},
    "corn": {"months": [1, 2, 3, 5, 6, 7, 9, 10], "window": "January–March, May–July, or September–October", "type": "annual"},
    "watermelon": {"months": [11, 12, 1, 2, 3], "window": "November–March", "type": "annual"},
    "cassava": {"months": [5, 6, 7, 8, 9, 10, 11], "window": "May–November", "type": "annual"},
    "sweet potato": {"months": [5, 6, 7, 8, 9, 10, 11], "window": "May–November", "type": "annual"},
    "papaya": {"months": list(range(1, 13)), "preferred": [5, 6, 7, 8, 9, 10, 11], "window": "Year-round; establishment preferred May–November", "type": "perennial"},
    "banana": {"months": list(range(1, 13)), "preferred": [5, 6, 7, 8, 9, 10, 11], "window": "Year-round with moisture; establishment preferred May–November", "type": "perennial"},
    "abaca": {"months": list(range(1, 13)), "preferred": [5, 6, 7, 8, 9, 10, 11], "window": "Year-round with moisture; establishment preferred May–November", "type": "perennial"},
    "coconut": {"months": list(range(1, 13)), "preferred": [5, 6, 7, 8, 9, 10, 11], "window": "Year-round; establishment preferred May–November", "type": "perennial"},
    "cacao": {"months": list(range(1, 13)), "preferred": [5, 6, 7, 8, 9, 10, 11], "window": "Year-round with shade and moisture; establishment preferred May–November", "type": "perennial"},
    "durian": {"months": list(range(1, 13)), "preferred": [5, 6, 7, 8, 9, 10, 11], "window": "Year-round with moisture; establishment preferred May–November", "type": "perennial"},
    "rubber": {"months": list(range(1, 13)), "preferred": [5, 6, 7, 8, 9, 10, 11], "window": "Year-round; establishment preferred May–November", "type": "perennial"},
    "pomelo": {"months": list(range(1, 13)), "preferred": [5, 6, 7, 8, 9, 10, 11], "window": "Year-round with irrigation; establishment preferred May–November", "type": "perennial"},
}

MONTH_NAMES = [
    "", "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December"
]

def _crop_season_info(crop_name: str, planting_month: int) -> Dict[str, Any]:
    month = max(1, min(12, int(planting_month)))
    raw_key = str(crop_name or "").strip().lower()
    # Normalize model labels such as "Banana (Cavendish/Lakatan)" and
    # "Corn (White/Yellow)" to the base crop used by the local calendar.
    aliases = {
        "banana (cavendish/lakatan)": "banana",
        "banana (saba)": "banana",
        "corn (white/yellow)": "corn",
        "sweet potato/camote": "sweet potato",
    }
    key = aliases.get(raw_key, raw_key.split("(", 1)[0].strip())
    config = CROP_SEASON_CALENDAR.get(key)
    if not config:
        return {
            "status": "unknown", "label": "Calendar unavailable",
            "multiplier": 0.95, "window": "Local calendar not yet configured",
            "note": f"No local planting calendar is configured for {crop_name}."
        }
    if config.get("type") == "perennial":
        preferred = config.get("preferred", [])
        if month in preferred:
            return {
                "status": "preferred_establishment", "label": "Preferred establishment period",
                "multiplier": 1.00, "window": config["window"],
                "note": f"{MONTH_NAMES[month]} is within the preferred establishment period for {crop_name}."
            }
        return {
            "status": "year_round_with_management", "label": "Year-round with management",
            "multiplier": 0.97, "window": config["window"],
            "note": f"{crop_name} may be established in {MONTH_NAMES[month]}, but reliable irrigation and moisture management are more important outside the wetter months."
        }
    if month in config.get("months", []):
        return {
            "status": "in_season", "label": "In season", "multiplier": 1.00,
            "window": config["window"],
            "note": f"{MONTH_NAMES[month]} is within the configured local planting window for {crop_name}."
        }
    return {
        "status": "out_of_season", "label": "Outside preferred season",
        "multiplier": 0.88, "window": config["window"],
        "note": f"{MONTH_NAMES[month]} is outside the configured local planting window for {crop_name}."
    }

def apply_local_seasonality(result: Dict[str, Any], planting_month: int) -> Dict[str, Any]:
    month = max(1, min(12, int(planting_month)))
    result["intended_planting_month"] = month
    result["intended_planting_month_name"] = MONTH_NAMES[month]
    result["seasonality_method"] = "Soft seasonal adjustment after environmental model ranking; reordering limited to crops within 8 percentage points"

    if result.get("is_crop_recommended") is not True:
        result["season_status"] = "not_applicable"
        result["season_label"] = "Not applicable to land-use advisory"
        result["season_adjusted_score"] = None
        result["recommended_planting_window"] = None
        return result

    raw_rankings = result.get("top_crop_recommendations") or []
    candidates = []
    for item in raw_rankings:
        if not isinstance(item, dict) or not item.get("crop"):
            continue
        crop = str(item["crop"])
        try:
            base = float(item.get("compatibility_pct") or 0)
        except (TypeError, ValueError):
            base = 0.0
        info = _crop_season_info(crop, month)
        adjusted = max(0.0, min(100.0, base * float(info["multiplier"])))
        enriched = dict(item)
        enriched.update({
            "environmental_suitability_pct": round(base, 1),
            "season_adjusted_score": round(adjusted, 1),
            "season_status": info["status"],
            "season_label": info["label"],
            "recommended_planting_window": info["window"],
            "season_note": info["note"],
        })
        enriched["compatibility_pct"] = round(adjusted, 1)
        candidates.append(enriched)

    if not candidates:
        crop = str(result.get("predicted_crop") or result.get("crop") or "")
        base = float(result.get("crop_compatibility_pct") or 0)
        info = _crop_season_info(crop, month)
        candidates = [{
            "crop": crop, "environmental_suitability_pct": round(base, 1),
            "compatibility_pct": round(base * info["multiplier"], 1),
            "season_adjusted_score": round(base * info["multiplier"], 1),
            "season_status": info["status"], "season_label": info["label"],
            "recommended_planting_window": info["window"], "season_note": info["note"],
        }]

    # Keep seasonality as a supporting factor rather than allowing it to
    # overpower the environmental model. A crop may overtake the original
    # environmental leader only when its base score is within 8 percentage
    # points of the best environmental score.
    best_environmental = max(
        (float(item.get("environmental_suitability_pct") or 0) for item in candidates),
        default=0.0,
    )
    close_margin = 8.0
    for item in candidates:
        base_score = float(item.get("environmental_suitability_pct") or 0)
        adjusted_score = float(item.get("season_adjusted_score") or 0)
        is_close_contender = base_score >= (best_environmental - close_margin)
        item["season_reorder_eligible"] = is_close_contender
        # Candidates outside the margin retain their adjusted value for display,
        # but cannot leap ahead of environmentally stronger crops.
        item["_season_rank_score"] = (
            adjusted_score
            if is_close_contender
            else min(adjusted_score, best_environmental - close_margin - 0.01)
        )

    candidates.sort(
        key=lambda item: (
            float(item.get("_season_rank_score") or 0),
            float(item.get("environmental_suitability_pct") or 0),
        ),
        reverse=True,
    )
    winner = candidates[0]
    for item in candidates:
        item.pop("_season_rank_score", None)
    result["top_crop_recommendations"] = candidates
    result["alternative_crops"] = candidates[1:]
    result["predicted_crop"] = winner["crop"]
    result["crop"] = winner["crop"]
    result["best_crop"] = {"crop": winner["crop"], "compatibility_pct": winner["compatibility_pct"]}
    result["environmental_suitability_pct"] = winner["environmental_suitability_pct"]
    result["crop_compatibility_pct"] = winner["compatibility_pct"]
    result["season_adjusted_score"] = winner["season_adjusted_score"]
    result["season_status"] = winner["season_status"]
    result["season_label"] = winner["season_label"]
    result["recommended_planting_window"] = winner["recommended_planting_window"]
    result["season_note"] = winner["season_note"]
    result["season_name"] = f"{winner['season_label']} — {MONTH_NAMES[month]}"
    result["season_advice"] = winner["season_note"]

    # The seasonal winner may differ from the initial model/environment leader.
    # Never carry that earlier crop's reasons over to the new winner.
    comparison = winner.get('condition_comparison') or {}
    if comparison:
        result['xai_explanation'] = {
            'method': 'Configured crop-condition comparisons (not model attribution)',
            'scope': 'crop_conditions', 'crop': winner['crop'],
            'plain_summary': comparison.get('summary'),
            'supporting_factors': [],
            'limiting_factors': [comparison['main_limitation']] if comparison.get('main_limitation') else [],
        }
    elif (result.get('xai_explanation') or {}).get('crop') != winner['crop']:
        result['xai_explanation'] = {'scope': 'crop_conditions', 'crop': winner['crop']}
    xai = result.get("xai_explanation")
    if isinstance(xai, dict):
        xai = dict(xai)
        factors = list(xai.get("supporting_factors") or [])
        limiting = list(xai.get("limiting_factors") or [])
        sentence = winner["season_note"]
        if winner["season_status"] in ("in_season", "preferred_establishment"):
            factors.insert(0, sentence)
        elif winner["season_status"] in ("out_of_season", "year_round_with_management"):
            limiting.insert(0, sentence)
        xai["supporting_factors"] = factors
        xai["limiting_factors"] = limiting
        xai["seasonal_context"] = sentence
        xai["summary"] = (
            f"{winner['crop']} ranked first after combining {winner['environmental_suitability_pct']:.1f}% "
            f"environmental suitability with the {MONTH_NAMES[month]} planting calendar, resulting in "
            f"{winner['season_adjusted_score']:.1f}% final suitability."
        )
        result["xai_explanation"] = xai
    return result


app = CorsFastAPI(title="GeoSustain API", version="2.0.0")


@app.exception_handler(RequestValidationError)
async def invalid_request(request: Request, exc: RequestValidationError):
    # Pydantic's default errors include the raw input (including passwords).
    return JSONResponse({'detail': [
        {'loc': list(e['loc']), 'msg': e['msg'], 'type': e['type']}
        for e in exc.errors()
    ]}, status_code=422)


@app.exception_handler(DatabaseError)
async def database_unavailable(request: Request, exc: DatabaseError):
    # Credentials/DSNs can appear in driver messages; never send those to clients.
    print(f'Database operation failed: {type(exc).__name__}')
    return JSONResponse({'error':'The account/data service is unavailable. Please try again shortly.'}, status_code=503)
app.add_middleware(SessionMiddleware, secret_key=SECRET_KEY, https_only=production_mode(), same_site="lax", max_age=86400)
app.add_middleware(AuthSecurityMiddleware)

@app.exception_handler(Exception)
async def unexpected_failure(request: Request, exc: Exception):
    logging.getLogger('uvicorn.error').exception(
        'Unhandled request failure method=%s path=%s', request.method, request.url.path,
        exc_info=(type(exc), exc, exc.__traceback__),
    )
    return JSONResponse({'detail': 'The service encountered an error. Please try again.'}, status_code=500)

app.mount("/static", StaticFiles(directory=os.path.join(BASE_DIR, "static")), name="static")
templates = Jinja2Templates(directory=os.path.join(BASE_DIR, "templates"))

def _get_flashed_messages(request: Request, with_categories: bool = False):
    messages = request.session.pop("_flash", [])
    if with_categories:
        return messages
    return [message for _, message in messages]

templates.env.globals["get_flashed_messages"] = lambda with_categories=False: []

token_serializer = URLSafeTimedSerializer(SECRET_KEY)

WEATHER_CODE_TEXT = {
    0: "Clear sky", 1: "Mainly clear", 2: "Partly cloudy", 3: "Overcast",
    45: "Fog", 48: "Depositing rime fog", 51: "Light drizzle", 53: "Moderate drizzle",
    55: "Dense drizzle", 61: "Slight rain", 63: "Moderate rain", 65: "Heavy rain",
    71: "Slight snow", 73: "Moderate snow", 75: "Heavy snow", 80: "Slight rain showers",
    81: "Moderate rain showers", 82: "Violent rain showers", 95: "Thunderstorm",
    96: "Thunderstorm with hail", 99: "Thunderstorm with heavy hail",
}


def fetch_open_meteo_weather(lat: float, lon: float) -> Dict[str, Any]:
    """Fetch weather with forecast windows aligned to the provider's local time."""
    params = {
        "latitude": lat,
        "longitude": lon,
        "current": "temperature_2m,relative_humidity_2m,precipitation,rain,weather_code,cloud_cover,wind_speed_10m",
        "hourly": "temperature_2m,precipitation,precipitation_probability,weather_code,wind_speed_10m",
        "daily": "precipitation_sum",
        "past_days": 30,
        "forecast_days": 2,  # Include the next morning when requested late at night.
        "wind_speed_unit": "kmh",
        "timezone": "Asia/Manila",
    }
    response = requests.get(
        "https://api.open-meteo.com/v1/forecast", params=params,
        headers={"User-Agent": "GeoSustainCapstone/1.0"}, timeout=12,
    )
    response.raise_for_status()
    payload = response.json()
    current = payload.get("current") or {}
    hourly = payload.get("hourly") or {}
    daily = payload.get("daily") or {}
    current_time = current.get("time")
    if not current_time or current.get("temperature_2m") is None:
        raise ValueError("Weather provider returned no current conditions.")
    now = datetime.fromisoformat(current_time)
    times = hourly.get("time") or []
    start = next(
        (i for i, value in enumerate(times) if datetime.fromisoformat(value) >= now),
        len(times),
    )

    def window(name, hours=6):
        values = (hourly.get(name) or [])[start:start + hours]
        return [float(value) for value in values if value is not None]

    daily_times = daily.get("time") or []
    daily_rain = daily.get("precipitation_sum") or []
    by_day = dict(zip(daily_times, daily_rain))
    today = now.date()
    today_rain = by_day.get(today.isoformat())
    past_rain = [by_day.get((today - timedelta(days=i)).isoformat()) for i in range(1, 31)]
    monthly_rain = round(sum(float(v) for v in past_rain), 2) if all(v is not None for v in past_rain) else None
    next_6h_rain = sum(window("precipitation"))
    max_rain_prob = max(window("precipitation_probability"), default=0)
    rainfall_status = "Low"
    if next_6h_rain >= 20 or max_rain_prob >= 80:
        rainfall_status = "High"
    elif next_6h_rain >= 5 or max_rain_prob >= 50:
        rainfall_status = "Moderate"
    wind_kmh = current.get("wind_speed_10m")
    code = current.get("weather_code")
    return {
        "latitude": lat,
        "longitude": lon,
        "temperature_c": current.get("temperature_2m"),
        "temperature_current_c": current.get("temperature_2m"),
        "humidity_current_pct": current.get("relative_humidity_2m"),
        "climate_field_metadata": {
            "temperature_current_c": {"unit": "C", "period": "current", "source": "Open-Meteo", "quality": "modelled"},
            "humidity_current_pct": {"unit": "%", "period": "current", "source": "Open-Meteo", "quality": "modelled"},
            "rainfall_30d_mm": {"unit": "mm", "period": "rolling_30_days", "source": "Open-Meteo", "quality": "modelled",
                                "start": (today - timedelta(days=30)).isoformat(), "end_exclusive": today.isoformat()},
        },
        "live_humidity": current.get("relative_humidity_2m"),
        "rainfall_mm": monthly_rain,
        "rainfall_monthly_mm": monthly_rain,
        "monthly_rainfall_mm": monthly_rain,
        "rainfall_30d_mm": monthly_rain,
        "rainfall_today_mm": today_rain,
        "today_rainfall_mm": today_rain,
        "daily_rainfall_mm": today_rain,
        "current_precipitation_mm": current.get("precipitation", current.get("rain")),
        "rain_next_3h_mm": round(sum(window("precipitation", 3)), 2),
        "rain_next_6h_mm": round(next_6h_rain, 2),
        "rain_probability_next_3h": max(window("precipitation_probability", 3), default=0),
        "rain_probability_next_6h": round(max_rain_prob, 1),
        "rainfall_status": rainfall_status,
        "wind_speed_kmh": wind_kmh,
        "wind_speed_ms": float(wind_kmh) / 3.6 if wind_kmh is not None else None,
        "max_wind_next_6h_kmh": max(window("wind_speed_10m"), default=0),
        "max_temp_next_6h_c": max(window("temperature_2m"), default=0),
        "weather_codes_next_6h": [int(v) for v in window("weather_code")],
        "cloud_cover_pct": current.get("cloud_cover"),
        "weather_code": code,
        "weather_description": WEATHER_CODE_TEXT.get(code, "Weather data available"),
        "weather_updated_at": current_time,
        "weather_source": "Open-Meteo",
        "weather_is_realtime": True,
    }



@app.get("/health")
def health():
    from rainfallDatasets import model_health
    model = model_health()
    return {"status": "ok" if model['status'] == 'loaded' else 'degraded',
            "service": "GeoSustain API", "revision": os.getenv('RENDER_GIT_COMMIT'),
            "model": model}

@app.get('/api/mobile/crops')
def mobile_crop_catalog():
    from crop_requirements import catalog
    return catalog()


@app.get("/api/health")
def api_health():
    return health()


@app.on_event("startup")
def startup() -> None:
    # Do not let a temporary Supabase/network issue crash the web service.
    # Uvicorn can still expose /health while the database is unavailable.
    try:
        init_db()
        print("Database initialized successfully.")
        from push_delivery import start_worker
        start_worker()
        from analysis_jobs import start_worker as start_analysis_worker
        start_analysis_worker()
    except Exception as exc:
        print(f"Database initialization warning: {exc}")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def flash(request: Request, message: str, category: str = "info") -> None:
    request.session.setdefault("_flash", []).append((category, message))


def render_template(request: Request, template: str, context: Optional[Dict[str, Any]] = None):
    ctx = {"request": request}
    if context:
        ctx.update(context)
    # Make Flask-style flash work for the current request.
    templates.env.globals["get_flashed_messages"] = lambda with_categories=False: _get_flashed_messages(
        request, with_categories
    )
    return templates.TemplateResponse(request, template, ctx)


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt(rounds=12)).decode("utf-8")


def sign_in_user(request: Request, user) -> None:
    request.session.clear()
    request.session['sid'] = secrets.token_urlsafe(32)
    defense_db.start_session(user['id'], request.session['sid'], MOBILE_TOKEN_MAX_AGE)
    request.session["user_id"] = user["id"]
    request.session["username"] = user["username"]
    request.session["role"] = user["role"]
    request.session['password_version'] = user.get('password_version',0)


def current_user(request: Request):
    uid = request.session.get("user_id")
    user = get_user_by_id(uid) if uid else None
    if user and not defense_db.session_revoked(request.session.get('sid')) and user.get('is_active',True) and request.session.get('password_version',0) == user.get('password_version',0):
        return user
    return None


def require_web_user(request: Request):
    user = current_user(request)
    if not user:
        raise HTTPException(status_code=status.HTTP_307_TEMPORARY_REDIRECT, headers={"Location": "/login"})
    return user


def generate_mobile_token(user) -> str:
    sid = secrets.token_urlsafe(32)
    defense_db.start_session(user['id'], sid, MOBILE_TOKEN_MAX_AGE)
    return token_serializer.dumps(
        {"id": user["id"], "sid": sid, "password_version": user.get('password_version',0)},
        salt="geosustain-mobile",
    )


def user_public_dict(user) -> Dict[str, Any]:
    return {
        "id": user["id"],
        "username": user["username"],
        "email": user["email"],
        "role": user["role"],
        "location": user.get('location'),
        "profile_photo": user.get('profile_photo'),
        "email_verified": bool(user.get('email_verified')),
        "auth_provider": user.get('auth_provider', 'email'),
        "google_linked": bool(user.get('google_sub')),
        "phone_number": user.get('phone_number'),
        "phone_verified": user.get('phone_verified_at') is not None,
    }


def get_api_user(request: Request):
    auth_header = request.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Unauthorized. Please log in again.")
    token = auth_header.split(" ", 1)[1].strip()
    try:
        payload = token_serializer.loads(token, salt="geosustain-mobile", max_age=MOBILE_TOKEN_MAX_AGE)
    except (BadSignature, SignatureExpired):
        raise HTTPException(status_code=401, detail="Unauthorized. Please log in again.")
    user = get_user_by_id(payload.get("id"))
    if not user or not user.get('is_active',True) or payload.get('password_version',0) != user.get('password_version',0) or defense_db.session_revoked(payload.get('sid')):
        raise HTTPException(status_code=401, detail="Unauthorized. Please log in again.")
    return user


# ---------------------------------------------------------------------------
# Analysis helpers
# ---------------------------------------------------------------------------
def _pretty_place_name(address: Dict[str, Any]) -> str:
    barangay = (
        address.get("suburb")
        or address.get("village")
        or address.get("neighbourhood")
        or address.get("quarter")
        or address.get("hamlet")
        or address.get("barangay")
    )
    city = (
        address.get("city")
        or address.get("town")
        or address.get("municipality")
        or address.get("county")
        or "Panabo City"
    )
    if barangay and str(barangay).strip():
        name = str(barangay).strip()
        if not name.lower().startswith("brgy"):
            name = f"Brgy. {name}"
        return f"{name}, {city}"
    return str(city)


# Barangay fallback resolver for study area coordinates. Nominatim/OpenStreetMap
# sometimes returns only "Panabo City area" for farm parcels, so this gives the
# app a useful barangay-style label even when reverse geocoding is incomplete.
# Coordinates are approximate barangay centers used only as a display fallback.
STUDY_PLACE_CENTERS = [
    (7.2915, 125.6255, "Panabo City Poblacion, Panabo"),
    (7.3310, 125.6740, "Brgy. San Francisco, Panabo"),
    (7.3089, 125.6842, "Brgy. San Vicente, Panabo"),
    (7.3925, 125.6803, "Brgy. Quezon, Panabo"),
    (7.3278, 125.6715, "Brgy. Cebulano, Carmen"),
    (7.3480, 125.6500, "Brgy. New Visayas, Panabo"),
    (7.3650, 125.6400, "Brgy. Salvacion, Panabo"),
    (7.3820, 125.6300, "Brgy. Ising, Carmen"),
    (7.3950, 125.6000, "Brgy. Mangalcal, Carmen"),
    (7.2951, 125.7028, "Brgy. Datu Abdul Dadia, Panabo"),
    (7.2750, 125.6520, "Brgy. Gredu, Panabo"),
    (7.2500, 125.6100, "Brgy. Kasilak, Panabo"),
]


def study_area_place_fallback(lat: float, lon: float) -> str:
    best = min(
        STUDY_PLACE_CENTERS,
        key=lambda item: (lat - item[0]) ** 2 + (lon - item[1]) ** 2,
    )
    return best[2]


def reverse_geocode_place(lat: float, lon: float) -> str:
    """Resolve coordinates to a barangay-style place label via OpenStreetMap Nominatim."""
    params = urllib.parse.urlencode(
        {
            "format": "jsonv2",
            "lat": lat,
            "lon": lon,
            "addressdetails": 1,
            "zoom": 18,
            "accept-language": "en",
        }
    )
    url = f"https://nominatim.openstreetmap.org/reverse?{params}"
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "GeoSustainCapstone/1.0 (student capstone project)"},
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
        if isinstance(payload, dict):
            address = payload.get("address")
            if isinstance(address, dict):
                return _pretty_place_name(address)
            display = payload.get("display_name")
            if display:
                return ", ".join(str(display).split(",")[:2]).strip()
    except Exception:
        pass
    return study_area_place_fallback(float(lat), float(lon))


def polygon_centroid(latlngs: List[Dict[str, float]]) -> Tuple[Optional[float], Optional[float]]:
    from geometry import polygon_centroid as area_centroid
    return area_centroid(latlngs)


def point_in_polygon(lat: float, lon: float, polygon: List[Dict[str, float]]) -> bool:
    inside = False
    j = len(polygon) - 1
    for i in range(len(polygon)):
        yi = float(polygon[i]["lat"])
        xi = float(polygon[i]["lng"])
        yj = float(polygon[j]["lat"])
        xj = float(polygon[j]["lng"])
        intersects = ((yi > lat) != (yj > lat)) and (
            lon < (xj - xi) * (lat - yi) / ((yj - yi) or 1e-12) + xi
        )
        if intersects:
            inside = not inside
        j = i
    return inside


def polygon_area_sample_points(polygon: List[Dict[str, float]], max_points: int = 7) -> List[Tuple[float, float]]:
    center = polygon_centroid(polygon)
    samples: List[Tuple[float, float]] = []
    if center[0] is not None and center[1] is not None and point_in_polygon(*center, polygon):
        samples.append((float(center[0]), float(center[1])))

    lats = [float(p["lat"]) for p in polygon]
    lons = [float(p["lng"]) for p in polygon]
    min_lat, max_lat = min(lats), max(lats)
    min_lon, max_lon = min(lons), max(lons)

    for row in range(1, 4):
        for col in range(1, 4):
            lat = min_lat + (max_lat - min_lat) * row / 4
            lon = min_lon + (max_lon - min_lon) * col / 4
            if point_in_polygon(lat, lon, polygon):
                candidate = (round(lat, 6), round(lon, 6))
                if candidate not in samples:
                    samples.append(candidate)
            if len(samples) >= max_points:
                return samples

    for p in polygon:
        candidate = (float(p["lat"]), float(p["lng"]))
        if candidate not in samples:
            samples.append(candidate)
        if len(samples) >= max_points:
            break
    return samples


def merge_area_results(results: List[Dict[str, Any]]) -> Dict[str, Any]:
    if not results:
        return {}

    merged = dict(results[0])
    numeric_keys = set()
    for result in results:
        for key, value in result.items():
            if isinstance(value, (int, float)) and not isinstance(value, bool):
                numeric_keys.add(key)
    for key in numeric_keys:
        values = [float(r[key]) for r in results if isinstance(r.get(key), (int, float))]
        if values:
            merged[key] = sum(values) / len(values)

    # Aggregate per-variable data quality across every sampled point in the
    # polygon, so a farm-wide result honestly reflects how much of it was
    # actually measured vs. estimated — rather than `dict(results[0])`
    # above silently carrying over only the FIRST sample point's quality
    # info as if it applied to the whole farm.
    total_samples = len(results)
    quality_vars = set()
    for result in results:
        quality_vars.update((result.get('data_quality') or {}).keys())
    aggregated_quality: Dict[str, Any] = {}
    aggregated_warnings: List[str] = []
    _display_names = {
        'rainfall': 'Rainfall', 'temperature': 'Temperature', 'elevation': 'Elevation',
        'ndvi': 'NDVI (vegetation index)', 'soil_ph': 'Soil pH', 'humidity': 'Humidity',
        'nitrogen': 'Soil nitrogen', 'phosphorus': 'Phosphorus', 'potassium': 'Potassium',
    }
    for var in quality_vars:
        entries = [(r.get('data_quality') or {}).get(var) for r in results]
        entries = [e for e in entries if e]
        if not entries:
            continue
        fallback_count = sum(1 for e in entries if e.get('quality') == 'fallback_default')
        measured_count = sum(1 for e in entries if e.get('quality') == 'measured')
        proxy_count = sum(1 for e in entries if e.get('quality') == 'estimated_proxy')
        overall = 'measured' if fallback_count == 0 and proxy_count == 0 else (
            'estimated_proxy' if fallback_count == 0 else (
                'fallback_default' if fallback_count == len(entries) else 'partial_fallback'
            )
        )
        aggregated_quality[var] = {
            'overall_quality': overall,
            'measured_samples': measured_count,
            'fallback_samples': fallback_count,
            'total_samples': len(entries),
        }
        if fallback_count > 0:
            label = _display_names.get(var, var.replace('_', ' ').title())
            if fallback_count == len(entries):
                aggregated_warnings.append(f"{label} could not be retrieved from a live source anywhere on this farm — a regional typical value was used instead.")
            else:
                aggregated_warnings.append(f"{label} could not be retrieved from a live source at {fallback_count} of {len(entries)} sampled locations on this farm — a regional typical value was used there instead.")
    merged['data_quality'] = aggregated_quality
    merged['data_quality_warnings'] = aggregated_warnings
    merged['data_quality_sample_count'] = total_samples

    # A polygon is treated as non-arable when at least half of the valid
    # samples were classified as water, built-up/infrastructure, or degraded.
    # This prevents generic advisory labels from being counted as crop names.
    non_arable = [r for r in results if r.get('is_crop_recommended') is False]
    if len(non_arable) >= max(1, (len(results) + 1) // 2):
        from collections import Counter
        type_counts = Counter(str(r.get('land_type') or 'non-arable') for r in non_arable)
        dominant_type = type_counts.most_common(1)[0][0]
        candidates = [r for r in non_arable if str(r.get('land_type') or 'non-arable') == dominant_type]
        representative = candidates[0] if candidates else non_arable[0]
        for key in (
            'land_type', 'land_status', 'recommendation_title', 'recommendation',
            'land_use_recommendations', 'xai_explanation', 'infrastructure_suitability',
            'infrastructure_status', 'infrastructure_risk', 'infrastructure_recommendation'
        ):
            if representative.get(key) is not None:
                merged[key] = representative.get(key)
        merged['is_crop_recommended'] = False
        merged['predicted_crop'] = representative.get('land_status') or representative.get('recommendation_title')
        merged['crop'] = None
        merged['raw_predicted_crop'] = None
        merged['crop_compatibility_pct'] = 0.0
        merged['suitability_level'] = 'NOT RECOMMENDED'
        merged['best_crop'] = None
        merged['top_crop_recommendations'] = []
        merged['alternative_crops'] = []
        merge_model_snapshots(results, merged)
        return merged

    # For arable polygons, rank only genuine crop recommendations.
    crop_scores: Dict[str, List[float]] = {}
    crop_examples: Dict[str, Dict[str, Any]] = {}
    for result in results:
        if result.get('is_crop_recommended') is not True:
            continue
        crop = result.get('predicted_crop') or result.get('crop')
        if crop:
            score = result.get('crop_compatibility_pct') or result.get('suitability_pct') or 0
            try:
                crop_scores.setdefault(str(crop), []).append(float(score))
            except Exception:
                crop_scores.setdefault(str(crop), []).append(0.0)
            crop_examples[str(crop)] = result
    if crop_scores:
        best_crop = max(crop_scores.items(), key=lambda item: (len(item[1]), sum(item[1]) / max(len(item[1]), 1)))[0]
        representative = crop_examples[best_crop]
        merged['is_crop_recommended'] = True
        merged['predicted_crop'] = best_crop
        merged['crop'] = best_crop
        merged['crop_compatibility_pct'] = sum(crop_scores[best_crop]) / max(len(crop_scores[best_crop]), 1)
        for key in ('recommendation_title', 'land_status', 'xai_explanation', 'top_crop_recommendations', 'alternative_crops', 'suitability_level'):
            if representative.get(key) is not None:
                merged[key] = representative.get(key)
    merge_model_snapshots(results, merged)
    return merged



def _safe_number(value, default=None):
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def fetch_multi_year_monthly_baseline(lat: float, lon: float, month: int) -> Dict[str, Any]:
    """Return a cached 20-year monthly climate baseline from NASA POWER.

    The request is intentionally short and failure-tolerant: analyses continue
    with recent conditions if the external climate service is unavailable.
    """
    cached = get_climate_baseline(lat, lon, month)
    if cached:
        return cached
    start_year, end_year = 2005, 2024
    try:
        url = 'https://power.larc.nasa.gov/api/temporal/monthly/point'
        params = {
            'parameters': 'T2M,PRECTOTCORR,RH2M', 'community': 'AG',
            'longitude': lon, 'latitude': lat,
            'start': start_year, 'end': end_year, 'format': 'JSON',
        }
        response = requests.get(url, params=params, timeout=12)
        response.raise_for_status()
        payload = response.json()
        parameter = payload.get('properties', {}).get('parameter', {})
        month_key = f'{int(month):02d}'
        def month_values(name):
            source = parameter.get(name) or {}
            vals=[]
            for key,val in source.items():
                if str(key).endswith(month_key) and isinstance(val,(int,float)) and val > -900:
                    vals.append(float(val))
            return vals
        temps=month_values('T2M'); rains=month_values('PRECTOTCORR'); hums=month_values('RH2M')
        values={
            'mean_temperature_c': sum(temps)/len(temps) if temps else None,
            'mean_rainfall_mm': sum(rains)/len(rains) if rains else None,
            'mean_humidity_pct': sum(hums)/len(hums) if hums else None,
            'baseline_start_year': start_year, 'baseline_end_year': end_year,
            'source_name': 'NASA POWER',
        }
        return save_climate_baseline(lat, lon, month, values) or values
    except Exception as exc:
        print(f'NASA POWER baseline unavailable: {exc}')
        return {'baseline_start_year': start_year, 'baseline_end_year': end_year,
                'source_name': 'NASA POWER (temporarily unavailable)'}


def _distribution(values: List[float], classifier):
    clean=[float(v) for v in values if isinstance(v,(int,float))]
    if not clean:
        return None
    labels=[classifier(v) for v in clean]
    from collections import Counter
    counts=Counter(labels); dominant,count=counts.most_common(1)[0]
    return {'minimum':min(clean),'maximum':max(clean),'average':sum(clean)/len(clean),
            'dominant_class':dominant,'dominant_pct':round(count*100/len(clean),1),
            'sample_count':len(clean),'classes':dict(counts)}


def build_analysis_summary(result: Dict[str, Any]) -> Dict[str, Any]:
    grid=result.get('heatmap_grid') if isinstance(result.get('heatmap_grid'),list) else []
    vals=lambda key:[_safe_number(x.get(key)) for x in grid if isinstance(x,dict) and _safe_number(x.get(key)) is not None]
    slope=_distribution(vals('slope'), lambda v:'flat' if v<=3 else 'gently sloping' if v<=8 else 'moderately sloping' if v<=18 else 'steep')
    elev=_distribution(vals('elevation'), lambda v:'low-lying' if v<20 else 'slightly elevated' if v<100 else 'elevated')
    ndvi=_distribution(vals('ndvi'), lambda v:'very low vegetation' if v<.1 else 'sparse vegetation' if v<.3 else 'moderate vegetation' if v<.6 else 'dense vegetation')
    rainfall=_distribution(vals('rainfall'), lambda v:'low rainfall' if v<50 else 'moderate rainfall' if v<150 else 'high rainfall')
    ph=_distribution(vals('soil_ph'), lambda v:'acidic' if v<5.5 else 'near-neutral' if v<=7.5 else 'alkaline')
    crop=result.get('predicted_crop') or result.get('land_status') or 'This land'
    recommended=result.get('is_crop_recommended') is not False

    # Short, plain-language summary for the Farmer-facing app (Section 11 /
    # Section 23): one or two everyday sentences, no raw decimal dumps.
    # The detailed numeric breakdown lives in `environmental_distributions`
    # and the full `xai_explanation` for anyone (Analyst, report) who wants it.
    if recommended:
        bits = []
        if ndvi and ndvi['dominant_class'] in ('moderate vegetation', 'dense vegetation'):
            bits.append('healthy vegetation')
        if rainfall and rainfall['dominant_class'] in ('moderate rainfall', 'high rainfall'):
            bits.append('good rainfall')
        if ph and ph['dominant_class'] == 'near-neutral':
            bits.append('balanced soil')
        if bits:
            plain = f"{crop} looks like a strong choice for this land — it has {', '.join(bits)}."
        else:
            plain = f"{crop} is the best available match for this land based on its current conditions."
        if slope and slope['dominant_class'] in ('moderately sloping', 'steep'):
            plain += ' The land is somewhat sloped, so consider erosion control.'
    else:
        plain = f"{crop.title() if isinstance(crop, str) else crop} — this land may need some preparation before a crop is recommended. See the explanation below for details."

    result['analysis_summary']=plain
    result['environmental_distributions']={'slope':slope,'elevation':elev,'ndvi':ndvi,'rainfall':rainfall,'soil_ph':ph}
    return result


def build_analysis_result(body: Optional[Dict[str, Any]] = None, query_args: Optional[Dict[str, Any]] = None):
    analysis_source = None
    polygon = []

    if body is not None:
        polygon = body.get("polygon", []) or []
        lat = body.get("lat")
        lon = body.get("lon")

        if polygon:
            polygon = normalize_polygon(polygon)
            lat, lon = polygon_centroid(polygon)
            analysis_source = "selected-polygon"
        elif lat is not None and lon is not None:
            lat = float(lat)
            lon = float(lon)
            analysis_source = "query-point"
        else:
            raise ValueError("Send either polygon with at least 3 points or lat/lon.")
    else:
        query_args = query_args or {}
        lat = query_args.get("lat")
        lon = query_args.get("lon")
        if lat is None or lon is None:
            raise ValueError("lat and lon query parameters are required.")
        lat = float(lat)
        lon = float(lon)
        analysis_source = "query-point"

    if analyze_location is None:
        raise RuntimeError(
            f"Analysis engine failed to load on server: {ANALYSIS_IMPORT_ERROR}"
        )

    if not in_study_area(lat, lon):
        raise ValueError('Selected location is outside the supported Panabo study area.')

    logging.getLogger('uvicorn.error').info('Analysis geometry validated source=%s vertices=%s', analysis_source, len(polygon))
    # Enforced on both formal API routes, before provider calls or ranking.
    coverage, matched_soil = (require_analysis_coverage(polygon) if polygon
                              else require_point_coverage(lat, lon))
    preliminary = coverage['analysis_mode'] == 'preliminary_environmental'

    # Fetched once per analysis request (not once per sampled point) — a
    # Super Administrator's crop reference table can temporarily narrow the
    # approved crop set (Section 17); this can only ever remove a crop from
    # consideration, never add one outside CROP_ENV_PROFILES (Section 9).
    # Fails open (None = no restriction) on any DB error.
    active_crops = get_active_crop_keys()

    try:
        cover = screen_land_cover(lat, lon, polygon)
    except Exception as exc:
        logging.getLogger('uvicorn.error').warning('Land-cover screening unavailable type=%s', type(exc).__name__)
        raise ModelRankingUnavailable('Land-cover verification is unavailable. Please retry; crop recommendations are withheld until water and built-up areas can be checked.') from exc

    if not cover['allow_crops']:
        result = advisory_result(cover)
    elif polygon and len(polygon) >= 3:
        sample_points = polygon_area_sample_points(polygon, max_points=9)
        # Analyze independent parcel samples concurrently. Four workers avoids
        # overwhelming Earth Engine/external sources while reducing the old
        # multi-minute sequential wait substantially.
        ordered_results = [None] * len(sample_points)
        model_failures = []
        with ThreadPoolExecutor(max_workers=min(4, len(sample_points))) as executor:
            future_to_index = {
                executor.submit(analyze_location, sample_lat, sample_lon, active_crops, **({'preliminary': True} if preliminary else {})): index
                for index, (sample_lat, sample_lon) in enumerate(sample_points)
            }
            for future in as_completed(future_to_index):
                index = future_to_index[future]
                try:
                    ordered_results[index] = future.result()
                except Exception as exc:
                    logging.getLogger('uvicorn.error').warning('Polygon sample failed sample=%s type=%s', index + 1, type(exc).__name__)
                    if isinstance(exc, ModelRankingUnavailable):
                        model_failures.append(str(exc))
        if model_failures:
            raise ModelRankingUnavailable(' '.join(sorted(set(model_failures))))
        sample_results = [item for item in ordered_results if item is not None]
        if not sample_results:
            raise RuntimeError("All polygon sample analyses failed.")
        logging.getLogger('uvicorn.error').info('Polygon samples completed successful=%s requested=%s', len(sample_results), len(sample_points))
        if any(item.get('scoring_version') for item in sample_results):
            from environmental_pipeline import merge_results
            if len(sample_results) != len(sample_points):
                raise RuntimeError('Some parcel samples failed; retry when datasets are available.')
            result = merge_results(sample_results, active_crops)
        else:
            result = merge_area_results(sample_results)
        result["polygon_area_sample_count"] = len(sample_points)
        result["polygon_area_samples"] = [{"lat": p[0], "lng": p[1]} for p in sample_points]
        # Persist parcel-level grid values so the planner can inspect real
        # spatial variation instead of a single center-point result.
        heatmap_grid = []
        for (sample_lat, sample_lon), sample in zip(sample_points, ordered_results):
            if sample is None:
                continue
            heatmap_grid.append({
                "lat": float(sample_lat),
                "lng": float(sample_lon),
                "ndvi": sample.get("ndvi"),
                "crop_suitability": sample.get("crop_compatibility_pct") if sample.get("crop_compatibility_pct") is not None else sample.get("suitability_pct"),
                "soil_ph": sample.get("soil_ph"),
                "rainfall": sample.get("rainfall_mm"),
                "elevation": sample.get("elevation_m"),
                "slope": sample.get("slope_pct") if sample.get("slope_pct") is not None else sample.get("slope"),
            })
        result["heatmap_grid"] = heatmap_grid
    else:
        result = analyze_location(lat, lon, active_crops, **({'preliminary': True} if preliminary else {}))

    result["land_cover"] = cover
    result["cagro_soil"] = matched_soil
    result['analysis_mode'] = coverage['analysis_mode']
    if preliminary:
        result['preliminary_notice'] = 'Preliminary environmental screening. CAGRO NPK unavailable for this farm; no complete soil suitability claim is made.'
    result.update(analysis_schema_version=COVERAGE_VERSION, analysis_coverage=coverage,
                  nutrient_basis='CAGRO historical local evidence; legacy Random Forest nutrient proxies remain separate',
                  historical_soil_notice=HISTORICAL_NOTE,
                  centroid_method=('Area-weighted polygon centroid; not a soil sample coordinate' if polygon
                                   else 'Selected point; not a farm centroid or soil sample coordinate'))
    result.update(nutrient_layers(result["cagro_soil"], result))
    planting_month = int((body or {}).get("intended_planting_month") or datetime.now().month)
    if not result.get('scoring_version'):
        result = apply_local_seasonality(result, planting_month)

    result["selected_polygon"] = polygon
    result["analysis_source"] = analysis_source
    result["selection_type"] = "Polygon boundary area" if polygon and len(polygon) >= 3 else "Point location"
    result["center_lat"] = float(lat)
    result["center_lon"] = float(lon)
    result["lat"] = float(lat)
    result["lon"] = float(lon)
    if polygon:
        result['area_m2'] = polygon_area_m2(polygon)
        result['area_hectares'] = result['area_m2'] / 10000.0
    if body is not None and body.get("place_name"):
        result["place_name"] = str(body["place_name"]).strip()
    else:
        result["place_name"] = reverse_geocode_place(float(lat), float(lon))
    if result.get('scoring_version'):
        result['intended_planting_month'] = planting_month
        return result, analysis_source
    baseline = fetch_multi_year_monthly_baseline(float(lat), float(lon), planting_month)
    result["historical_climate_baseline"] = baseline
    # A selected-month baseline and rolling air-temperature mean are different
    # temporal variables. Keep evidence separate; do not synthesize a blend.
    result["temperature_method"] = "Historical monthly baseline and analysis temperature retained separately; no cross-period blend"
    result = build_analysis_summary(result)
    result = finalize_explanation(result)
    return result, analysis_source


# ---------------------------------------------------------------------------
# Pydantic models for mobile/API JSON
# ---------------------------------------------------------------------------
class RegisterBody(BaseModel):
    username: str = Field(min_length=3, max_length=50)
    email: str = Field(max_length=100)
    password: str = Field(min_length=8, max_length=72)
    role: str = "farmer"

    @field_validator('username', 'email', mode='before')
    @classmethod
    def strip_identity(cls, value):
        return value.strip() if isinstance(value, str) else value

    @field_validator('email')
    @classmethod
    def valid_email(cls,value):
        try:
            return validate_email(value,check_deliverability=False).normalized.lower()
        except EmailNotValidError:
            raise ValueError('Enter a valid email address.')

    @field_validator('password')
    @classmethod
    def password_size(cls,value):
        return validate_new_password(value)


class LoginBody(BaseModel):
    email: str = Field(max_length=100)
    password: str = Field(default="", max_length=1024)


class AnalysisBody(BaseModel):
    lat: Optional[float] = Field(default=None, ge=-90, le=90, allow_inf_nan=False)
    lon: Optional[float] = Field(default=None, ge=-180, le=180, allow_inf_nan=False)
    polygon: Optional[List[Dict[str, float]]] = None
    place_name: Optional[str] = None
    intended_planting_month: Optional[int] = Field(default=None, ge=1, le=12)
    farm_id: Optional[int] = None

    @field_validator('polygon')
    @classmethod
    def finite_coordinates(cls, value):
        if value is not None:
            for point in value:
                lat, lon = point.get('lat'), point.get('lng', point.get('lon'))
                if lat is None or lon is None or not (-90 <= lat <= 90 and -180 <= lon <= 180):
                    raise ValueError('Polygon coordinates must be finite and within latitude/longitude ranges.')
        return value


class SessionActionBody(BaseModel):
    session_id: int
    title: Optional[str] = None


class ProfileUpdateBody(BaseModel):
    """Self-service profile fields only.

    SECURITY: `role` is intentionally NOT a field here. Role changes must
    only ever happen through the Super Administrator endpoint
    (`PATCH /api/admin/users/{user_id}`, guarded by `require_super_admin`).
    Even if a client sends a `role` key in the JSON body, Pydantic drops
    unknown fields by default, so it is never parsed, never reaches
    `update_user_profile`, and is silently ignored rather than applied.
    """
    username: Optional[str] = Field(default=None, min_length=3, max_length=50)
    location: Optional[str] = Field(default=None, max_length=200)
    profile_photo: Optional[str] = None
    phone_number: Optional[str] = Field(default=None, max_length=16)

    @field_validator('phone_number')
    @classmethod
    def valid_phone(cls, value):
        from federated_identity import normalize_phone
        return normalize_phone(value) if value else value

    @field_validator('profile_photo')
    @classmethod
    def valid_photo(cls, value):
        return validate_profile_photo(value)

    @field_validator('username',mode='before')
    @classmethod
    def strip_username(cls,value):
        return value.strip() if isinstance(value,str) else value


class ChangePasswordBody(BaseModel):
    current_password: str = Field(max_length=1024)
    new_password: str = Field(min_length=8, max_length=72)

    @field_validator('new_password')
    @classmethod
    def password_size(cls,value):
        return RegisterBody.password_size(value)


class AdminUserUpdateBody(BaseModel):
    role: Optional[str] = None
    is_active: Optional[bool] = None


# ---------------------------------------------------------------------------
# Web routes
# ---------------------------------------------------------------------------
@app.get("/", response_class=HTMLResponse)
def index(request: Request):
    if request.session.get("user_id"):
        return RedirectResponse("/dashboard", status_code=302)
    return RedirectResponse("/login", status_code=302)


@app.get("/login", response_class=HTMLResponse, name="login")
def login_page(request: Request):
    if request.session.get("user_id"):
        return RedirectResponse("/dashboard", status_code=302)
    return render_template(request, "login.html")


@app.post("/login", name="login")
async def login_submit(request: Request):
    form = await request.form()
    email = str(form.get("email", "")).strip().lower()
    password = str(form.get("password", ""))

    if not email or not password:
        flash(request, "Email and password are required.", "error")
        return render_template(request, "login.html")

    user = get_user_by_email(email)
    if not verify_password(password, user.get("password_hash") if user else None):
        flash(request, "Invalid email or password.", "error")
        return render_template(request, "login.html")

    if user.get("is_active") is False:
        flash(request, "This account is deactivated.", "error")
        return render_template(request, "login.html")

    sign_in_user(request, user)
    return RedirectResponse("/dashboard", status_code=302)


@app.get("/register", response_class=HTMLResponse, name="register")
def register_page(request: Request):
    if request.session.get("user_id"):
        return RedirectResponse("/dashboard", status_code=302)
    return render_template(request, "register.html")


@app.post("/register", name="register")
async def register_submit(request: Request):
    form = await request.form()
    username = str(form.get("username", "")).strip()
    email = str(form.get("email", "")).strip().lower()
    password = str(form.get("password", ""))
    confirm = str(form.get("confirm_password", ""))
    role = str(form.get("role", "farmer"))

    errors = []
    if not username or len(username) < 3:
        errors.append("Username must be at least 3 characters.")
    if not email or "@" not in email:
        errors.append("A valid email is required.")
    try:
        validated = RegisterBody(username=username, email=email, password=password)
        email = validated.email
    except ValueError:
        errors.append("Use a valid name/email and a password of at least 8 characters with no spaces and at least one special character.")
    if password != confirm:
        errors.append("Passwords do not match.")
    role = "farmer"  # Privileged accounts are assigned by a Super Administrator.
    if get_user_by_email(email):
        errors.append("Email is already registered.")

    if errors:
        for error in errors:
            flash(request, error, "error")
        return render_template(request, "register.html", {"username": username, "email": email, "role": role})

    if email_verification.enabled():
        try:
            challenge = email_verification.start(username, email, hash_password(password), SECRET_KEY)
            request.session['email_signup_ticket'] = challenge['verification_ticket']
            return render_template(request, 'verify_signup.html', {'email': email})
        except HTTPException as exc:
            flash(request, str(exc.detail), 'error')
            return render_template(request, 'register.html', {'username': username, 'email': email})

    user = create_user(username, email, hash_password(password), role, email_verified=False, auth_provider="email")
    if not user:
        flash(request, "Registration failed. Please try again.", "error")
        return render_template(request, "register.html")

    flash(request, "Account created! Please log in.", "success")
    return RedirectResponse("/login", status_code=302)


@app.get("/verify-email")
def email_verify_page(request: Request):
    if not request.session.get('email_signup_ticket'):
        return RedirectResponse('/login', status_code=303)
    return render_template(request, 'verify_signup.html')


@app.post("/verify-email")
@app.post("/resend-verification")
async def email_verify_form(request: Request):
    ticket = request.session.get('email_signup_ticket')
    if not email_verification.enabled() or not ticket:
        return RedirectResponse('/login', status_code=303)
    try:
        if request.url.path == '/resend-verification':
            email_verification.resend(ticket, SECRET_KEY)
            flash(request, 'A new code was sent.', 'success')
        else:
            form = await request.form()
            code = str(form.get('code', ''))
            if len(code) != 6 or not code.isascii() or not code.isdigit():
                raise HTTPException(400, 'Enter the six-digit code from your email.')
            email_verification.verify(ticket, code, SECRET_KEY)
            request.session.pop('email_signup_ticket', None)
            flash(request, 'Email verified. Please sign in.', 'success')
            return RedirectResponse('/login', status_code=303)
    except HTTPException as exc:
        flash(request, str(exc.detail), 'error')
    return render_template(request, 'verify_signup.html')


@app.get("/logout", name="logout")
def logout(request: Request):
    sid = request.session.get('sid')
    if sid:
        defense_db.revoke_session(sid)
    request.session.clear()
    return RedirectResponse("/login", status_code=302)


@app.get("/dashboard", response_class=HTMLResponse, name="dashboard")
def dashboard(request: Request):
    user = current_user(request)
    if not user:
        return RedirectResponse("/login", status_code=302)
    return render_template(request, "index.html", {"user": user})


@app.get("/history", response_class=HTMLResponse, name="history")
def history(request: Request, offset: int = Query(0, ge=0)):
    user = current_user(request)
    if not user:
        return RedirectResponse("/login", status_code=302)
    rows = get_user_history(user["id"], limit=21, offset=offset)
    return render_template(request, "history.html", {"user": user, "history": rows[:20],
        "offset":offset, "has_more":len(rows)>20})


# ---------------------------------------------------------------------------
# Web JSON API
# ---------------------------------------------------------------------------
@app.post("/api/analysis")
async def analysis(request: Request):
    user = current_user(request)
    if not user:
        raise HTTPException(status_code=401, detail='Please sign in to continue.')
    if request.headers.get('sec-fetch-site') == 'cross-site':
        raise HTTPException(status_code=403, detail='Cross-site submission rejected.')
    origin = request.headers.get('origin')
    if origin and urllib.parse.urlsplit(origin).netloc != request.headers.get('host'):
        raise HTTPException(status_code=403, detail='Cross-site submission rejected.')
    key = request.headers.get('idempotency-key')
    if not key:
        raise HTTPException(status_code=400, detail='Idempotency-Key is required for safe retries.')
    try:
        body = AnalysisBody.model_validate(await request.json())
    except (ValueError, TypeError):
        raise HTTPException(status_code=422, detail='Invalid analysis inputs.')
    return mobile_analysis(body, user, key)


# ---------------------------------------------------------------------------
# Mobile JSON API
# ---------------------------------------------------------------------------
@app.post("/api/mobile/register", status_code=201)
def mobile_register(body: RegisterBody):
    role = "farmer"
    username = body.username.strip()
    email = body.email.lower().strip()

    if len(username) < 3 or "@" not in email:
        return JSONResponse({"error": "Enter a valid username and email."}, status_code=400)
    if len(body.password.encode("utf-8")) > 72:
        return JSONResponse({"error": "Password must be at most 72 UTF-8 bytes."}, status_code=400)
    if get_user_by_email(email):
        return JSONResponse({"error": "Email is already registered. Please log in."}, status_code=409)
    if email_verification.enabled():
        return email_verification.start(username, email, hash_password(body.password), SECRET_KEY)
    user = create_user(username, email, hash_password(body.password), role, auth_provider="email")
    if not user:
        return JSONResponse({"error": "Email is already registered. Please log in."}, status_code=409)
    return {"message": "Account created. Please log in.", "email": email, "requires_verification": False}


@app.post("/api/mobile/login")
def mobile_login(body: LoginBody):
    user = get_user_by_email(body.email.strip().lower())
    if not verify_password(body.password, user.get("password_hash") if user else None):
        return JSONResponse({"error": "Invalid email or password."}, status_code=401)
    if user.get("is_active") is False:
        return JSONResponse({"error": "This account is deactivated."}, status_code=403)
    return {"user": user_public_dict(user), "token": generate_mobile_token(user)}




class EmailTicketBody(BaseModel):
    ticket: str = Field(min_length=32, max_length=128)


class EmailCodeBody(EmailTicketBody):
    code: str = Field(pattern=r"^[0-9]{6}$")


@app.post("/api/mobile/verify-email")
@app.post("/api/mobile/verify-code")
def verify_signup_email(body: EmailCodeBody):
    if not email_verification.enabled():
        return JSONResponse({'error': 'Email verification is not enabled.'}, status_code=410)
    return email_verification.verify(body.ticket, body.code, SECRET_KEY)


@app.post("/api/mobile/send-verification")
@app.post("/api/mobile/resend-verification")
def resend_signup_email(body: EmailTicketBody):
    if not email_verification.enabled():
        return JSONResponse({'error': 'Email verification is not enabled.'}, status_code=410)
    return email_verification.resend(body.ticket, SECRET_KEY)


@app.get("/api/mobile/me")
def mobile_me(user=Depends(get_api_user)):
    return {"user": user_public_dict(user)}


class ProviderTokenBody(BaseModel):
    id_token: str = Field(min_length=32, max_length=8192)


class PasswordResetStartBody(BaseModel):
    email: str = Field(max_length=100)

    @field_validator('email')
    @classmethod
    def normalize(cls, value):
        return RegisterBody.valid_email(value.strip())


class PasswordResetCompleteBody(EmailCodeBody):
    new_password: str = Field(min_length=8, max_length=72)

    @field_validator('new_password')
    @classmethod
    def valid_password(cls, value):
        return validate_new_password(value)


@app.post('/api/mobile/password-reset/start', status_code=202)
def password_reset_start(body: PasswordResetStartBody):
    import password_reset
    return password_reset.start(body.email, SECRET_KEY)


@app.post('/api/mobile/password-reset/complete')
def password_reset_complete(body: PasswordResetCompleteBody):
    import password_reset
    return password_reset.complete(body.ticket, body.code, hash_password(body.new_password), SECRET_KEY)


class LinkGoogleBody(ProviderTokenBody):
    current_password: str = Field(max_length=1024)


class PhoneStartBody(BaseModel):
    phone_number: str = Field(min_length=9, max_length=16)

    @field_validator('phone_number')
    @classmethod
    def normalize(cls, value):
        from federated_identity import normalize_phone
        return normalize_phone(value)


class PhoneFinishBody(ProviderTokenBody):
    ticket: str = Field(min_length=32, max_length=128)


@app.post('/api/mobile/auth/google')
def google_signin(body: ProviderTokenBody):
    from federated_identity import google_login
    user = google_login(body.id_token)
    return {'user': user_public_dict(user), 'token': generate_mobile_token(user)}


@app.post('/api/mobile/auth/link-google')
def google_link(body: LinkGoogleBody, user=Depends(get_api_user)):
    from federated_identity import link_google
    return {'user': user_public_dict(link_google(user, body.id_token, body.current_password))}


@app.post('/api/mobile/phone-verification/start')
def phone_start(body: PhoneStartBody, user=Depends(get_api_user)):
    from federated_identity import start_phone
    return start_phone(user, body.phone_number)


@app.post('/api/mobile/phone-verification/complete')
def phone_finish(body: PhoneFinishBody, user=Depends(get_api_user)):
    from federated_identity import finish_phone
    return {'user': user_public_dict(finish_phone(user, body.ticket, body.id_token))}


@app.post('/api/mobile/change-password')
def mobile_change_password(body: ChangePasswordBody, user=Depends(get_api_user)):
    if not verify_password(body.current_password, user.get('password_hash')):
        raise HTTPException(status_code=400, detail='Current password is incorrect.')
    if body.current_password == body.new_password:
        raise HTTPException(status_code=400, detail='Choose a different new password.')
    updated=change_user_password(user['id'],user['password_hash'],hash_password(body.new_password))
    if not updated:
        raise HTTPException(status_code=409, detail='The account changed. Please log in again before retrying.')
    return {'user':user_public_dict(updated),'token':generate_mobile_token(updated),
            'message':'Password changed. Other sessions have been signed out.'}


@app.put("/api/mobile/me")
def mobile_update_me(body: ProfileUpdateBody, user=Depends(get_api_user)):
    # SECURITY: role is deliberately never taken from the request body here.
    # Self-service profile updates can only ever change username/location/photo.
    updated = update_user_profile(
        user["id"],
        username=(body.username.strip() if body.username else None),
        location=body.location,
        profile_photo=body.profile_photo,
        **({'phone_number': body.phone_number} if body.phone_number is not None else {}),
    )
    return {"user": user_public_dict(updated or get_user_by_id(user["id"]))}



@app.post("/api/mobile/profile")
def mobile_update_profile_alias(body: ProfileUpdateBody, user=Depends(get_api_user)):
    # SECURITY: role is deliberately never taken from the request body here.
    updated = update_user_profile(
        user["id"],
        username=body.username,
        location=body.location,
        profile_photo=body.profile_photo,
        **({'phone_number': body.phone_number} if body.phone_number is not None else {}),
    )
    return {"user": user_public_dict(updated or get_user_by_id(user["id"]))}

@app.post("/api/mobile/me/deactivate")
def mobile_deactivate_me(user=Depends(get_api_user)):
    try:
        deactivate_user(user["id"])
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    return {"ok": True, "message": "Account deactivated."}


class WebAccountActionBody(BaseModel):
    action: str = Field(pattern='^(delete|deactivate)$')
    current_password: Optional[str] = Field(None, max_length=128)
    firebase_id_token: Optional[str] = Field(None, max_length=8192)


@app.post('/api/web/account-action')
def web_account_action(body: WebAccountActionBody, user=Depends(get_api_user)):
    qa_closure.enforce_quota(user['id'], 'account_action', 5)
    if body.firebase_id_token:
        import federated_identity
        claims, _ = federated_identity.google_identity(body.firebase_id_token)
        if not user.get('google_sub') or claims['sub'] != user['google_sub']:
            raise HTTPException(403, 'Confirm using the Google account linked to this profile.')
    elif not body.current_password or not verify_password(body.current_password, user.get('password_hash')):
        raise HTTPException(401, 'Confirm your current password before changing account access.')
    return mobile_delete_me(user=user) if body.action == 'delete' else mobile_deactivate_me(user=user)


@app.delete("/api/mobile/me")
def mobile_delete_me(user=Depends(get_api_user)):
    try:
        delete_user(user["id"])
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    return {"ok": True, "message": "Account deleted."}




# ---------------------------------------------------------------------------
# Super Administrator API
# ---------------------------------------------------------------------------
def require_super_admin(user=Depends(get_api_user)):
    role = str(user.get('role') or '').lower()
    if role not in ('admin', 'super_admin'):
        raise HTTPException(status_code=403, detail='Super Administrator access required.')
    return user

@app.get('/api/admin/dashboard')
def api_admin_dashboard(user=Depends(require_super_admin)):
    return {'stats': admin_dashboard_stats()}

@app.get('/api/admin/users')
def api_admin_users(user=Depends(require_super_admin), offset: int = Query(0, ge=0), limit: int = Query(50, ge=1, le=100), q: str = Query("", max_length=160)):
    rows = admin_list_users(limit=limit+1, offset=offset, q=q)
    return {"users": rows[:limit], "has_more": len(rows)>limit}

@app.patch('/api/admin/users/{user_id}')
def api_admin_update_user(user_id: int, body: AdminUserUpdateBody, user=Depends(require_super_admin)):
    if int(user_id) == int(user['id']) and body.is_active is False:
        raise HTTPException(status_code=400, detail='You cannot deactivate your own Super Administrator account.')
    try:
        updated = admin_update_user(user_id, role=body.role, is_active=body.is_active,
                                     actor_user_id=user['id'], actor_role=user.get('role'))
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    if not updated:
        raise HTTPException(status_code=404, detail='User not found.')
    return {'user': updated}

@app.get('/api/admin/analyses')
def api_admin_analyses(user=Depends(require_super_admin), offset: int = Query(0, ge=0), limit: int = Query(50, ge=1, le=100), q: str = Query("", max_length=160)):
    rows = admin_list_analyses(limit=limit+1, offset=offset, q=q)
    return {"analyses": rows[:limit], "has_more": len(rows)>limit}


@app.get('/api/admin/crops')
def api_admin_list_crops(user=Depends(require_super_admin)):
    return {'crops': list_crop_reference()}


class CropReferenceUpdateBody(BaseModel):
    label: Optional[str] = None
    growth_cycle: Optional[str] = None
    est_yield: Optional[str] = None
    suitability_note: Optional[str] = None
    is_active: Optional[bool] = None


@app.patch('/api/admin/crops/{crop_key}')
def api_admin_update_crop(crop_key: str, body: CropReferenceUpdateBody, user=Depends(require_super_admin)):
    updated = update_crop_reference(
        crop_key, label=body.label, growth_cycle=body.growth_cycle, est_yield=body.est_yield,
        suitability_note=body.suitability_note, is_active=body.is_active,
        actor_user_id=user['id'], actor_role=user.get('role'),
    )
    if not updated:
        raise HTTPException(status_code=404, detail='Crop reference not found.')
    return {'crop': updated}


@app.get('/api/admin/audit-logs')
def api_admin_audit_logs(user=Depends(require_super_admin), offset: int = Query(0, ge=0), limit: int = Query(50, ge=1, le=100), q: str = Query("", max_length=160)):
    rows = get_audit_logs(limit=limit+1, offset=offset, q=q)
    return {"logs": rows[:limit], "has_more": len(rows)>limit}


@app.get("/api/mobile/weather")
def mobile_live_weather(request: Request, lat: float = Query(ge=-90, le=90, allow_inf_nan=False), lon: float = Query(ge=-180, le=180, allow_inf_nan=False)):
    qa_closure.enforce_quota(request.client.host if request.client else 'unknown', 'weather', 60)
    qa_closure.enforce_quota('all', 'provider_weather', 300)
    # Public lightweight endpoint for the Home page. Auth is intentionally not
    # required because live weather should load before/after password login and
    # should not break when a local token is missing or expired.
    try:
        return fetch_open_meteo_weather(lat, lon)
    except Exception as e:
        print(f"Open-Meteo fetch failed: {type(e).__name__}: {e}")
        return JSONResponse({"error": "Unable to fetch live Open-Meteo weather right now."}, status_code=502)


@app.get("/api/mobile/history")
def mobile_history(user=Depends(get_api_user), offset: int = Query(0, ge=0), limit: int = Query(50, ge=1, le=100), farm_id: Optional[int] = Query(None, gt=0)):
    if farm_id is not None and not get_farm_parcel(user['id'], farm_id):
        raise HTTPException(status_code=404, detail='Farm not found.')
    rows = get_user_history(user["id"], limit=limit+1, offset=offset, farm_id=farm_id)
    return {"history": [dict(row) for row in rows[:limit]], "has_more": len(rows)>limit}


@app.get('/api/web/history')
def web_history(user=Depends(get_api_user), offset: int = Query(0, ge=0), limit: int = Query(50, ge=1, le=100), q: str = Query('', max_length=160)):
    rows = get_user_history(user['id'], limit=limit+1, offset=offset, q=q)
    return {'history': [dict(row) for row in rows[:limit]], 'has_more':len(rows)>limit}


@app.get('/api/web/summary')
def web_history_summary(user=Depends(get_api_user)):
    from web_summary import summary
    return summary(user['id'])


@app.get('/api/mobile/analyses/{session_id}')
def mobile_analysis_detail(session_id: int, user=Depends(get_api_user)):
    item=get_user_analysis(user['id'],session_id)
    if not item:
        raise HTTPException(status_code=404,detail='Analysis not found.')
    return {'analysis':item}


@app.get("/api/mobile/counts")
def mobile_counts(user=Depends(get_api_user)):
    return get_user_counts(user["id"])


@app.post("/api/mobile/save-analysis")
def mobile_save_analysis(body: SessionActionBody, user=Depends(get_api_user)):
    item = save_analysis_for_user(user["id"], body.session_id)
    if not item:
        raise HTTPException(status_code=404, detail="Analysis not found.")
    return {"saved": item}


@app.post("/api/mobile/submit-to-planner")
def mobile_submit_to_planner(body: SessionActionBody, user=Depends(get_api_user)):
    if user.get('role') != 'farmer':
        raise HTTPException(status_code=403,detail='Only farmers can submit an analysis for review.')
    item = submit_analysis_to_planner(user["id"], body.session_id)
    if not item:
        raise HTTPException(status_code=404, detail="Analysis not found or not eligible for review.")
    return {"submission": item}


@app.get("/api/mobile/saved")
def mobile_saved(user=Depends(get_api_user), offset: int = Query(0, ge=0), limit: int = Query(50, ge=1, le=100), q: str = Query("", max_length=160)):
    rows = get_saved_analyses(user["id"], limit=limit+1, offset=offset, q=q)
    return {"saved": rows[:limit], "has_more": len(rows)>limit}


@app.post("/api/mobile/report")
def mobile_create_report(body: SessionActionBody, user=Depends(get_api_user)):
    item = create_report_for_user(user["id"], body.session_id, body.title)
    if not item:
        raise HTTPException(status_code=404, detail="Analysis not found.")
    return {"report": item}


@app.get("/api/mobile/reports")
def mobile_reports(user=Depends(get_api_user), offset: int = Query(0, ge=0), limit: int = Query(50, ge=1, le=100), q: str = Query("", max_length=160)):
    rows = get_reports(user["id"], limit=limit+1, offset=offset, q=q)
    return {"reports": rows[:limit], "has_more": len(rows)>limit}


@app.get("/api/mobile/reverse-geocode")
def mobile_reverse_geocode(lat: float = Query(ge=-90, le=90, allow_inf_nan=False), lon: float = Query(ge=-180, le=180, allow_inf_nan=False), user=Depends(get_api_user)):
    qa_closure.enforce_quota(user['id'], 'geocode', 60)
    qa_closure.enforce_quota('all', 'provider_geocode', 300)
    return {"place_name": reverse_geocode_place(lat, lon)}



class FarmCreateBody(BaseModel):
    farm_name: str = Field(min_length=2, max_length=160)
    location_name: Optional[str] = Field(default=None,max_length=240)
    polygon: List[Dict[str, float]]
    mapping_method: str = 'manual_draw'
    gps_accuracy_m: Optional[float] = Field(default=None,ge=0,allow_inf_nan=False)

    @field_validator('farm_name',mode='before')
    @classmethod
    def trim_name(cls,value):
        return value.strip() if isinstance(value,str) else value

    @field_validator('mapping_method')
    @classmethod
    def known_method(cls,value):
        if value not in ('manual_draw','gps_walk'):
            raise ValueError('Boundary source must be manual_draw or gps_walk.')
        return value

class FarmUpdateBody(BaseModel):
    expected_boundary_version: int = Field(ge=1)
    farm_name: Optional[str] = Field(default=None,min_length=2,max_length=160)
    location_name: Optional[str] = Field(default=None,max_length=240)
    polygon: Optional[List[Dict[str, float]]] = None
    mapping_method: Optional[str] = None
    gps_accuracy_m: Optional[float] = Field(default=None,ge=0,allow_inf_nan=False)
    is_archived: Optional[bool] = None

    @field_validator('farm_name',mode='before')
    @classmethod
    def trim_name(cls,value):
        return FarmCreateBody.trim_name(value)

    @field_validator('mapping_method')
    @classmethod
    def known_method(cls,value):
        return FarmCreateBody.known_method(value) if value is not None else None


def request_identity(key, payload):
    if key is not None and (not key.strip() or len(key)>128):
        raise HTTPException(status_code=400,detail='Idempotency-Key must be between 1 and 128 characters.')
    digest=hashlib.sha256(json.dumps(payload,sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()
    return key,digest

@app.get('/api/mobile/farms')
def mobile_farms(include_archived: bool=False, user=Depends(get_api_user)):
    return {'farms': [farm_coverage(row) for row in list_farm_parcels(user['id'], include_archived)]}

@app.post('/api/mobile/farms', status_code=201)
def mobile_create_farm(body: FarmCreateBody, user=Depends(get_api_user), idempotency_key: Optional[str]=Header(default=None)):
    if len(body.polygon) < 3:
        raise HTTPException(status_code=400, detail='A farm boundary requires at least three valid GPS/map points.')
    ok, err = validate_farm_polygon(body.polygon)
    if not ok:
        raise HTTPException(status_code=400, detail=err)
    key,digest=request_identity(idempotency_key,body.model_dump())
    try:
        return {'farm': farm_coverage(create_farm_parcel(user['id'], body.farm_name, body.polygon,
                    body.location_name, body.mapping_method, body.gps_accuracy_m,request_key=key,request_hash=digest))}
    except ValueError as exc:
        raise HTTPException(status_code=409,detail=str(exc))

@app.patch('/api/mobile/farms/{farm_id}')
def mobile_update_farm(farm_id: int, body: FarmUpdateBody, user=Depends(get_api_user)):
    if body.polygon is not None:
        if len(body.polygon) < 3:
            raise HTTPException(status_code=400, detail='A farm boundary requires at least three points.')
        ok, err = validate_farm_polygon(body.polygon)
        if not ok:
            raise HTTPException(status_code=400, detail=err)
    try:
        row=update_farm_parcel(user['id'],farm_id,**body.model_dump(exclude_none=True))
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    if not row: raise HTTPException(status_code=404, detail='Farm parcel not found.')
    return {'farm':farm_coverage(row)}

@app.get('/api/mobile/farms/{farm_id}')
def mobile_farm(farm_id: int, user=Depends(get_api_user)):
    row=get_farm_parcel(user['id'],farm_id)
    if not row: raise HTTPException(status_code=404, detail='Farm parcel not found.')
    return {'farm':farm_coverage(row)}


@app.get('/api/mobile/analysis-coverage/catalog')
def mobile_coverage_catalog(user=Depends(get_api_user)):
    return coverage_catalog()


class CoverageBody(BaseModel):
    polygon: List[Dict[str, float]] = Field(default_factory=list)


@app.post('/api/mobile/analysis-coverage')
def mobile_coverage(body: CoverageBody, user=Depends(get_api_user)):
    # Preflight is informational; formal analysis always checks again.
    return farm_coverage({'polygon': body.polygon})


# ---------------------------------------------------------------------------
# Planner verification workflow
# ---------------------------------------------------------------------------
def require_planner(user=Depends(get_api_user)):
    """Allow the combined Analyst / Planner role to review submitted land."""
    role = (user.get("role") or "").lower()
    if role not in ("analyst", "planner", "agricultural_planning_analyst"):
        raise HTTPException(
            status_code=403,
            detail="Agricultural Planning Analyst access required.",
        )
    return user


class VerifySessionBody(BaseModel):
    session_id: int
    status: str  # 'verified' or 'rejected'
    notes: Optional[str] = None


@app.get("/api/planner/queue")
def planner_queue(status: str = "pending", planner=Depends(require_planner), offset: int = Query(0, ge=0), limit: int = Query(50, ge=1, le=100), q: str = Query("", max_length=160)):
    """List analyzed land submissions for the planner to review.

    `status` query param: 'pending' (default), 'verified', 'rejected', or 'all'.
    """
    if status not in ("pending", "verified", "rejected", "all"):
        status = "pending"
    rows = get_planner_queue(status=status, limit=limit+1, offset=offset, q=q)
    return {"queue": rows[:limit], "has_more": len(rows)>limit}


@app.get("/api/planner/counts")
def planner_counts(planner=Depends(require_planner)):
    """Summary counts of pending/verified/rejected submissions for dashboard cards."""
    return get_planner_queue_counts()


@app.get("/api/planner/session/{session_id}")
def planner_session_detail(session_id: int, planner=Depends(require_planner)):
    """Full detail of a single analyzed land submission, including farmer info."""
    session = get_planner_session_detail(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found.")
    return {"session": session}


@app.post("/api/planner/verify")
def planner_verify(body: VerifySessionBody, planner=Depends(require_planner)):
    """Approve or reject a farmer's analyzed land submission."""
    if body.status not in ("verified", "rejected"):
        raise HTTPException(status_code=400, detail="status must be 'verified' or 'rejected'.")
    session = verify_analysis_session(body.session_id, planner["id"], body.status, body.notes)
    if not session:
        raise HTTPException(
            status_code=404,
            detail="Session not found, not a Farmer submission, or not currently pending review.",
        )
    return {"session": session}


@app.get('/api/mobile/analysis-requests/{request_id}')
def mobile_analysis_request(request_id: str, user=Depends(get_api_user)):
    request_identity(request_id, {})
    import analysis_jobs
    queued = analysis_jobs.status(user['id'], request_id) if analysis_jobs.enabled() else None
    if queued:
        return queued
    return analysis_request_status(user['id'], request_id)


@app.post("/api/mobile/analysis")
def mobile_analysis(body: AnalysisBody, user=Depends(get_api_user), idempotency_key: Optional[str]=Header(default=None)):
    key, _ = request_identity(idempotency_key, body.model_dump(exclude_none=True))
    import analysis_jobs
    if analysis_jobs.enabled():
        if not idempotency_key:
            raise HTTPException(400, 'Idempotency-Key is required for queued analysis.')
        payload = body.model_dump(exclude_none=True)
        key, digest = request_identity(idempotency_key, payload)
        try:
            prior = find_analysis_request(user['id'], key, digest)
        except ValueError as exc:
            raise HTTPException(409, str(exc))
        if prior:
            return json_safe(prior)
        analysis_jobs.enqueue(user, key, digest, payload)
        return JSONResponse({'status':'processing','stage':'queued','request_id':key}, status_code=202)
    logger = logging.getLogger('uvicorn.error')
    started = time.monotonic()
    # Logs deliberately omit bearer tokens, coordinates, email and provider secrets.
    logger.info('Analysis started user=%s farm=%s', user['id'], body.farm_id)
    try:
        with analysis_request_lock(user['id'], key) as acquired:
            if not acquired:
                return JSONResponse({'status': 'processing', 'request_id': key}, status_code=202)
            result = _perform_mobile_analysis(body, user, key)
            logger.info('Analysis completed user=%s farm=%s session=%s seconds=%.1f', user['id'], body.farm_id, result.get('session_id'), time.monotonic()-started)
            return json_safe(result)
    except Exception as exc:
        code = exc.status_code if isinstance(exc,HTTPException) else 503
        if code in (400,404,409,422,502,503):
            try:
                from activity_notifications import record_failure
                record_failure(user['id'],key,body.farm_id,code)
            except Exception:
                logger.warning('Could not persist analysis failure activity.')
        if isinstance(exc, HTTPException):
            logger.warning('Analysis rejected user=%s farm=%s status=%s seconds=%.1f', user['id'], body.farm_id, exc.status_code, time.monotonic()-started)
        else:
            logger.exception('Analysis failed user=%s farm=%s type=%s seconds=%.1f', user['id'], body.farm_id, type(exc).__name__, time.monotonic()-started)
        raise


def _perform_mobile_analysis(body, user, idempotency_key, charge_quota=True):
    payload=body.model_dump(exclude_none=True)
    key,digest=request_identity(idempotency_key,payload)
    try:
        prior=find_analysis_request(user['id'],key,digest)
        if prior:
            return prior
    except ValueError as exc:
        raise HTTPException(status_code=409,detail=str(exc))
    if charge_quota:
        qa_closure.enforce_quota(user['id'], 'analysis', 10)
        qa_closure.enforce_quota('all', 'provider_analysis', 60)
    farm=None
    if body.farm_id:
        farm=get_farm_parcel(user['id'],body.farm_id)
        if not farm or farm.get('is_archived'):
            raise HTTPException(status_code=404,detail='Farm parcel not found or archived.')
        # Use the server-owned version, never a client-supplied replacement ring.
        payload['polygon']=farm['polygon']
        payload['place_name']=farm.get('location_name') or body.place_name
    try:
        logging.getLogger('uvicorn.error').info('Analysis inference user=%s farm=%s', user['id'], body.farm_id)
        result, analysis_source = build_analysis_result(body=payload)
    except CoverageUnavailable as exc:
        raise HTTPException(status_code=422, detail={'code': 'cagro_coverage_unsupported',
                            'message': str(exc), 'analysis_coverage': exc.coverage}) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400,detail=str(exc))
    except ModelRankingUnavailable as exc:
        logging.getLogger('uvicorn.error').exception('Model ranking unavailable user=%s farm=%s', user['id'], body.farm_id)
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except RuntimeError as exc:
        logging.getLogger('uvicorn.error').exception('Analysis engine unavailable user=%s farm=%s type=%s', user['id'], body.farm_id, type(exc).__name__)
        raise HTTPException(status_code=503,detail='Environmental datasets are unavailable. The project team should check Earth Engine access and server configuration.')
    except Exception as exc:
        logging.getLogger('uvicorn.error').exception('Analysis inference failed user=%s farm=%s type=%s', user['id'], body.farm_id, type(exc).__name__)
        raise HTTPException(status_code=502,detail='An analysis data service failed. Please retry.')
    if farm:
        result.update(farm_id=farm['id'], farm_name=farm['farm_name'], boundary_version=farm['boundary_version'])
    else:
        result['farm_name']=None
    try:
        logging.getLogger('uvicorn.error').info('Analysis saving user=%s farm=%s', user['id'], body.farm_id)
        session_id=save_analysis_session(user['id'],result,analysis_source,request_key=key,request_hash=digest)
    except ValueError as exc:
        raise HTTPException(status_code=409,detail=str(exc))
    # A database failure is a failed request, never a false successful result.
    saved = get_user_analysis(user['id'],session_id)
    if saved is None:
        raise RuntimeError('Saved analysis could not be read back')
    response = json_safe(saved)
    # Strict encoding catches unsupported values before sending a response.
    json.dumps(response, allow_nan=False)
    logging.getLogger('uvicorn.error').info('Analysis response serialized user=%s farm=%s session=%s', user['id'], body.farm_id, session_id)
    return response


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("fastapi_app:app", host="0.0.0.0", port=8000, reload=False)


@app.post('/api/mobile/logout')
def mobile_logout(request: Request, user=Depends(get_api_user)):
    payload = token_serializer.loads(request.headers['authorization'].split(' ', 1)[1].strip(),
        salt='geosustain-mobile', max_age=MOBILE_TOKEN_MAX_AGE)
    defense_db.revoke_session(payload['sid'], MOBILE_TOKEN_MAX_AGE)
    return {'signed_out': True}


@app.get('/api/mobile/notifications')
def notifications(user=Depends(get_api_user), offset: int = Query(0, ge=0), limit: int = Query(50, ge=1, le=100)):
    return qa_closure.inbox(user['id'], offset, limit)


@app.get('/api/mobile/activity')
def activity_inbox(user=Depends(get_api_user), offset: int=Query(0,ge=0), limit: int=Query(50,ge=1,le=100),
                   unread_only: bool=False, event_type: Optional[str]=Query(None,pattern='^(analysis_ready|analysis_partial|analysis_failed|submitted|review|submission_received)$')):
    import activity_notifications as activity
    return activity.inbox(user['id'],offset,limit,unread_only,event_type)


@app.post('/api/mobile/activity/read-all')
def activity_read_all(user=Depends(get_api_user)):
    import activity_notifications as activity
    return activity.mark_all(user['id'])


@app.post('/api/mobile/activity/{event_id}/read')
def activity_read(event_id: int, user=Depends(get_api_user)):
    import activity_notifications as activity
    item=activity.mark_read(user['id'],event_id)
    if not item: raise HTTPException(404,'Activity is no longer available.')
    return item


@app.post('/api/mobile/notifications/{notification_id}/read')
def read_notification(notification_id: int, user=Depends(get_api_user)):
    row = qa_closure.read_notification(user['id'], notification_id)
    if not row:
        raise HTTPException(404, 'Notification is no longer available.')
    return row


@app.post('/api/mobile/reviews/{session_id}/read')
def read_review(session_id: int, user=Depends(get_api_user)):
    row = qa_closure.read_notification(user['id'], session_id, by_session=True)
    if not row:
        raise HTTPException(404, 'Review notification is no longer available.')
    return row


@app.get('/api/admin/messages')
def notification_log(user=Depends(require_super_admin), offset: int = Query(0, ge=0), limit: int = Query(50, ge=1, le=100)):
    return qa_closure.message_log(offset, limit)


class PushSubscriptionBody(BaseModel):
    token: str = Field(min_length=20, max_length=4096)
    platform: str = Field(pattern='^(android|web)$')
    enabled: bool


@app.put('/api/mobile/push-subscription')
def push_subscription(request: Request, body: PushSubscriptionBody, user=Depends(get_api_user)):
    from push_delivery import configured, register
    if body.enabled and not configured():
        raise HTTPException(status_code=503, detail='Push provider is not configured. Ask the project administrator to complete Firebase setup.')
    payload = token_serializer.loads(request.headers['authorization'].split(' ', 1)[1].strip(),
        salt='geosustain-mobile', max_age=MOBILE_TOKEN_MAX_AGE)
    register(user['id'], payload['sid'], user.get('password_version',0), body.token, body.platform, body.enabled)
    return {'enabled':body.enabled}


class RecoveryIssueBody(BaseModel):
    identity_verified: bool


class RecoveryRedeemBody(BaseModel):
    recovery_token: str = Field(min_length=32, max_length=128)
    new_password: str = Field(min_length=8, max_length=72)

    @field_validator('new_password')
    @classmethod
    def password_size(cls, value):
        return validate_new_password(value)


@app.post('/api/admin/users/{user_id}/recovery')
def admin_recovery(user_id: int, body: RecoveryIssueBody, user=Depends(require_super_admin)):
    if not body.identity_verified:
        raise HTTPException(status_code=400, detail='Verify the account owner before issuing a recovery handoff.')
    token = defense_db.issue_password_recovery(user_id, user['id'])
    if token is None:
        raise HTTPException(status_code=404, detail='Active account not found.')
    return JSONResponse({'recovery_token': token, 'expires_in_seconds': 900},
                        headers={'Cache-Control': 'no-store'})


@app.post('/api/mobile/recover-password')
def recover_password(body: RecoveryRedeemBody):
    if not defense_db.redeem_password_recovery(body.recovery_token, hash_password(body.new_password)):
        raise HTTPException(status_code=400, detail='Recovery handoff is invalid, expired or already used.')
    return {'message': 'Password changed. Sign in using your new password.'}


@app.get('/ready')
def readiness():
    checks = {'database': 'unavailable', 'model': 'unavailable'}
    try:
        conn = defense_db.psycopg2.connect(defense_db.DATABASE_URL,
            connect_timeout=3, options='-c statement_timeout=2000')
        try:
            with conn.cursor() as cur:
                cur.execute('''SELECT u.password_version,u.phone_verified_at,u.google_sub, a.actor_reference, f.boundary_version
                    FROM users u LEFT JOIN audit_logs a ON FALSE LEFT JOIN farm_parcels f ON FALSE
                    LEFT JOIN revoked_sessions r ON FALSE LEFT JOIN password_recovery p ON FALSE
                    LEFT JOIN push_subscriptions s ON FALSE
                    LEFT JOIN review_notifications n ON FALSE
                    LEFT JOIN request_quotas q ON FALSE
                    LEFT JOIN analysis_jobs j ON FALSE
                    LEFT JOIN session_activity t ON FALSE
                    LEFT JOIN password_reset_challenges pr ON FALSE
                    LEFT JOIN phone_verification_challenges pc ON FALSE
                    LEFT JOIN activity_push_deliveries ap ON FALSE LIMIT 1''')
            checks['database'] = 'ready'
        finally:
            conn.close()
    except Exception:
        pass
    if analyze_location is not None and ANALYSIS_IMPORT_ERROR is None:
        from rainfallDatasets import model_health
        try:
            if model_health().get('status') == 'loaded':
                checks['model'] = 'ready'
        except Exception:
            pass
    if os.getenv('PUSH_REQUIRED', '').lower() == 'true':
        from push_delivery import configured
        checks['push_configuration'] = 'ready' if configured() else 'unavailable'
    if email_verification.enabled():
        from mail_delivery import configured as mail_configured
        checks['email_configuration'] = 'ready' if mail_configured() else 'unavailable'
    if os.getenv('IDENTITY_REQUIRED', '').lower() == 'true':
        from federated_identity import project_id
        checks['identity_configuration'] = 'ready' if project_id() else 'unavailable'
    ready = all(value == 'ready' for value in checks.values())
    return JSONResponse({'status': 'ready' if ready else 'not_ready', 'checks': checks},
        status_code=200 if ready else 503, headers={'Cache-Control': 'no-store'})
