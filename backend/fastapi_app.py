import os
import json
import secrets
import urllib.parse
import urllib.request
from datetime import datetime, timezone, timedelta
from functools import wraps
from typing import Any, Dict, List, Optional, Tuple

import bcrypt
import requests
from fastapi import FastAPI, Request, Depends, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from itsdangerous import BadSignature, SignatureExpired, URLSafeTimedSerializer
from pydantic import BaseModel, Field
from starlette.middleware.sessions import SessionMiddleware

from database import (
    init_db,
    create_user,
    set_email_verification_code,
    mark_email_verified,
    get_user_by_google_sub,
    link_google_to_user,
    get_user_by_email,
    get_user_by_id,
    get_user_by_username,
    save_analysis_session,
    get_user_history,
    save_analysis_for_user,
    create_report_for_user,
    get_saved_analyses,
    get_reports,
    get_user_counts,
    update_user_profile,
    deactivate_user,
    delete_user,
    upsert_pending_registration,
    get_pending_registration,
    delete_pending_registration,
)

try:
    from rainfallDatasets import analyze_location
    ANALYSIS_IMPORT_ERROR = None
except Exception as exc:
    analyze_location = None
    ANALYSIS_IMPORT_ERROR = exc
    print(f'GeoSustain analysis engine failed to load: {exc}')


BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SECRET_KEY = os.getenv("SECRET_KEY", "geosustain-secret-change-in-production")
MOBILE_TOKEN_MAX_AGE = 60 * 60 * 24 * 30  # 30 days
VERIFICATION_CODE_MAX_AGE_MINUTES = int(os.getenv("VERIFICATION_CODE_MAX_AGE_MINUTES", "10"))
GOOGLE_CLIENT_ID = os.getenv("GOOGLE_CLIENT_ID", "").strip()
GOOGLE_CLIENT_SECRET = os.getenv("GOOGLE_CLIENT_SECRET", "").strip()
GOOGLE_REDIRECT_URI = os.getenv("GOOGLE_REDIRECT_URI", "").strip()
FIREBASE_WEB_CLIENT_ID = os.getenv("FIREBASE_WEB_CLIENT_ID", "").strip()

app = FastAPI(title="GeoSustain API", version="2.0.0")
app.add_middleware(SessionMiddleware, secret_key=SECRET_KEY)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # change this in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

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
    """Fetch live/current weather from Open-Meteo without an API key."""
    params = {
        "latitude": lat,
        "longitude": lon,
        "current": "temperature_2m,relative_humidity_2m,precipitation,rain,weather_code,cloud_cover,wind_speed_10m",
        "hourly": "temperature_2m,relative_humidity_2m,precipitation,precipitation_probability,cloud_cover,wind_speed_10m",
        "daily": "precipitation_sum",
        "past_days": 31,
        "forecast_days": 1,
        "timezone": "auto",
    }
    url = "https://api.open-meteo.com/v1/forecast?" + urllib.parse.urlencode(params)
    # Use requests instead of urllib here because it behaves more reliably on
    # Render free instances after cold starts. Keep a clear timeout so Home
    # weather fails fast instead of hanging the whole app.
    resp = requests.get(url, headers={"User-Agent": "GeoSustainCapstone/1.0"}, timeout=12)
    resp.raise_for_status()
    payload = resp.json()

    current = payload.get("current", {}) or {}
    hourly = payload.get("hourly", {}) or {}
    daily = payload.get("daily", {}) or {}
    code = int(current.get("weather_code") or 0)
    precip_now = current.get("precipitation") or current.get("rain") or 0
    daily_precip = daily.get("precipitation_sum") or []
    daily_times = daily.get("time") or []
    today_rainfall = 0.0
    if isinstance(daily_precip, list) and daily_precip:
        # Home page uses the real daily rainfall total, not the current instant rain rate.
        try:
            current_day = str((current.get("time") or "")[:10])
            if current_day and isinstance(daily_times, list) and current_day in daily_times:
                today_rainfall = float(daily_precip[daily_times.index(current_day)] or 0)
            else:
                today_rainfall = float(daily_precip[-1] or 0)
        except Exception:
            today_rainfall = 0.0
    monthly_rainfall = 0.0
    if isinstance(daily_precip, list):
        monthly_rainfall = round(sum(float(x or 0) for x in daily_precip[-31:]), 2)
    # Do not multiply the current rain rate as a monthly fallback.
    # Keep 0.0 when the live daily series genuinely reports no rain.
    hourly_precip = hourly.get("precipitation") or []
    hourly_prob = hourly.get("precipitation_probability") or []
    next_6h_rain = sum(float(x or 0) for x in hourly_precip[:6]) if isinstance(hourly_precip, list) else 0
    max_rain_prob = max([float(x or 0) for x in hourly_prob[:6]], default=0) if isinstance(hourly_prob, list) else 0

    rainfall_status = "Low"
    if next_6h_rain >= 20 or max_rain_prob >= 80:
        rainfall_status = "High"
    elif next_6h_rain >= 5 or max_rain_prob >= 50:
        rainfall_status = "Moderate"

    return {
        "latitude": lat,
        "longitude": lon,
        "temperature_c": current.get("temperature_2m"),
        "live_humidity": current.get("relative_humidity_2m"),
        "rainfall_mm": monthly_rainfall,
        "rainfall_monthly_mm": monthly_rainfall,
        "rainfall_today_mm": round(today_rainfall, 2),
        "today_rainfall_mm": round(today_rainfall, 2),
        "current_precipitation_mm": precip_now,
        "rain_next_6h_mm": round(next_6h_rain, 2),
        "rain_probability_next_6h": round(max_rain_prob, 1),
        "rainfall_status": rainfall_status,
        "wind_speed_ms": current.get("wind_speed_10m"),
        "cloud_cover_pct": current.get("cloud_cover"),
        "weather_code": code,
        "weather_description": WEATHER_CODE_TEXT.get(code, "Weather data available"),
        "weather_updated_at": current.get("time") or datetime.now(timezone.utc).isoformat(),
        "weather_source": "Open-Meteo",
        "weather_is_realtime": True,
    }



