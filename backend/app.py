"""
app.py  —  GeoSustain Flask Application
----------------------------------------
Routes:
  GET  /              → redirect to /dashboard if logged in, else /login
  GET  /login         → login page
  POST /login         → authenticate and redirect
  GET  /register      → register page
  POST /register      → create account and redirect
  GET  /logout        → clear session and redirect to /login
  GET  /dashboard     → main map dashboard (login required)
  GET  /history       → user's past analyses (login required)
  POST /api/analysis  → run GEE + ML analysis (login required)
"""

import os
import secrets
from datetime import datetime, timezone, timedelta
from flask import (
    Flask, render_template, request, redirect,
    url_for, session, jsonify, flash,
)
from flask_bcrypt import Bcrypt
from itsdangerous import URLSafeTimedSerializer, BadSignature, SignatureExpired

try:
    from flask_cors import CORS
except ImportError:
    CORS = None
from database import (
    init_db, create_user, get_user_by_email, get_user_by_id, get_user_by_username,
    save_analysis_session, get_user_history, set_email_verification_code,
    mark_email_verified, get_user_by_google_sub, link_google_to_user, update_user_profile,
    upsert_pending_registration, get_pending_registration, delete_pending_registration,
)
from rainfallDatasets import analyze_location
from functools import wraps

app = Flask(__name__)
app.secret_key = os.getenv("SECRET_KEY", "geosustain-secret-change-in-production")
bcrypt = Bcrypt(app)
if CORS:
    CORS(app, supports_credentials=True)

token_serializer = URLSafeTimedSerializer(app.secret_key)
MOBILE_TOKEN_MAX_AGE = 60 * 60 * 24 * 30  # 30 days
VERIFICATION_CODE_MAX_AGE_MINUTES = int(os.getenv("VERIFICATION_CODE_MAX_AGE_MINUTES", "10"))


# ---------------------------------------------------------------------------
# Bootstrap DB on startup
# ---------------------------------------------------------------------------
with app.app_context():
    init_db()


# ---------------------------------------------------------------------------
# Auth helper
# ---------------------------------------------------------------------------
def login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if "user_id" not in session:
            flash("Please log in to continue.", "warning")
            return redirect(url_for("login"))
        return f(*args, **kwargs)
    return decorated


def current_user():
    uid = session.get("user_id")
    return get_user_by_id(uid) if uid else None




# ---------------------------------------------------------------------------
# Mobile API auth helpers
# ---------------------------------------------------------------------------
def generate_mobile_token(user):
    return token_serializer.dumps({
        "id": user["id"],
        "username": user["username"],
        "role": user["role"],
        "location": user.get("location"),
        "profile_photo": user.get("profile_photo"),
        "email_verified": user.get("email_verified", False),
        "auth_provider": user.get("auth_provider", "email"),
    }, salt="geosustain-mobile")


def get_user_from_bearer_token():
    auth_header = request.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        return None
    token = auth_header.split(" ", 1)[1].strip()
    try:
        payload = token_serializer.loads(
            token, salt="geosustain-mobile", max_age=MOBILE_TOKEN_MAX_AGE
        )
    except (BadSignature, SignatureExpired):
        return None
    return get_user_by_id(payload.get("id"))


def api_login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        user = get_user_from_bearer_token()
        if not user:
            return jsonify({"error": "Unauthorized. Please log in again."}), 401
        request.current_api_user = user
        return f(*args, **kwargs)
    return decorated


def user_public_dict(user):
    return {
        "id": user["id"],
        "username": user["username"],
        "email": user["email"],
        "role": user["role"],
        "location": user.get("location"),
        "profile_photo": user.get("profile_photo"),
        "email_verified": user.get("email_verified", False),
        "auth_provider": user.get("auth_provider", "email"),
    }

# ---------------------------------------------------------------------------
# Auth routes
# ---------------------------------------------------------------------------
@app.route("/")
def index():
    if "user_id" in session:
        return redirect(url_for("dashboard"))
    return redirect(url_for("login"))


@app.route("/login", methods=["GET", "POST"])
def login():
    if "user_id" in session:
        return redirect(url_for("dashboard"))

    if request.method == "POST":
        email    = request.form.get("email", "").strip().lower()
        password = request.form.get("password", "")

        if not email or not password:
            flash("Email and password are required.", "error")
            return render_template("login.html")

        user = get_user_by_email(email)
        if not user or not bcrypt.check_password_hash(user["password_hash"], password):
            flash("Invalid email or password.", "error")
            return render_template("login.html")

        session["user_id"]   = user["id"]
        session["username"]  = user["username"]
        session["role"]      = user["role"]
        return redirect(url_for("dashboard"))

    return render_template("login.html")


@app.route("/register", methods=["GET", "POST"])
def register():
    if "user_id" in session:
        return redirect(url_for("dashboard"))

    if request.method == "POST":
        username = request.form.get("username", "").strip()
        email    = request.form.get("email", "").strip().lower()
        password = request.form.get("password", "")
        confirm  = request.form.get("confirm_password", "")
        role     = request.form.get("role", "farmer")

        # Validation
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
            for e in errors:
                flash(e, "error")
            return render_template("register.html",
                                   username=username, email=email, role=role)

        pw_hash = bcrypt.generate_password_hash(password).decode("utf-8")
        user    = create_user(username, email, pw_hash, role)

        if not user:
            flash("Registration failed. Please try again.", "error")
            return render_template("register.html")

        flash("Account created! Please log in.", "success")
        return redirect(url_for("login"))

    return render_template("register.html")


@app.route("/logout")
def logout():
    session.clear()
    flash("You have been logged out.", "info")
    return redirect(url_for("login"))


# ---------------------------------------------------------------------------
# Main dashboard
# ---------------------------------------------------------------------------
@app.route("/dashboard")
@login_required
def dashboard():
    user = current_user()
    return render_template("index.html", user=user)


# ---------------------------------------------------------------------------
# Analysis history
# ---------------------------------------------------------------------------
@app.route("/history")
@login_required
def history():
    user = current_user()
    rows = get_user_history(user["id"], limit=20)
    return render_template("history.html", user=user, history=rows)


# ---------------------------------------------------------------------------
# Analysis API
# ---------------------------------------------------------------------------
def polygon_centroid(latlngs):
    if not latlngs or len(latlngs) < 3:
        return None, None
    lat_total = sum(float(p["lat"]) for p in latlngs)
    lon_total = sum(float(p["lng"]) for p in latlngs)
    count = len(latlngs)
    return lat_total / count, lon_total / count


def point_in_polygon(lat, lon, polygon):
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


def polygon_area_sample_points(polygon, max_points=7):
    center = polygon_centroid(polygon)
    samples = []
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


def merge_area_results(results):
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

    crop_scores = {}
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




def build_analysis_result(body=None, query_args=None):
    analysis_source = None
    polygon = []

    if body is not None:
        polygon = body.get("polygon", [])
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
        lat = query_args.get("lat", type=float)
        lon = query_args.get("lon", type=float)
        if lat is None or lon is None:
            raise ValueError("lat and lon query parameters are required.")
        analysis_source = "query-point"

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
    return result, analysis_source

@app.route("/api/analysis", methods=["GET", "POST"])
@login_required
def analysis():
    try:
        result, analysis_source = build_analysis_result(
            body=(request.get_json(silent=True) or {}) if request.method == "POST" else None,
            query_args=request.args,
        )
    except ValueError as e:
        return jsonify({"error": str(e)}), 400

    user_id = session.get("user_id")
    try:
        session_id = save_analysis_session(user_id, result, analysis_source)
        result["session_id"] = session_id
    except Exception as e:
        app.logger.warning(f"DB save failed: {e}")
        result["session_id"] = None

    return jsonify(result)


# ---------------------------------------------------------------------------
# Email verification helpers for mobile JSON API
# ---------------------------------------------------------------------------
def generate_verification_code():
    return f"{secrets.randbelow(1_000_000):06d}"