@app.get("/health")
def health():
    return {"status": "ok", "service": "GeoSustain API"}

@app.get("/api/health")
def api_health():
    return {"status": "ok", "service": "GeoSustain API"}


@app.on_event("startup")
def startup() -> None:
    init_db()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def flash(request: Request, message: str, category: str = "info") -> None:
    request.session.setdefault("_flash", []).append((category, message))


def render_template(request: Request, template: str, context: Optional[Dict[str, Any]] = None):
    ctx = {"request": request, "google_oauth_enabled": google_oauth_enabled()}
    if context:
        ctx.update(context)
    # Make Flask-style flash work for the current request.
    templates.env.globals["get_flashed_messages"] = lambda with_categories=False: _get_flashed_messages(
        request, with_categories
    )
    return templates.TemplateResponse(template, ctx)


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return bcrypt.checkpw(password.encode("utf-8"), password_hash.encode("utf-8"))
    except Exception:
        return False


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def generate_verification_code() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


def send_verification_email(email: str, code: str) -> bool:
    """Legacy placeholder kept for older web routes. Mobile now uses Firebase email links."""
    print(f"[LEGACY EMAIL CODE DISABLED] Firebase handles email verification for {email}.")
    return False

def issue_and_send_verification_code(email: str) -> bool:
    code = generate_verification_code()
    code_hash = hash_password(code)
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=VERIFICATION_CODE_MAX_AGE_MINUTES)
    set_email_verification_code(email, code_hash, expires_at)
    return send_verification_email(email, code)


def make_verification_code_payload():
    code = generate_verification_code()
    code_hash = hash_password(code)
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=VERIFICATION_CODE_MAX_AGE_MINUTES)
    return code, code_hash, expires_at


def sign_in_user(request: Request, user) -> None:
    request.session["user_id"] = user["id"]
    request.session["username"] = user["username"]
    request.session["role"] = user["role"]


def google_oauth_enabled() -> bool:
    return bool(GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET)


def google_redirect_uri(request: Request) -> str:
    if GOOGLE_REDIRECT_URI:
        return GOOGLE_REDIRECT_URI
    return str(request.url_for("google_callback"))


def current_user(request: Request):
    uid = request.session.get("user_id")
    return get_user_by_id(uid) if uid else None