def send_verification_email(email, code):
    print(f"[LEGACY EMAIL CODE DISABLED] Firebase handles email verification for {email}.")
    return False

def issue_and_send_verification_code(email):
    code = generate_verification_code()
    code_hash = bcrypt.generate_password_hash(code).decode("utf-8")
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=VERIFICATION_CODE_MAX_AGE_MINUTES)
    set_email_verification_code(email, code_hash, expires_at)
    return send_verification_email(email, code)


def make_verification_code_payload():
    code = generate_verification_code()
    code_hash = bcrypt.generate_password_hash(code).decode("utf-8")
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=VERIFICATION_CODE_MAX_AGE_MINUTES)
    return code, code_hash, expires_at


def _send_mobile_verification_response(email):
    email = (email or "").strip().lower()
    pending = get_pending_registration(email)
    if pending:
        try:
            code, code_hash, expires_at = make_verification_code_payload()
            upsert_pending_registration(pending["username"], email, pending["password_hash"], pending.get("role") or "farmer", code_hash, expires_at)
            sent = send_verification_email(email, code)
        except Exception as exc:
            app.logger.warning(f"Mobile pending verification resend failed: {exc}")
            return jsonify({"error": "Firebase email verification is now used. Please resend the verification link from the app."}), 500
        return jsonify({
            "message": "Firebase verification link sent." if sent else "Verification code generated. Firebase email verification is enabled, so check backend logs for the code.",
            "sent": bool(sent),
            "pending": True,
        })

    user = get_user_by_email(email)
    if not user:
        return jsonify({"error": "No pending registration found. Please create an account first."}), 404
    if user.get("email_verified"):
        return jsonify({"message": "Email is already verified."})
    try:
        sent = issue_and_send_verification_code(email)
    except Exception as exc:
        app.logger.warning(f"Mobile resend verification failed: {exc}")
        return jsonify({"error": "Firebase email verification is now used. Please resend the verification link from the app."}), 500
    return jsonify({
        "message": "Firebase verification link sent." if sent else "Verification code generated. Firebase email verification is enabled, so check backend logs for the code.",
        "sent": bool(sent),
    })

# ---------------------------------------------------------------------------
# Mobile JSON API routes
# ---------------------------------------------------------------------------
@app.route("/api/mobile/register", methods=["POST"])
def mobile_register():
    body = request.get_json(silent=True) or {}
    username = body.get("username", "").strip()
    email = body.get("email", "").strip().lower()
    password = body.get("password", "")
    role = body.get("role", "farmer")

    errors = []
    if not username or len(username) < 3:
        errors.append("Username must be at least 3 characters.")
    if not email or "@" not in email:
        errors.append("A valid email is required.")
    if not password or len(password) < 6:
        errors.append("Password must be at least 6 characters.")
    if role not in ("farmer", "analyst"):
        role = "farmer"
    if get_user_by_email(email):
        errors.append("Email is already registered.")
    if errors:
        return jsonify({"errors": errors}), 400

    try:
        code, code_hash, expires_at = make_verification_code_payload()
        pw_hash = bcrypt.generate_password_hash(password).decode("utf-8")
        upsert_pending_registration(username, email, pw_hash, role, code_hash, expires_at)
        sent = send_verification_email(email, code)
    except Exception as exc:
        app.logger.warning(f"Mobile pending registration failed: {exc}")
        return jsonify({"error": "Firebase email verification is now used. Please resend the verification link from the app."}), 500

    return jsonify({
        "requires_verification": True,
        "pending": True,
        "sent": bool(sent),
        "message": "Firebase verification link sent. Your account will be created after verification.",
    }), 201


@app.route("/api/mobile/login", methods=["POST"])
def mobile_login():
    body = request.get_json(silent=True) or {}
    email = body.get("email", "").strip().lower()
    password = body.get("password", "")
    user = get_user_by_email(email)
    if not user or not bcrypt.check_password_hash(user["password_hash"], password):
        return jsonify({"error": "Invalid email or password."}), 401
    if user.get("is_active") is False:
        return jsonify({"error": "This account is deactivated."}), 403
    if not user.get("email_verified"):
        try:
            issue_and_send_verification_code(email)
        except Exception as exc:
            app.logger.warning(f"Mobile verification resend failed: {exc}")
        return jsonify({"error": "Please verify your email first.", "requires_verification": True}), 403
    return jsonify({"user": user_public_dict(user), "token": generate_mobile_token(user)})


@app.route("/api/mobile/send-verification", methods=["POST"])
def mobile_send_verification():
    body = request.get_json(silent=True) or {}
    return _send_mobile_verification_response(body.get("email"))


@app.route("/api/mobile/resend-verification", methods=["POST"])
def mobile_resend_verification():
    body = request.get_json(silent=True) or {}
    return _send_mobile_verification_response(body.get("email"))


@app.route("/api/mobile/verify-email", methods=["POST"])
@app.route("/api/mobile/verify-code", methods=["POST"])
def mobile_verify_email():
    body = request.get_json(silent=True) or {}
    email = body.get("email", "").strip().lower()
    code = body.get("code", "").strip().replace(" ", "")

    pending = get_pending_registration(email)
    if pending:
        expires_at = pending.get("verification_expires_at")
        if expires_at and getattr(expires_at, "tzinfo", None) is None:
            expires_at = expires_at.replace(tzinfo=timezone.utc)
        if not pending.get("verification_code_hash") or not expires_at or expires_at < datetime.now(timezone.utc):
            return jsonify({"error": "Verification code expired. Please request a new one."}), 400
        if not bcrypt.check_password_hash(pending["verification_code_hash"], code):
            return jsonify({"error": "Incorrect verification code."}), 400
        if get_user_by_email(email):
            delete_pending_registration(email)
            return jsonify({"error": "Email is already registered."}), 400
        user = create_user(pending["username"], email, pending["password_hash"], pending.get("role") or "farmer", email_verified=True, auth_provider="email")
        if not user:
            return jsonify({"error": "Could not create account after verification."}), 500
        delete_pending_registration(email)
        return jsonify({"user": user_public_dict(user), "token": generate_mobile_token(user), "message": "Account verified and created."})

    user = get_user_by_email(email)
    if not user:
        return jsonify({"error": "No pending registration found. Please create an account first."}), 404
    if user.get("email_verified"):
        return jsonify({"user": user_public_dict(user), "token": generate_mobile_token(user)})
    expires_at = user.get("verification_expires_at")
    if expires_at and getattr(expires_at, "tzinfo", None) is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    if not user.get("verification_code_hash") or not expires_at or expires_at < datetime.now(timezone.utc):
        return jsonify({"error": "Verification code expired. Please request a new one."}), 400
    if not bcrypt.check_password_hash(user["verification_code_hash"], code):
        return jsonify({"error": "Incorrect verification code."}), 400
    verified_user = mark_email_verified(email)
    return jsonify({"user": user_public_dict(verified_user), "token": generate_mobile_token(verified_user)})


@app.route("/api/mobile/me", methods=["GET"])
@api_login_required
def mobile_me():
    return jsonify({"user": user_public_dict(request.current_api_user)})


@app.route("/api/mobile/history", methods=["GET"])
@api_login_required
def mobile_history():
    rows = get_user_history(request.current_api_user["id"], limit=20)
    return jsonify({"history": [dict(row) for row in rows]})


@app.route("/api/mobile/analysis", methods=["POST"])
@api_login_required
def mobile_analysis():
    try:
        result, analysis_source = build_analysis_result(
            body=request.get_json(silent=True) or {},
            query_args=request.args,
        )
    except ValueError as e:
        return jsonify({"error": str(e)}), 400

    try:
        session_id = save_analysis_session(request.current_api_user["id"], result, analysis_source)
        result["session_id"] = session_id
    except Exception as e:
        app.logger.warning(f"DB save failed: {e}")
        result["session_id"] = None
    return jsonify(result)


# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    app.run(debug=True)