def require_web_user(request: Request):
    user = current_user(request)
    if not user:
        raise HTTPException(status_code=status.HTTP_307_TEMPORARY_REDIRECT, headers={"Location": "/login"})
    return user


def generate_mobile_token(user) -> str:
    return token_serializer.dumps(
        {"id": user["id"], "username": user["username"], "role": user["role"]},
        salt="geosustain-mobile",
    )


def user_public_dict(user) -> Dict[str, Any]:
    return {
        "id": user["id"],
        "username": user["username"],
        "email": user["email"],
        "role": user["role"],
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
    if not user:
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
    if not latlngs or len(latlngs) < 3:
        return None, None
    lat_total = sum(float(p["lat"]) for p in latlngs)
    lon_total = sum(float(p["lng"]) for p in latlngs)
    count = len(latlngs)
    return lat_total / count, lon_total / count


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
    if center[0] is not None and center[1] is not None:
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

    crop_scores: Dict[str, List[float]] = {}
    for result in results:
        crop = result.get("predicted_crop") or result.get("crop")
        if crop:
            score = result.get("crop_compatibility_pct") or result.get("suitability_pct") or 0
            try:
                crop_scores.setdefault(str(crop), []).append(float(score))
            except Exception:
                crop_scores.setdefault(str(crop), []).append(0.0)
    if crop_scores:
        best_crop = max(crop_scores.items(), key=lambda item: (len(item[1]), sum(item[1]) / max(len(item[1]), 1)))[0]
        merged["predicted_crop"] = best_crop
        merged["crop"] = best_crop
        merged["crop_compatibility_pct"] = sum(crop_scores[best_crop]) / max(len(crop_scores[best_crop]), 1)
    return merged


def build_analysis_result(body: Optional[Dict[str, Any]] = None, query_args: Optional[Dict[str, Any]] = None):
    analysis_source = None
    polygon = []

    if body is not None:
        polygon = body.get("polygon", []) or []
        lat = body.get("lat")
        lon = body.get("lon")

        if polygon and len(polygon) >= 3:
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

    if polygon and len(polygon) >= 3:
        sample_points = polygon_area_sample_points(polygon, max_points=7)
        sample_results = [analyze_location(sample_lat, sample_lon) for sample_lat, sample_lon in sample_points]
        result = merge_area_results(sample_results)
        result["polygon_area_sample_count"] = len(sample_points)
        result["polygon_area_samples"] = [{"lat": p[0], "lng": p[1]} for p in sample_points]
    else:
        result = analyze_location(lat, lon)

    result["selected_polygon"] = polygon
    result["analysis_source"] = analysis_source
    result["selection_type"] = "Polygon boundary area" if polygon and len(polygon) >= 3 else "Point location"
    result["center_lat"] = float(lat)
    result["center_lon"] = float(lon)
    if body is not None and body.get("place_name"):
        result["place_name"] = str(body["place_name"]).strip()
    else:
        result["place_name"] = reverse_geocode_place(float(lat), float(lon))
    return result, analysis_source


# ---------------------------------------------------------------------------
# Pydantic models for mobile/API JSON
# ---------------------------------------------------------------------------
class RegisterBody(BaseModel):
    username: str = Field(min_length=3)
    email: str
    password: str = Field(min_length=6)
    role: str = "farmer"


class LoginBody(BaseModel):
    email: str
    password: str = ""


class EmailOnlyBody(BaseModel):
    email: str


class GoogleLoginBody(BaseModel):
    id_token: str
    role: Optional[str] = 'farmer'


class AnalysisBody(BaseModel):
    lat: Optional[float] = None
    lon: Optional[float] = None
    polygon: Optional[List[Dict[str, float]]] = None
    place_name: Optional[str] = None


class SessionActionBody(BaseModel):
    session_id: int
    title: Optional[str] = None


class ProfileUpdateBody(BaseModel):
    username: Optional[str] = None
    role: Optional[str] = None
    location: Optional[str] = None
    profile_photo: Optional[str] = None


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
    if not user or not verify_password(password, user["password_hash"]):
        flash(request, "Invalid email or password.", "error")
        return render_template(request, "login.html")

    if not user.get("email_verified"):
        try:
            issue_and_send_verification_code(email)
        except Exception as exc:
            print(f"Failed to send verification code: {exc}")
        flash(request, "Please verify your email before signing in. We sent you a new code.", "warning")
        return RedirectResponse(f"/verify-email?email={urllib.parse.quote(email)}", status_code=302)

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
    if not password or len(password) < 6:
        errors.append("Password must be at least 6 characters.")
    if password != confirm:
        errors.append("Passwords do not match.")
    if role not in ("farmer", "analyst"):
        role = "farmer"
    if get_user_by_email(email):
        errors.append("Email is already registered.")

    if errors:
        for error in errors:
            flash(request, error, "error")
        return render_template(request, "register.html", {"username": username, "email": email, "role": role})

    user = create_user(username, email, hash_password(password), role, email_verified=False, auth_provider="email")
    if not user:
        flash(request, "Registration failed. Please try again.", "error")
        return render_template(request, "register.html")

    try:
        sent = issue_and_send_verification_code(email)
        if sent:
            flash(request, "Account created! We sent a verification code to your email.", "success")
        else:
            flash(request, "Account created! Firebase email verification is enabled, so check the server console for the test code.", "warning")
    except Exception as exc:
        print(f"Failed to send verification email: {exc}")
        flash(request, "Account created, but email verification should be handled through Firebase in the mobile app.", "warning")
    return RedirectResponse(f"/verify-email?email={urllib.parse.quote(email)}", status_code=302)



@app.get("/verify-email", response_class=HTMLResponse, name="verify_email")
def verify_email_page(request: Request, email: str = ""):
    return render_template(request, "verify_email.html", {"email": email})


@app.post("/verify-email", name="verify_email")
async def verify_email_submit(request: Request):
    form = await request.form()
    email = str(form.get("email", "")).strip().lower()
    code = str(form.get("code", "")).strip().replace(" ", "")

    user = get_user_by_email(email)
    if not user:
        flash(request, "We could not find that account.", "error")
        return render_template(request, "verify_email.html", {"email": email})
    if user.get("email_verified"):
        sign_in_user(request, user)
        return RedirectResponse("/dashboard", status_code=302)
    if not code or len(code) != 6 or not code.isdigit():
        flash(request, "Open the Firebase verification link sent to your email.", "error")
        return render_template(request, "verify_email.html", {"email": email})

    expires_at = user.get("verification_expires_at")
    if not user.get("verification_code_hash") or not expires_at:
        flash(request, "Your verification code is missing. Please request a new code.", "error")
        return render_template(request, "verify_email.html", {"email": email})
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    if expires_at < datetime.now(timezone.utc):
        flash(request, "Your verification code expired. Please request a new one.", "error")
        return render_template(request, "verify_email.html", {"email": email})
    if not verify_password(code, user["verification_code_hash"]):
        flash(request, "Incorrect verification code.", "error")
        return render_template(request, "verify_email.html", {"email": email})

    verified_user = mark_email_verified(email)
    sign_in_user(request, verified_user)
    flash(request, "Email verified successfully. Welcome to GeoSustain!", "success")
    return RedirectResponse("/dashboard", status_code=302)


@app.post("/resend-verification", name="resend_verification")
async def resend_verification(request: Request):
    form = await request.form()
    email = str(form.get("email", "")).strip().lower()
    user = get_user_by_email(email)
    if not user:
        flash(request, "We could not find that account.", "error")
        return render_template(request, "verify_email.html", {"email": email})
    if user.get("email_verified"):
        flash(request, "This email is already verified. You can sign in now.", "success")
        return RedirectResponse("/login", status_code=302)
    try:
        sent = issue_and_send_verification_code(email)
        flash(request, "We sent a new verification code." if sent else "New test code printed in the server console because Firebase email verification is enabled.", "success" if sent else "warning")
    except Exception as exc:
        print(f"Failed to resend verification email: {exc}")
        flash(request, "Firebase email verification is handled by the mobile app.", "error")
    return render_template(request, "verify_email.html", {"email": email})


@app.get("/auth/google", name="google_login")
def google_login(request: Request):
    if not google_oauth_enabled():
        flash(request, "Google sign-in is not configured yet. Add GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET in Render.", "warning")
        return RedirectResponse("/login", status_code=302)
    state = secrets.token_urlsafe(24)
    request.session["google_oauth_state"] = state
    params = {
        "client_id": GOOGLE_CLIENT_ID,
        "redirect_uri": google_redirect_uri(request),
        "response_type": "code",
        "scope": "openid email profile",
        "state": state,
        "prompt": "select_account",
    }
    return RedirectResponse("https://accounts.google.com/o/oauth2/v2/auth?" + urllib.parse.urlencode(params), status_code=302)


@app.get("/auth/google/callback", name="google_callback")
def google_callback(request: Request, code: str = "", state: str = "", error: str = ""):
    if error:
        flash(request, "Google sign-in was cancelled or failed.", "error")
        return RedirectResponse("/login", status_code=302)
    if not state or state != request.session.get("google_oauth_state"):
        flash(request, "Google sign-in session expired. Please try again.", "error")
        return RedirectResponse("/login", status_code=302)
    if not code:
        flash(request, "Google did not return an authorization code.", "error")
        return RedirectResponse("/login", status_code=302)

    data = urllib.parse.urlencode({
        "code": code,
        "client_id": GOOGLE_CLIENT_ID,
        "client_secret": GOOGLE_CLIENT_SECRET,
        "redirect_uri": google_redirect_uri(request),
        "grant_type": "authorization_code",
    }).encode("utf-8")
    try:
        req = urllib.request.Request("https://oauth2.googleapis.com/token", data=data, method="POST")
        req.add_header("Content-Type", "application/x-www-form-urlencoded")
        with urllib.request.urlopen(req, timeout=15) as resp:
            token_payload = json.loads(resp.read().decode("utf-8"))
        id_token = token_payload.get("id_token")
        info_req = urllib.request.Request("https://oauth2.googleapis.com/tokeninfo?id_token=" + urllib.parse.quote(id_token or ""))
        with urllib.request.urlopen(info_req, timeout=15) as resp:
            profile = json.loads(resp.read().decode("utf-8"))
    except Exception as exc:
        print(f"Google OAuth error: {exc}")
        flash(request, "Google sign-in failed. Please try again.", "error")
        return RedirectResponse("/login", status_code=302)

    if profile.get("aud") != GOOGLE_CLIENT_ID:
        flash(request, "Google sign-in failed because the client ID did not match.", "error")
        return RedirectResponse("/login", status_code=302)

    email = str(profile.get("email", "")).strip().lower()
    google_sub = str(profile.get("sub", "")).strip()
    name = str(profile.get("name") or email.split("@")[0]).strip()
    if not email or not google_sub:
        flash(request, "Google account did not provide an email address.", "error")
        return RedirectResponse("/login", status_code=302)

    user = get_user_by_google_sub(google_sub)
    if not user:
        existing = get_user_by_email(email)
        if existing:
            user = link_google_to_user(existing["id"], google_sub)
        else:
            base_username = ''.join(ch for ch in name.lower().replace(' ', '_') if ch.isalnum() or ch == '_')[:32] or email.split('@')[0]
            username = base_username
            suffix = 1
            while get_user_by_username(username):
                suffix += 1
                username = f"{base_username[:28]}_{suffix}"
            requested_role = (body.role or 'farmer').strip().lower()
            if requested_role not in ('farmer', 'analyst', 'planner'):
                requested_role = 'farmer'
            user = create_user(username, email, hash_password(secrets.token_urlsafe(32)), requested_role, email_verified=True, auth_provider="google", google_sub=google_sub)
    if not user:
        flash(request, "Could not create or link your Google account.", "error")
        return RedirectResponse("/login", status_code=302)

    request.session.pop("google_oauth_state", None)
    sign_in_user(request, user)
    return RedirectResponse("/dashboard", status_code=302)


@app.get("/logout", name="logout")
def logout(request: Request):
    request.session.clear()
    return RedirectResponse("/login", status_code=302)


@app.get("/dashboard", response_class=HTMLResponse, name="dashboard")
def dashboard(request: Request):
    user = current_user(request)
    if not user:
        return RedirectResponse("/login", status_code=302)
    return render_template(request, "index.html", {"user": user})


@app.get("/history", response_class=HTMLResponse, name="history")
def history(request: Request):
    user = current_user(request)
    if not user:
        return RedirectResponse("/login", status_code=302)
    rows = get_user_history(user["id"], limit=20)
    return render_template(request, "history.html", {"user": user, "history": rows})


# ---------------------------------------------------------------------------
# Web JSON API
# ---------------------------------------------------------------------------
@app.api_route("/api/analysis", methods=["GET", "POST"])
async def analysis(request: Request):
    user = current_user(request)
    if not user:
        return JSONResponse({"error": "Please log in to continue."}, status_code=401)

    try:
        body = await request.json() if request.method == "POST" else None
    except Exception:
        body = {}

    try:
        result, analysis_source = build_analysis_result(
            body=body if request.method == "POST" else None,
            query_args=dict(request.query_params),
        )
    except ValueError as e:
        return JSONResponse({"error": str(e)}, status_code=400)

    try:
        session_id = save_analysis_session(user["id"], result, analysis_source)
        result["session_id"] = session_id
    except Exception as e:
        print(f"DB save failed: {e}")
        result["session_id"] = None

    return result


# ---------------------------------------------------------------------------
# Mobile JSON API
# ---------------------------------------------------------------------------
@app.post("/api/mobile/register", status_code=201)
def mobile_register(body: RegisterBody):
    return JSONResponse({
        "error": "This app now uses Firebase email verification links. Please register through Firebase in the mobile app.",
        "firebase_email_verification": True,
    }, status_code=400)


@app.post("/api/mobile/firebase-email-register", status_code=201)
def mobile_firebase_email_register(body: RegisterBody):
    role = body.role if body.role in ("farmer", "analyst") else "farmer"
    username = body.username.strip()
    email = body.email.lower().strip()

    existing = get_user_by_email(email)
    if existing:
        if not existing.get("email_verified"):
            verified_user = mark_email_verified(email) or existing
            return {"user": user_public_dict(verified_user), "token": generate_mobile_token(verified_user), "message": "Email verified."}
        return {"user": user_public_dict(existing), "token": generate_mobile_token(existing), "message": "Account already exists."}

    user = create_user(
        username,
        email,
        hash_password(body.password),
        role,
        email_verified=True,
        auth_provider="firebase_email",
    )
    if not user:
        return JSONResponse({"error": "Could not create verified account."}, status_code=500)
    return {"user": user_public_dict(user), "token": generate_mobile_token(user), "message": "Firebase email verified and account created."}


@app.post("/api/mobile/login")
def mobile_login(body: LoginBody):
    user = get_user_by_email(body.email.lower())
    if not user or not verify_password(body.password, user["password_hash"]):
        return JSONResponse({"error": "Invalid email or password."}, status_code=401)
    if user.get("is_active") is False:
        return JSONResponse({"error": "This account is deactivated."}, status_code=403)
    if not user.get("email_verified"):
        # Legacy PostgreSQL-only accounts are allowed to log in so users do not lose old accounts
        # after switching new registrations to Firebase email verification.
        provider = (user.get("auth_provider") or "email").lower()
        if provider in ("firebase_email", "firebase", "google"):
            return JSONResponse({"error": "Please verify your email through the Firebase verification link first.", "requires_verification": True}, status_code=403)
        try:
            user = mark_email_verified(body.email.lower()) or user
        except Exception:
            pass
    return {"user": user_public_dict(user), "token": generate_mobile_token(user), "legacy_postgres_login": True}




class VerifyEmailBody(BaseModel):
    email: str
    code: str


@app.post("/api/mobile/verify-email")
def mobile_verify_email(body: VerifyEmailBody):
    email = body.email.lower().strip()
    code = body.code.strip().replace(" ", "")

    pending = get_pending_registration(email)
    if pending:
        expires_at = pending.get("verification_expires_at")
        if expires_at and expires_at.tzinfo is None:
            expires_at = expires_at.replace(tzinfo=timezone.utc)
        if not pending.get("verification_code_hash") or not expires_at or expires_at < datetime.now(timezone.utc):
            return JSONResponse({"error": "Verification code expired. Please request a new one."}, status_code=400)
        if not verify_password(code, pending["verification_code_hash"]):
            return JSONResponse({"error": "Incorrect verification code."}, status_code=400)

        if get_user_by_email(email):
            delete_pending_registration(email)
            return JSONResponse({"error": "Email is already registered."}, status_code=400)
        user = create_user(
            pending["username"],
            email,
            pending["password_hash"],
            pending.get("role") or "farmer",
            email_verified=True,
            auth_provider="email",
        )
        if not user:
            return JSONResponse({"error": "Could not create account after verification."}, status_code=500)
        delete_pending_registration(email)
        return {"user": user_public_dict(user), "token": generate_mobile_token(user), "message": "Account verified and created."}

    user = get_user_by_email(email)
    if not user:
        return JSONResponse({"error": "No pending registration found. Please create an account first."}, status_code=404)
    if user.get("email_verified"):
        return {"user": user_public_dict(user), "token": generate_mobile_token(user)}
    expires_at = user.get("verification_expires_at")
    if expires_at and expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    if not user.get("verification_code_hash") or not expires_at or expires_at < datetime.now(timezone.utc):
        return JSONResponse({"error": "Verification code expired. Please request a new one."}, status_code=400)
    if not verify_password(code, user["verification_code_hash"]):
        return JSONResponse({"error": "Incorrect verification code."}, status_code=400)
    verified_user = mark_email_verified(email)
    return {"user": user_public_dict(verified_user), "token": generate_mobile_token(verified_user)}


def _send_mobile_verification_response(email: str):
    return JSONResponse({
        "error": "GeoSustain now uses Firebase email verification links instead of backend email codes.",
        "firebase_email_verification": True,
    }, status_code=410)


@app.post("/api/mobile/send-verification")
def mobile_send_verification(body: EmailOnlyBody):
    return _send_mobile_verification_response(body.email)


@app.post("/api/mobile/resend-verification")
def mobile_resend_verification(body: EmailOnlyBody):
    return _send_mobile_verification_response(body.email)


@app.post("/api/mobile/verify-code")
def mobile_verify_code_alias(body: VerifyEmailBody):
    return JSONResponse({
        "error": "Backend OTP codes were removed. Please use Firebase email verification links.",
        "firebase_email_verification": True,
    }, status_code=410)


@app.post("/api/mobile/google-login")
def mobile_google_login(body: GoogleLoginBody):
    token = body.id_token.strip()
    if not token:
        return JSONResponse({"error": "Missing Google token."}, status_code=400)
    try:
        info_req = urllib.request.Request("https://oauth2.googleapis.com/tokeninfo?id_token=" + urllib.parse.quote(token))
        with urllib.request.urlopen(info_req, timeout=12) as resp:
            profile = json.loads(resp.read().decode("utf-8"))
    except Exception as exc:
        print(f"Mobile Firebase Google token check failed: {exc}")
        return JSONResponse({"error": "Google sign-in token could not be verified."}, status_code=401)

    allowed_audiences = {x for x in [GOOGLE_CLIENT_ID, FIREBASE_WEB_CLIENT_ID] if x}
    aud = str(profile.get("aud", "")).strip()
    if allowed_audiences and aud not in allowed_audiences:
        return JSONResponse({"error": "Google client ID did not match this GeoSustain project."}, status_code=401)

    email = str(profile.get("email", "")).strip().lower()
    google_sub = str(profile.get("sub", "")).strip()
    given_name = str(profile.get("given_name") or "").strip()
    full_name = str(profile.get("name") or "").strip()
    first_name = given_name or (full_name.split()[0] if full_name else email.split("@")[0])
    if not email or not google_sub:
        return JSONResponse({"error": "Google account did not provide an email address."}, status_code=400)

    user = get_user_by_google_sub(google_sub)
    if not user:
        existing = get_user_by_email(email)
        if existing:
            user = link_google_to_user(existing["id"], google_sub)
            # Keep a real name for previously-created placeholder accounts when possible.
            try:
                if str(existing.get("username") or "").lower() in ("user", "farmer", email.split("@")[0].lower()):
                    update_user_profile(existing["id"], username=first_name[:80])
                    user = get_user_by_id(existing["id"])
            except Exception:
                pass
        else:
            base = ''.join(ch for ch in first_name if ch.isalnum() or ch in " _-").strip()[:32] or email.split('@')[0]
            username = base
            suffix = 1
            while get_user_by_username(username):
                suffix += 1
                username = f"{base}{suffix}"[:40]
            requested_role = (body.role or 'farmer').strip().lower()
            if requested_role not in ('farmer', 'analyst', 'planner'):
                requested_role = 'farmer'
            user = create_user(username, email, hash_password(secrets.token_urlsafe(32)), requested_role, email_verified=True, auth_provider="google", google_sub=google_sub)
    if not user:
        return JSONResponse({"error": "Could not create or link Google account."}, status_code=500)
    return {"user": user_public_dict(user), "token": generate_mobile_token(user)}

@app.get("/api/mobile/me")
def mobile_me(user=Depends(get_api_user)):
    return {"user": user_public_dict(user)}


@app.put("/api/mobile/me")
def mobile_update_me(body: ProfileUpdateBody, user=Depends(get_api_user)):
    updated = update_user_profile(
        user["id"],
        username=(body.username.strip() if body.username else None),
        role=body.role,
        location=body.location,
        profile_photo=body.profile_photo,
    )
    return {"user": user_public_dict(updated or get_user_by_id(user["id"]))}



@app.post("/api/mobile/profile")
def mobile_update_profile_alias(body: ProfileUpdateBody, user=Depends(get_api_user)):
    updated = update_user_profile(
        user["id"],
        username=body.username,
        role=body.role,
        location=body.location,
        profile_photo=body.profile_photo,
    )
    return {"user": user_public_dict(updated or get_user_by_id(user["id"]))}

@app.post("/api/mobile/me/deactivate")
def mobile_deactivate_me(user=Depends(get_api_user)):
    deactivate_user(user["id"])
    return {"ok": True, "message": "Account deactivated."}


@app.delete("/api/mobile/me")
def mobile_delete_me(user=Depends(get_api_user)):
    delete_user(user["id"])
    return {"ok": True, "message": "Account deleted."}


@app.get("/api/mobile/weather")
def mobile_live_weather(lat: float, lon: float):
    # Public lightweight endpoint for the Home page. Auth is intentionally not
    # required because live weather should load before/after Firebase login and
    # should not break when a local token is missing or expired.
    try:
        return fetch_open_meteo_weather(lat, lon)
    except Exception as e:
        print(f"Open-Meteo fetch failed: {type(e).__name__}: {e}")
        return JSONResponse({"error": "Unable to fetch live Open-Meteo weather right now."}, status_code=502)


@app.get("/api/mobile/history")
def mobile_history(user=Depends(get_api_user)):
    rows = get_user_history(user["id"], limit=50)
    return {"history": [dict(row) for row in rows]}


@app.get("/api/mobile/counts")
def mobile_counts(user=Depends(get_api_user)):
    return get_user_counts(user["id"])


@app.post("/api/mobile/save-analysis")
def mobile_save_analysis(body: SessionActionBody, user=Depends(get_api_user)):
    item = save_analysis_for_user(user["id"], body.session_id)
    return {"saved": item}


@app.get("/api/mobile/saved")
def mobile_saved(user=Depends(get_api_user)):
    return {"saved": get_saved_analyses(user["id"], limit=50)}


@app.post("/api/mobile/report")
def mobile_create_report(body: SessionActionBody, user=Depends(get_api_user)):
    item = create_report_for_user(user["id"], body.session_id, body.title)
    return {"report": item}


@app.get("/api/mobile/reports")
def mobile_reports(user=Depends(get_api_user)):
    return {"reports": get_reports(user["id"], limit=50)}


@app.get("/api/mobile/reverse-geocode")
def mobile_reverse_geocode(lat: float, lon: float, user=Depends(get_api_user)):
    return {"place_name": reverse_geocode_place(lat, lon)}


@app.post("/api/mobile/analysis")
def mobile_analysis(body: AnalysisBody, user=Depends(get_api_user)):
    try:
        result, analysis_source = build_analysis_result(body=body.dict(exclude_none=True))
    except ValueError as e:
        return JSONResponse({"error": str(e)}, status_code=400)
    except RuntimeError as e:
        return JSONResponse({"error": str(e)}, status_code=503)
    except Exception as e:
        print(f"Analysis failed: {e}")
        return JSONResponse({"error": f"Analysis failed: {e}"}, status_code=500)

    try:
        session_id = save_analysis_session(user["id"], result, analysis_source)
        result["session_id"] = session_id
    except Exception as e:
        print(f"DB save failed: {e}")
        result["session_id"] = None
    return result


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("fastapi_app:app", host="0.0.0.0", port=8000, reload=False)
