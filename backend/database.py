import os
import config  # noqa: F401 -- load local environment before reading settings
import psycopg2
from psycopg2.extras import RealDictCursor, Json

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://postgres:postgres@localhost:5432/geosustain_db"
)


def get_conn():
    """Open and return a fresh psycopg2 connection."""
    return psycopg2.connect(DATABASE_URL, cursor_factory=RealDictCursor)

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS users (
    id            SERIAL PRIMARY KEY,
    username      VARCHAR(50)  NOT NULL,
    email         VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role          VARCHAR(50)  NOT NULL DEFAULT 'farmer',
    location      VARCHAR(200),
    profile_photo TEXT,
    is_active     BOOLEAN NOT NULL DEFAULT TRUE,
    email_verified BOOLEAN NOT NULL DEFAULT FALSE,
    verification_code_hash VARCHAR(255),
    verification_expires_at TIMESTAMPTZ,
    google_sub VARCHAR(255) UNIQUE,
    auth_provider VARCHAR(30) NOT NULL DEFAULT 'email',
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS farm_parcels (
    id              SERIAL PRIMARY KEY,
    farmer_id       INTEGER REFERENCES users(id) ON DELETE CASCADE,
    farm_name       VARCHAR(160) NOT NULL,
    location_name   VARCHAR(240),
    polygon         JSONB NOT NULL,
    area_m2         FLOAT,
    area_hectares   FLOAT,
    mapping_method  VARCHAR(40) NOT NULL DEFAULT 'manual_draw',
    gps_accuracy_m  FLOAT,
    is_archived     BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS climate_monthly_baselines (
    id              SERIAL PRIMARY KEY,
    latitude_key    FLOAT NOT NULL,
    longitude_key   FLOAT NOT NULL,
    month_number    INTEGER NOT NULL,
    mean_temperature_c FLOAT,
    mean_rainfall_mm FLOAT,
    mean_humidity_pct FLOAT,
    baseline_start_year INTEGER,
    baseline_end_year INTEGER,
    source_name     VARCHAR(120) NOT NULL DEFAULT 'NASA POWER',
    fetched_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(latitude_key, longitude_key, month_number)
);


CREATE TABLE IF NOT EXISTS analysis_sessions (
    id              SERIAL PRIMARY KEY,
    user_id         INTEGER REFERENCES users(id) ON DELETE SET NULL,
    farm_id         INTEGER REFERENCES farm_parcels(id) ON DELETE SET NULL,
    center_lat      FLOAT NOT NULL,
    center_lon      FLOAT NOT NULL,
    place_name      VARCHAR(200),
    analysis_source VARCHAR(50),
    season_name     VARCHAR(80),
    season_advice   TEXT,
    intended_planting_month INTEGER,
    season_status VARCHAR(50),
    season_adjusted_score FLOAT,
    environmental_suitability_pct FLOAT,
    recommended_planting_window TEXT,
    analyzed_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    verification_status VARCHAR(20) NOT NULL DEFAULT 'draft',
    verified_by     INTEGER REFERENCES users(id) ON DELETE SET NULL,
    verified_at     TIMESTAMPTZ,
    planner_notes   TEXT,
    selected_polygon JSONB,
    heatmap_grid JSONB,
    area_m2 FLOAT,
    area_hectares FLOAT
);

CREATE TABLE IF NOT EXISTS environmental_data (
    id                  SERIAL PRIMARY KEY,
    session_id          INTEGER REFERENCES analysis_sessions(id) ON DELETE CASCADE,
    ndvi                FLOAT,
    biomass             FLOAT,
    rainfall_mm         FLOAT,
    temperature_c       FLOAT,
    elevation_m         FLOAT,
    soil_ph             FLOAT,
    live_humidity       FLOAT,
    wind_speed_ms       FLOAT,
    cloud_cover_pct     FLOAT,
    weather_description VARCHAR(120),
    infrastructure_suitability VARCHAR(80),
    infrastructure_score FLOAT,
    infrastructure_status TEXT,
    infrastructure_recommendation TEXT,
    infrastructure_risk VARCHAR(80),
    slope_pct FLOAT
);

CREATE TABLE IF NOT EXISTS soil_nutrients (
    id                  SERIAL PRIMARY KEY,
    session_id          INTEGER REFERENCES analysis_sessions(id) ON DELETE CASCADE,
    nitrogen            FLOAT,
    phosphorus          FLOAT,
    potassium           FLOAT,
    nitrogen_index_pct  FLOAT
);

CREATE TABLE IF NOT EXISTS crop_recommendations (
    id                   SERIAL PRIMARY KEY,
    session_id           INTEGER REFERENCES analysis_sessions(id) ON DELETE CASCADE,
    raw_predicted_crop   VARCHAR(80),
    predicted_crop       VARCHAR(80),
    compatibility_pct    FLOAT,
    suitability_level    VARCHAR(40),
    is_crop_recommended  BOOLEAN,
    land_type            VARCHAR(40),
    land_status          VARCHAR(120),
    recommendation_title VARCHAR(120),
    recommendation       TEXT,
    crop_label           VARCHAR(120),
    crop_growth_cycle    VARCHAR(80),
    crop_est_yield       VARCHAR(80),
    alternative_crops     JSONB,
    xai_explanation        JSONB
);

CREATE TABLE IF NOT EXISTS analysis_cache (
    id             SERIAL PRIMARY KEY,
    lat_rounded    FLOAT NOT NULL,
    lon_rounded    FLOAT NOT NULL,
    cached_result  JSONB NOT NULL,
    cached_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at     TIMESTAMPTZ NOT NULL,
    UNIQUE (lat_rounded, lon_rounded)
);

CREATE TABLE IF NOT EXISTS pending_registrations (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(50) NOT NULL DEFAULT 'farmer',
    verification_code_hash VARCHAR(255) NOT NULL,
    verification_expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


CREATE TABLE IF NOT EXISTS saved_analyses (
    id             SERIAL PRIMARY KEY,
    user_id        INTEGER REFERENCES users(id) ON DELETE CASCADE,
    session_id     INTEGER REFERENCES analysis_sessions(id) ON DELETE CASCADE,
    saved_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, session_id)
);



CREATE TABLE IF NOT EXISTS reports (
    id             SERIAL PRIMARY KEY,
    user_id        INTEGER REFERENCES users(id) ON DELETE CASCADE,
    session_id     INTEGER REFERENCES analysis_sessions(id) ON DELETE CASCADE,
    report_title   VARCHAR(160),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, session_id)
);
"""


def init_db():
    """Create all tables if they do not already exist."""
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(SCHEMA_SQL)
            cur.execute("ALTER TABLE analysis_sessions ADD COLUMN IF NOT EXISTS place_name VARCHAR(200)")
            cur.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS location VARCHAR(200)")
            cur.execute("ALTER TABLE users ALTER COLUMN role TYPE VARCHAR(50)")
            # Migrate any legacy/obsolete role strings that may still exist in
            # the database (from earlier project iterations) to the three
            # finalized GeoSustain roles. Idempotent — safe to run every startup.
            cur.execute(
                """
                UPDATE users SET role = 'agricultural_planning_analyst'
                WHERE LOWER(role) IN ('analyst', 'planner', 'lgu_officer', 'env_planner')
                """
            )
            cur.execute(
                """
                UPDATE users SET role = 'super_admin'
                WHERE LOWER(role) = 'admin'
                """
            )
            cur.execute(
                """
                UPDATE users SET role = 'farmer'
                WHERE role IS NULL OR LOWER(role) NOT IN ('farmer', 'agricultural_planning_analyst', 'super_admin')
                """
            )
            cur.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS profile_photo TEXT")
            cur.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE")
            cur.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS email_verified BOOLEAN NOT NULL DEFAULT FALSE")
            cur.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS verification_code_hash VARCHAR(255)")
            cur.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS verification_expires_at TIMESTAMPTZ")
            cur.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS google_sub VARCHAR(255) UNIQUE")
            cur.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS auth_provider VARCHAR(30) NOT NULL DEFAULT 'email'")
            cur.execute("ALTER TABLE environmental_data ADD COLUMN IF NOT EXISTS infrastructure_suitability VARCHAR(80)")
            cur.execute("ALTER TABLE environmental_data ADD COLUMN IF NOT EXISTS infrastructure_score FLOAT")
            cur.execute("ALTER TABLE environmental_data ADD COLUMN IF NOT EXISTS infrastructure_status TEXT")
            cur.execute("ALTER TABLE environmental_data ADD COLUMN IF NOT EXISTS infrastructure_recommendation TEXT")
            cur.execute("ALTER TABLE environmental_data ADD COLUMN IF NOT EXISTS infrastructure_risk VARCHAR(80)")
            cur.execute("ALTER TABLE environmental_data ADD COLUMN IF NOT EXISTS slope_pct FLOAT")
            cur.execute("ALTER TABLE environmental_data ADD COLUMN IF NOT EXISTS data_quality JSONB")
            cur.execute("ALTER TABLE crop_recommendations ADD COLUMN IF NOT EXISTS alternative_crops JSONB")
            cur.execute("ALTER TABLE crop_recommendations ADD COLUMN IF NOT EXISTS xai_explanation JSONB")
            cur.execute("ALTER TABLE analysis_sessions ADD COLUMN IF NOT EXISTS verification_status VARCHAR(20) NOT NULL DEFAULT 'draft'")
            # One-time migration from the old automatic-pending behavior. Only run
            # while the database column still has the old pending default, so real
            # farmer submissions are never reset on later app restarts.
            cur.execute("""
                DO $$
                DECLARE old_default TEXT;
                BEGIN
                    SELECT column_default INTO old_default
                    FROM information_schema.columns
                    WHERE table_name = 'analysis_sessions'
                      AND column_name = 'verification_status';
                    IF old_default LIKE '%pending%' THEN
                        UPDATE analysis_sessions
                        SET verification_status = 'draft'
                        WHERE verification_status = 'pending'
                          AND verified_by IS NULL
                          AND verified_at IS NULL;
                    END IF;
                END $$;
            """)
            cur.execute("ALTER TABLE analysis_sessions ALTER COLUMN verification_status SET DEFAULT 'draft'")
            cur.execute("ALTER TABLE analysis_sessions ADD COLUMN IF NOT EXISTS verified_by INTEGER REFERENCES users(id) ON DELETE SET NULL")
            cur.execute("ALTER TABLE analysis_sessions ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ")
            cur.execute("ALTER TABLE analysis_sessions ADD COLUMN IF NOT EXISTS planner_notes TEXT")
            cur.execute("ALTER TABLE analysis_sessions ADD COLUMN IF NOT EXISTS selected_polygon JSONB")
            cur.execute("ALTER TABLE analysis_sessions ADD COLUMN IF NOT EXISTS heatmap_grid JSONB")
            cur.execute("ALTER TABLE analysis_sessions ADD COLUMN IF NOT EXISTS area_m2 FLOAT")
            cur.execute("ALTER TABLE analysis_sessions ADD COLUMN IF NOT EXISTS area_hectares FLOAT")
            cur.execute("ALTER TABLE analysis_sessions ADD COLUMN IF NOT EXISTS intended_planting_month INTEGER")
            cur.execute("ALTER TABLE analysis_sessions ADD COLUMN IF NOT EXISTS season_status VARCHAR(50)")
            cur.execute("ALTER TABLE analysis_sessions ADD COLUMN IF NOT EXISTS season_adjusted_score FLOAT")
            cur.execute("ALTER TABLE analysis_sessions ADD COLUMN IF NOT EXISTS environmental_suitability_pct FLOAT")
            cur.execute("ALTER TABLE analysis_sessions ADD COLUMN IF NOT EXISTS recommended_planting_window TEXT")
            cur.execute("ALTER TABLE analysis_sessions ADD COLUMN IF NOT EXISTS farm_id INTEGER REFERENCES farm_parcels(id) ON DELETE SET NULL")
            cur.execute("ALTER TABLE analysis_sessions ADD COLUMN IF NOT EXISTS analysis_summary TEXT")
            # Usernames are display names; only email must be unique.
            cur.execute("ALTER TABLE users DROP CONSTRAINT IF EXISTS users_username_key")

            # --- Super Administrator: crop reference management (Section 17) ---
            cur.execute("""
                CREATE TABLE IF NOT EXISTS crop_reference (
                    id SERIAL PRIMARY KEY,
                    crop_key VARCHAR(60) UNIQUE NOT NULL,
                    label TEXT NOT NULL,
                    growth_cycle TEXT,
                    est_yield TEXT,
                    suitability_note TEXT,
                    is_active BOOLEAN NOT NULL DEFAULT TRUE,
                    updated_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
                    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
                )
            """)
            # Seed with the finalized approved crop set (Section 9) exactly once —
            # ON CONFLICT DO NOTHING means re-running this never overwrites a
            # Super Administrator's later edits.
            cur.execute("""
                INSERT INTO crop_reference (crop_key, label, growth_cycle, est_yield, suitability_note)
                VALUES
                    ('banana (cavendish/lakatan)', 'Cavendish Variety (Export Grade)', '9-12 Months', '35 Tons / Ha', 'Thrives in Panabo''s high humidity and warm temperature.'),
                    ('banana (saba)', 'Saba Variety (Cooking Banana)', '10-12 Months', '28 Tons / Ha', 'Well-suited for Panabo''s soil and rainfall profile.'),
                    ('coconut', 'Coconut Palm', '36-48 Months (first harvest)', '4-6 Tons Copra / Ha', 'Thrives in coastal and lowland areas of Davao del Norte.'),
                    ('cacao', 'Cacao Plantation', '24-36 Months', '0.8 Tons / Ha', 'High-value crop suited for shaded agroforestry systems.'),
                    ('papaya', 'Papaya (Solo / Red Lady)', '6-9 Months', '40 Tons / Ha', 'Fast-growing; ideal for loamy soils with good drainage.'),
                    ('abaca', 'Abaca (Fiber Crop)', '18-24 Months', '1.2 Tons / Ha', 'Davao Region is the top abaca producer in the Philippines.'),
                    ('rice', 'Rice (Lowland Variety)', '3-4 Months', '4-5 Tons / Ha', 'Suitable for low-lying, high-rainfall areas of Panabo.'),
                    ('corn (white/yellow)', 'Corn (White/Yellow Variety)', '3 Months', '5-7 Tons / Ha', 'Commonly grown in Davao del Norte upland barangays.'),
                    ('watermelon', 'Watermelon (Local/Hybrid)', '2-3 Months', '20-25 Tons / Ha', 'Grows well during dry season with irrigation support.'),
                    ('durian', 'Durian (Davao Variety)', '4-6 Years (first harvest)', '8-15 Tons / Ha', 'High-value Mindanao fruit crop suited to warm, humid, well-drained areas.'),
                    ('cassava', 'Cassava / Kamoteng Kahoy', '8-12 Months', '15-25 Tons / Ha', 'Tolerates drier and less fertile soils; useful for food and feed production.'),
                    ('sweet potato', 'Sweet Potato / Kamote', '3-5 Months', '8-15 Tons / Ha', 'Short-cycle root crop suited for diversified lowland and upland farming.'),
                    ('rubber', 'Rubber Tree', '5-7 Years (tapping starts)', '1-2 Tons Dry Rubber / Ha', 'Suitable for humid Mindanao areas with stable rainfall and well-drained soils.'),
                    ('pomelo', 'Pomelo', '3-5 Years (first harvest)', '10-20 Tons / Ha', 'A Davao-associated fruit crop suited for warm areas with moderate rainfall.')
                ON CONFLICT (crop_key) DO NOTHING
            """)

            # --- Super Administrator: audit log for security-sensitive actions ---
            cur.execute("""
                CREATE TABLE IF NOT EXISTS audit_logs (
                    id SERIAL PRIMARY KEY,
                    actor_user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
                    actor_role VARCHAR(40),
                    action VARCHAR(60) NOT NULL,
                    target_type VARCHAR(40),
                    target_id INTEGER,
                    details JSONB,
                    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
                )
            """)
            cur.execute("CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON audit_logs (created_at DESC)")
        conn.commit()
    finally:
        conn.close()


def create_user(username: str, email: str, password_hash: str, role: str = "farmer", email_verified: bool = False, auth_provider: str = "email", google_sub: str = None):
    """Insert a new user row. Returns the new user dict or None on duplicate."""
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO users (username, email, password_hash, role, email_verified, auth_provider, google_sub)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                RETURNING id, username, email, role, location, profile_photo, is_active, email_verified, auth_provider, created_at
                """,
                (username.strip(), email.strip().lower(), password_hash, role, email_verified, auth_provider, google_sub),
            )
            user = cur.fetchone()
        conn.commit()
        return dict(user)
    except psycopg2.errors.UniqueViolation:
        conn.rollback()
        return None
    finally:
        conn.close()


def upsert_pending_registration(username: str, email: str, password_hash: str, role: str, code_hash: str, expires_at):
    """Store signup details temporarily. Real user is created only after OTP verification."""
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO pending_registrations (username, email, password_hash, role, verification_code_hash, verification_expires_at)
                VALUES (%s, %s, %s, %s, %s, %s)
                ON CONFLICT (email) DO UPDATE SET
                    username = EXCLUDED.username,
                    password_hash = EXCLUDED.password_hash,
                    role = EXCLUDED.role,
                    verification_code_hash = EXCLUDED.verification_code_hash,
                    verification_expires_at = EXCLUDED.verification_expires_at,
                    updated_at = NOW()
                RETURNING *
                """,
                (username, email, password_hash, role, code_hash, expires_at),
            )
            row = cur.fetchone()
        conn.commit()
        return dict(row) if row else None
    finally:
        conn.close()


def get_pending_registration(email: str):
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM pending_registrations WHERE email = %s", (email,))
            row = cur.fetchone()
        return dict(row) if row else None
    finally:
        conn.close()


def delete_pending_registration(email: str):
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM pending_registrations WHERE email = %s", (email,))
        conn.commit()
        return True
    finally:
        conn.close()


def set_email_verification_code(email: str, code_hash: str, expires_at):
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE users
                   SET verification_code_hash = %s,
                       verification_expires_at = %s,
                       updated_at = NOW()
                 WHERE email = %s
                RETURNING id, username, email, role, email_verified
                """,
                (code_hash, expires_at, email),
            )
            row = cur.fetchone()
        conn.commit()
        return dict(row) if row else None
    finally:
        conn.close()


def mark_email_verified(email: str):
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE users
                   SET email_verified = TRUE,
                       verification_code_hash = NULL,
                       verification_expires_at = NULL,
                       updated_at = NOW()
                 WHERE email = %s
                RETURNING *
                """,
                (email,),
            )
            row = cur.fetchone()
        conn.commit()
        return dict(row) if row else None
    finally:
        conn.close()


def get_user_by_google_sub(google_sub: str):
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM users WHERE google_sub = %s", (google_sub,))
            row = cur.fetchone()
        return dict(row) if row else None
    finally:
        conn.close()


def link_google_to_user(user_id: int, google_sub: str):
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE users
                   SET google_sub = %s, auth_provider = 'google', email_verified = TRUE, updated_at = NOW()
                 WHERE id = %s
                RETURNING *
                """,
                (google_sub, user_id),
            )
            row = cur.fetchone()
        conn.commit()
        return dict(row) if row else None
    finally:
        conn.close()


def get_user_by_email(email: str):
    """Return user row by email, or None."""
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM users WHERE LOWER(BTRIM(email)) = LOWER(BTRIM(%s))", (email,))
            row = cur.fetchone()
        return dict(row) if row else None
    finally:
        conn.close()


def get_user_by_id(user_id: int):
    """Return user row by primary key, or None."""
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM users WHERE id = %s", (user_id,))
            row = cur.fetchone()
        return dict(row) if row else None
    finally:
        conn.close()


def get_user_by_username(username: str):
    """Return user row by username, or None."""
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM users WHERE username = %s", (username,))
            row = cur.fetchone()
        return dict(row) if row else None
    finally:
        conn.close()



def update_user_profile(user_id: int, username: str = None, role: str = None, location: str = None, profile_photo: str = None):
    """Update editable SELF-SERVICE profile fields and return the updated public row.

    SECURITY: this function is used by the mobile/web self-service "update my
    own profile" endpoints. It must NEVER be able to grant a privileged role.
    Privileged role assignment (including to Super Administrator) is only
    permitted through `admin_update_user`, which is gated behind the
    `require_super_admin` dependency in fastapi_app.py. Even if a `role`
    argument is passed in here, only the two ordinary/unprivileged roles are
    honored — an "admin"/"super_admin" value passed to THIS function is
    silently ignored rather than applied.
    """
    self_service_roles = {"farmer", "agricultural_planning_analyst"}
    updates = []
    values = []
    if username:
        updates.append("username = %s")
        values.append(username)
    if role in self_service_roles:
        updates.append("role = %s")
        values.append(role)
    if location is not None:
        updates.append("location = %s")
        values.append(location)
    if profile_photo is not None:
        updates.append("profile_photo = %s")
        values.append(profile_photo)
    if not updates:
        return get_user_by_id(user_id)
    updates.append("updated_at = NOW()")
    values.append(user_id)
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                f"""
                UPDATE users
                SET {', '.join(updates)}
                WHERE id = %s
                RETURNING id, username, email, role, location, profile_photo, is_active, created_at, updated_at
                """,
                tuple(values),
            )
            row = cur.fetchone()
        conn.commit()
        return dict(row) if row else None
    finally:
        conn.close()


def deactivate_user(user_id: int):
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute("UPDATE users SET is_active = FALSE, updated_at = NOW() WHERE id = %s", (user_id,))
        conn.commit()
        return True
    finally:
        conn.close()


def delete_user(user_id: int):
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM users WHERE id = %s", (user_id,))
        conn.commit()
        return True
    finally:
        conn.close()

# ---------------------------------------------------------------------------
# Analysis session helpers
# ---------------------------------------------------------------------------

def _polygon_points(polygon):
    pts = []
    for item in polygon or []:
        try:
            if isinstance(item, dict):
                lat = item.get("lat", item.get("latitude"))
                lon = item.get("lng", item.get("lon", item.get("longitude")))
            elif isinstance(item, (list, tuple)) and len(item) >= 2:
                lat, lon = item[0], item[1]
            else:
                continue
            pts.append((float(lat), float(lon)))
        except (TypeError, ValueError):
            continue
    return pts


def _polygon_self_intersects(pts):
    """O(n^2) segment-intersection check for an obviously self-crossing
    ('bowtie') boundary. Skipped for very large point counts (long GPS
    walks) to stay fast — such shapes are rare there and downstream
    analysis will still just get a noisier polygon rather than a crash."""
    n = len(pts)
    if n < 4 or n > 500:
        return False

    def cross(o, a, b):
        return (a[1] - o[1]) * (b[0] - o[0]) - (a[0] - o[0]) * (b[1] - o[1])

    def seg_intersect(p1, p2, p3, p4):
        d1, d2 = cross(p3, p4, p1), cross(p3, p4, p2)
        d3, d4 = cross(p1, p2, p3), cross(p1, p2, p4)
        return ((d1 > 0 and d2 < 0) or (d1 < 0 and d2 > 0)) and ((d3 > 0 and d4 < 0) or (d3 < 0 and d4 > 0))

    for i in range(n):
        a1, a2 = pts[i], pts[(i + 1) % n]
        for j in range(i + 1, n):
            if j == i or (j + 1) % n == i or i == (j + 1) % n:
                continue
            b1, b2 = pts[j], pts[(j + 1) % n]
            if seg_intersect(a1, a2, b1, b2):
                return True
    return False


def validate_farm_polygon(polygon):
    """Server-side farm boundary validation. Never trust that the client
    (mobile app) already did this — it can be bypassed by calling the API
    directly. Returns (ok: bool, error_message: str | None).

    Checks: valid lat/lon ranges, at least three distinct vertices after
    collapsing near-duplicate points, a non-degenerate (not vanishingly
    small/collinear) area, and no self-intersection — a self-crossing
    shape has no well-defined interior and breaks polygon-based
    environmental sampling and area math downstream.
    """
    import math
    pts = _polygon_points(polygon)
    for lat, lon in pts:
        if not (-90 <= lat <= 90) or not (-180 <= lon <= 180):
            return False, "One or more boundary points has an invalid GPS coordinate."

    deduped = []
    for lat, lon in pts:
        if deduped:
            plat, plon = deduped[-1]
            dlat_m = (lat - plat) * 111320
            dlon_m = (lon - plon) * 111320 * math.cos(math.radians(lat))
            if (dlat_m * dlat_m + dlon_m * dlon_m) ** 0.5 < 0.5:
                continue  # collapse near-duplicate points (<0.5m apart)
        deduped.append((lat, lon))

    if len(deduped) < 3:
        return False, "A farm boundary requires at least three distinct GPS/map points."

    area = _polygon_area_m2(polygon)
    if not area or area < 4:
        return False, "The boundary shape is too small or degenerate — the points may be collinear or nearly identical."

    if _polygon_self_intersects(deduped):
        return False, "The boundary crosses over itself. Please redraw or re-walk a simple (non-crossing) shape."

    return True, None


def _polygon_area_m2(polygon):
    """Approximate geodesic polygon area in square metres from lat/lon points."""
    import math
    pts = []
    for item in polygon or []:
        try:
            if isinstance(item, dict):
                lat = item.get("lat", item.get("latitude"))
                lon = item.get("lng", item.get("lon", item.get("longitude")))
            elif isinstance(item, (list, tuple)) and len(item) >= 2:
                lat, lon = item[0], item[1]
            else:
                continue
            pts.append((float(lat), float(lon)))
        except (TypeError, ValueError):
            continue
    if len(pts) < 3:
        return None
    lat0 = math.radians(sum(p[0] for p in pts) / len(pts))
    r = 6378137.0
    xy = [(r * math.radians(lon) * math.cos(lat0), r * math.radians(lat)) for lat, lon in pts]
    area = 0.0
    for i, (x1, y1) in enumerate(xy):
        x2, y2 = xy[(i + 1) % len(xy)]
        area += x1 * y2 - x2 * y1
    return abs(area) / 2.0

def save_analysis_session(user_id, result: dict, analysis_source: str):
    """
    Persist a full analysis result across the four related tables.
    Returns the new session_id.
    """
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            # 1. analysis_sessions
            cur.execute(
                """
                INSERT INTO analysis_sessions
                    (user_id, center_lat, center_lon, place_name, analysis_source,
                     season_name, season_advice, intended_planting_month, season_status,
                     season_adjusted_score, environmental_suitability_pct, recommended_planting_window,
                     selected_polygon, heatmap_grid, area_m2, area_hectares, analysis_summary)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                RETURNING id
                """,
                (
                    user_id,
                    result["lat"],
                    result["lon"],
                    result.get("place_name"),
                    analysis_source,
                    result.get("season_name"),
                    result.get("season_advice"),
                    result.get("intended_planting_month"),
                    result.get("season_status"),
                    result.get("season_adjusted_score"),
                    result.get("environmental_suitability_pct"),
                    result.get("recommended_planting_window"),
                    Json(result.get("selected_polygon") or []),
                    Json(result.get("heatmap_grid") or []),
                    result.get("area_m2") or _polygon_area_m2(result.get("selected_polygon") or []),
                    result.get("area_hectares") or ((result.get("area_m2") or _polygon_area_m2(result.get("selected_polygon") or [])) / 10000.0 if (result.get("area_m2") or _polygon_area_m2(result.get("selected_polygon") or [])) else None),
                    result.get("analysis_summary"),
                ),
            )
            session_id = cur.fetchone()["id"]

            # 2. environmental_data
            cur.execute(
                """
                INSERT INTO environmental_data
                    (session_id, ndvi, biomass, rainfall_mm, temperature_c,
                     elevation_m, soil_ph, live_humidity, wind_speed_ms,
                     cloud_cover_pct, weather_description,
                     infrastructure_suitability, infrastructure_score,
                     infrastructure_status, infrastructure_recommendation,
                     infrastructure_risk, slope_pct, data_quality)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                """,
                (
                    session_id,
                    result.get("ndvi"),
                    result.get("biomass"),
                    result.get("rainfall_mm"),
                    result.get("temperature_c"),
                    result.get("elevation_m"),
                    result.get("soil_ph"),
                    result.get("live_humidity"),
                    result.get("wind_speed_ms"),
                    result.get("cloud_cover_pct"),
                    result.get("weather_description"),
                    result.get("infrastructure_suitability"),
                    result.get("infrastructure_score"),
                    result.get("infrastructure_status"),
                    result.get("infrastructure_recommendation"),
                    result.get("infrastructure_risk"),
                    result.get("slope_pct"),
                    Json(result.get("data_quality") or {}),
                ),
            )

            # 3. soil_nutrients
            cur.execute(
                """
                INSERT INTO soil_nutrients
                    (session_id, nitrogen, phosphorus, potassium, nitrogen_index_pct)
                VALUES (%s,%s,%s,%s,%s)
                """,
                (
                    session_id,
                    result.get("nitrogen"),
                    result.get("phosphorus"),
                    result.get("potassium"),
                    result.get("nitrogen_index_pct"),
                ),
            )

            # 4. crop_recommendations
            cur.execute(
                """
                INSERT INTO crop_recommendations
                    (session_id, raw_predicted_crop, predicted_crop,
                     compatibility_pct, suitability_level, is_crop_recommended,
                     land_type, land_status, recommendation_title,
                     recommendation, crop_label, crop_growth_cycle, crop_est_yield, alternative_crops, xai_explanation)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                """,
                (
                    session_id,
                    result.get("raw_predicted_crop"),
                    result.get("predicted_crop"),
                    result.get("crop_compatibility_pct"),
                    result.get("suitability_level"),
                    result.get("is_crop_recommended"),
                    result.get("land_type"),
                    result.get("land_status"),
                    result.get("recommendation_title"),
                    result.get("recommendation"),
                    result.get("crop_label"),
                    result.get("crop_growth_cycle"),
                    result.get("crop_est_yield"),
                    Json(result.get("alternative_crops") or result.get("top_crop_recommendations") or []),
                    Json(result.get("xai_explanation")) if result.get("xai_explanation") else None,
                ),
            )

        conn.commit()
        return session_id
    finally:
        conn.close()


def enrich_history_rows(rows):
    """Fill missing slope_pct for older sessions using stored coordinates."""
    try:
        from rainfallDatasets import estimate_slope_percent
    except ImportError:
        return [dict(r) for r in rows]

    enriched = []
    for row in rows:
        item = dict(row)
        if item.get("area_m2") is None and item.get("selected_polygon"):
            try:
                area_m2 = _polygon_area_m2(item.get("selected_polygon"))
                if area_m2:
                    item["area_m2"] = area_m2
                    item["area_hectares"] = area_m2 / 10000.0
            except Exception:
                pass
        if item.get("slope_pct") is None:
            lat = item.get("center_lat")
            lon = item.get("center_lon")
            if lat is not None and lon is not None:
                try:
                    item["slope_pct"] = estimate_slope_percent(
                        float(lat),
                        float(lon),
                        item.get("elevation_m"),
                    )
                except Exception:
                    pass
        enriched.append(item)
    return enriched


def get_user_history(user_id: int, limit: int = 20):
    """
    Return the last `limit` analysis sessions for a user with
    joined environmental and crop data for display.
    """
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT
                    s.id            AS session_id,
                    s.center_lat,
                    s.center_lon,
                    s.place_name,
                    s.analysis_source,
                    s.season_name,
                    s.season_advice,
                    s.intended_planting_month,
                    s.season_status,
                    s.season_adjusted_score,
                    s.environmental_suitability_pct,
                    s.recommended_planting_window,
                    s.analyzed_at,
                    s.verification_status,
                    s.verified_by,
                    s.verified_at,
                    s.planner_notes,
                    s.selected_polygon,
                    s.heatmap_grid,
                    s.area_m2,
                    s.area_hectares,
        s.analysis_summary,
                    s.analysis_summary,
                    e.ndvi,
                    e.rainfall_mm,
                    e.temperature_c,
                    e.elevation_m,
                    e.soil_ph,
                    e.live_humidity,
                    e.weather_description,
                    e.infrastructure_suitability,
                    e.infrastructure_score,
                    e.infrastructure_status,
                    e.infrastructure_recommendation,
                    e.infrastructure_risk,
                    e.slope_pct,
                    e.data_quality,
                    n.nitrogen,
                    n.phosphorus,
                    n.potassium,
                    c.predicted_crop,
                    c.compatibility_pct,
                    c.suitability_level,
                    c.is_crop_recommended,
                    c.land_status,
                    c.recommendation_title,
                    c.alternative_crops,
                    c.xai_explanation,
                    fp.farm_name
                FROM analysis_sessions s
                LEFT JOIN environmental_data  e ON e.session_id = s.id
                LEFT JOIN soil_nutrients      n ON n.session_id = s.id
                LEFT JOIN crop_recommendations c ON c.session_id = s.id
                LEFT JOIN farm_parcels        fp ON fp.id = s.farm_id
                WHERE s.user_id = %s
                ORDER BY s.analyzed_at DESC
                LIMIT %s
                """,
                (user_id, limit),
            )
            rows = cur.fetchall()
        return enrich_history_rows(rows)
    finally:
        conn.close()


def _history_select_sql(extra_select="", extra_join="", where_prefix="s.user_id = %s"):
    return f"""
                SELECT
                    s.id            AS session_id,
                    s.verification_status,
                    s.verified_by,
                    s.verified_at,
                    s.planner_notes,
                    s.center_lat,
                    s.center_lon,
                    s.place_name,
                    s.analysis_source,
                    s.season_name,
                    s.season_advice,
                    s.intended_planting_month,
                    s.season_status,
                    s.season_adjusted_score,
                    s.environmental_suitability_pct,
                    s.recommended_planting_window,
                    s.analyzed_at,
                    s.selected_polygon,
                    s.heatmap_grid,
                    s.area_m2,
                    s.area_hectares,
        s.analysis_summary,
                    s.analysis_summary,
                    e.ndvi,
                    e.rainfall_mm,
                    e.temperature_c,
                    e.elevation_m,
                    e.soil_ph,
                    e.live_humidity,
                    e.weather_description,
                    e.infrastructure_suitability,
                    e.infrastructure_score,
                    e.infrastructure_status,
                    e.infrastructure_recommendation,
                    e.infrastructure_risk,
                    e.slope_pct,
                    e.data_quality,
                    n.nitrogen,
                    n.phosphorus,
                    n.potassium,
                    c.predicted_crop,
                    c.compatibility_pct,
                    c.suitability_level,
                    c.is_crop_recommended,
                    c.land_status,
                    c.recommendation_title,
                    c.alternative_crops,
                    c.xai_explanation,
                    fp.farm_name
                    {extra_select}
                FROM analysis_sessions s
                LEFT JOIN environmental_data  e ON e.session_id = s.id
                LEFT JOIN soil_nutrients      n ON n.session_id = s.id
                LEFT JOIN crop_recommendations c ON c.session_id = s.id
                LEFT JOIN farm_parcels        fp ON fp.id = s.farm_id
                {extra_join}
                WHERE {where_prefix}
                ORDER BY s.analyzed_at DESC
            """



def submit_analysis_to_planner(user_id: int, session_id: int):
    """Submit a farmer-owned draft/rejected analysis to the planner queue."""
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE analysis_sessions
                SET verification_status = 'pending',
                    verified_by = NULL,
                    verified_at = NULL,
                    planner_notes = NULL
                WHERE id = %s
                  AND user_id = %s
                  AND verification_status IN ('draft', 'rejected')
                RETURNING id, verification_status, analyzed_at
                """,
                (session_id, user_id),
            )
            row = cur.fetchone()
        conn.commit()
        return dict(row) if row else None
    finally:
        conn.close()

def save_analysis_for_user(user_id: int, session_id: int):
    """Bookmark/save an existing analysis session for a specific user."""
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO saved_analyses (user_id, session_id)
                SELECT %s, %s
                WHERE EXISTS (SELECT 1 FROM analysis_sessions WHERE id = %s AND user_id = %s)
                ON CONFLICT (user_id, session_id) DO NOTHING
                RETURNING id, user_id, session_id, saved_at
                """,
                (user_id, session_id, session_id, user_id),
            )
            row = cur.fetchone()
        conn.commit()
        return dict(row) if row else {"user_id": user_id, "session_id": session_id, "already_saved": True}
    finally:
        conn.close()


def create_report_for_user(user_id: int, session_id: int, title: str = None):
    """Create or keep a report record for an existing analysis session."""
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO reports (user_id, session_id, report_title)
                SELECT %s, %s, COALESCE(%s, 'GeoSustain Land Suitability Report')
                WHERE EXISTS (SELECT 1 FROM analysis_sessions WHERE id = %s AND user_id = %s)
                ON CONFLICT (user_id, session_id) DO NOTHING
                RETURNING id, user_id, session_id, report_title, created_at
                """,
                (user_id, session_id, title, session_id, user_id),
            )
            row = cur.fetchone()
        conn.commit()
        return dict(row) if row else {"user_id": user_id, "session_id": session_id, "already_reported": True}
    finally:
        conn.close()


def get_saved_analyses(user_id: int, limit: int = 50):
    """Return saved/bookmarked analyses for a user."""
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                _history_select_sql(
                    extra_select=", sv.saved_at",
                    extra_join="INNER JOIN saved_analyses sv ON sv.session_id = s.id AND sv.user_id = s.user_id",
                    where_prefix="s.user_id = %s",
                ) + " LIMIT %s",
                (user_id, limit),
            )
            rows = cur.fetchall()
        return enrich_history_rows(rows)
    finally:
        conn.close()


def get_reports(user_id: int, limit: int = 50):
    """Return generated report records for a user."""
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                _history_select_sql(
                    extra_select=", rp.id AS report_id, rp.report_title, rp.created_at AS report_created_at",
                    extra_join="INNER JOIN reports rp ON rp.session_id = s.id AND rp.user_id = s.user_id",
                    where_prefix="s.user_id = %s",
                ) + " LIMIT %s",
                (user_id, limit),
            )
            rows = cur.fetchall()
        return enrich_history_rows(rows)
    finally:
        conn.close()


def get_user_counts(user_id: int):
    """Return real per-user profile counts from PostgreSQL."""
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT
                    (SELECT COUNT(*) FROM analysis_sessions WHERE user_id = %s) AS analysis_count,
                    (SELECT COUNT(*) FROM saved_analyses WHERE user_id = %s) AS saved_count,
                    (SELECT COUNT(*) FROM reports WHERE user_id = %s) AS report_count
                """,
                (user_id, user_id, user_id),
            )
            row = cur.fetchone()
        return dict(row) if row else {"analysis_count": 0, "saved_count": 0, "report_count": 0}
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# Planner verification workflow
# ---------------------------------------------------------------------------
_PLANNER_SESSION_SELECT = """
    SELECT
        s.id                AS session_id,
        s.center_lat,
        s.center_lon,
        s.place_name,
        s.analysis_source,
        s.season_name,
        s.season_advice,
        s.intended_planting_month,
        s.season_status,
        s.season_adjusted_score,
        s.environmental_suitability_pct,
        s.recommended_planting_window,
        s.analyzed_at,
        s.verification_status,
        s.verified_by,
        s.verified_at,
        s.planner_notes,
        s.selected_polygon,
        s.heatmap_grid,
        s.area_m2,
        s.area_hectares,
        s.analysis_summary,
        u.id                AS farmer_id,
        u.username          AS farmer_name,
        u.email             AS farmer_email,
        u.role              AS farmer_role,
        e.ndvi,
        e.rainfall_mm,
        e.temperature_c,
        e.elevation_m,
        e.soil_ph,
        e.live_humidity,
        e.weather_description,
        e.infrastructure_suitability,
        e.infrastructure_score,
        e.infrastructure_status,
        e.infrastructure_recommendation,
        e.infrastructure_risk,
        e.slope_pct,
        e.data_quality,
        n.nitrogen,
        n.phosphorus,
        n.potassium,
        c.predicted_crop,
        c.compatibility_pct,
        c.suitability_level,
        c.is_crop_recommended,
        c.land_status,
        c.recommendation_title,
        c.recommendation,
        c.alternative_crops,
        c.xai_explanation,
        fp.farm_name
    FROM analysis_sessions s
    LEFT JOIN users               u ON u.id = s.user_id
    LEFT JOIN environmental_data  e ON e.session_id = s.id
    LEFT JOIN soil_nutrients      n ON n.session_id = s.id
    LEFT JOIN crop_recommendations c ON c.session_id = s.id
    LEFT JOIN farm_parcels        fp ON fp.id = s.farm_id
"""


def get_planner_queue(status: str = "pending", limit: int = 100):
    """
    Return analyzed land sessions for the planner to review, joined with the
    submitting farmer's basic info. `status` can be 'pending', 'verified',
    'rejected', or 'all'.
    """
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            farmer_only = " WHERE LOWER(COALESCE(u.role, 'farmer')) = 'farmer' "
            if status == "all":
                cur.execute(
                    _PLANNER_SESSION_SELECT + farmer_only + " ORDER BY s.analyzed_at DESC LIMIT %s",
                    (limit,),
                )
            else:
                cur.execute(
                    _PLANNER_SESSION_SELECT
                    + farmer_only
                    + " AND s.verification_status = %s ORDER BY s.analyzed_at DESC LIMIT %s",
                    (status, limit),
                )
            rows = cur.fetchall()
        return enrich_history_rows(rows)
    finally:
        conn.close()


def get_planner_session_detail(session_id: int):
    """Return a single FARMER-submitted session for the planner's detail view.

    SECURITY: only sessions that are actually in the review pipeline
    (pending/verified/rejected) and belong to a Farmer are returned. A
    Farmer's still-private `draft` session (never submitted) must never be
    visible to an Analyst just by guessing/incrementing a session id.
    """
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                _PLANNER_SESSION_SELECT
                + " WHERE s.id = %s"
                + " AND LOWER(COALESCE(u.role, 'farmer')) = 'farmer'"
                + " AND s.verification_status IN ('pending', 'verified', 'rejected')",
                (session_id,),
            )
            row = cur.fetchone()
        return enrich_history_rows([row])[0] if row else None
    finally:
        conn.close()


def verify_analysis_session(session_id: int, planner_id: int, status: str, notes: str = None):
    """
    Approve or reject a farmer's analyzed land submission.
    `status` must be 'verified' or 'rejected'.
    Returns the updated session row, or None if the session doesn't exist
    or isn't currently awaiting review.

    SECURITY: only a session that is a Farmer's and is currently `pending`
    can be verified/rejected. This stops an Analyst from directly flipping
    a Farmer's still-private `draft` (never submitted) straight to a
    decision, and from re-deciding a session that already has a decision.
    """
    if status not in ("verified", "rejected", "pending"):
        raise ValueError("status must be 'verified', 'rejected', or 'pending'")
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE analysis_sessions AS s
                SET verification_status = %s,
                    verified_by = %s,
                    verified_at = NOW(),
                    planner_notes = %s
                FROM users AS u
                WHERE s.id = %s
                  AND s.user_id = u.id
                  AND LOWER(COALESCE(u.role, 'farmer')) = 'farmer'
                  AND s.verification_status = 'pending'
                RETURNING s.id
                """,
                (status, planner_id, notes, session_id),
            )
            row = cur.fetchone()
        conn.commit()
        if not row:
            return None
        write_audit_log(
            planner_id, 'agricultural_planning_analyst', 'verification_decision',
            target_type='analysis_session', target_id=session_id,
            details={'decision': status, 'has_notes': bool(notes)},
        )
        return get_planner_session_detail(session_id)
    finally:
        conn.close()


def get_planner_queue_counts():
    """Return counts of sessions by verification status, for a planner's dashboard summary."""
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT
                    COUNT(*) FILTER (WHERE verification_status = 'pending')  AS pending_count,
                    COUNT(*) FILTER (WHERE verification_status = 'verified') AS verified_count,
                    COUNT(*) FILTER (WHERE verification_status = 'rejected') AS rejected_count
                FROM analysis_sessions s
                INNER JOIN users u ON u.id = s.user_id
                WHERE LOWER(COALESCE(u.role, 'farmer')) = 'farmer'
                """
            )
            row = cur.fetchone()
        return dict(row) if row else {"pending_count": 0, "verified_count": 0, "rejected_count": 0}
    finally:
        conn.close()



# ---------------------------------------------------------------------------
# Super Administrator queries
# ---------------------------------------------------------------------------
def admin_dashboard_stats():
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                  COUNT(*) FILTER (WHERE LOWER(role)='farmer') AS farmers,
                  COUNT(*) FILTER (WHERE LOWER(role) IN ('analyst','planner','agricultural_planning_analyst')) AS planning_analysts,
                  COUNT(*) FILTER (WHERE LOWER(role) IN ('admin','super_admin')) AS super_admins,
                  COUNT(*) FILTER (WHERE is_active) AS active_users,
                  COUNT(*) FILTER (WHERE NOT is_active) AS inactive_users
                FROM users
            """)
            users = dict(cur.fetchone() or {})
            cur.execute("""
                SELECT COUNT(*) AS total_analyses,
                       COUNT(*) FILTER (WHERE verification_status='pending') AS pending,
                       COUNT(*) FILTER (WHERE verification_status='verified') AS verified,
                       COUNT(*) FILTER (WHERE verification_status='rejected') AS rejected,
                       COUNT(*) FILTER (WHERE selected_polygon IS NOT NULL) AS registered_parcels,
                       COALESCE(SUM(area_hectares) FILTER (WHERE area_hectares IS NOT NULL),0) AS total_area_hectares
                FROM analysis_sessions
            """)
            analyses = dict(cur.fetchone() or {})
            return {**users, **analyses}


def admin_list_users(limit: int = 200):
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT id, username, email, role, location, is_active, email_verified,
                       auth_provider, created_at, updated_at
                FROM users ORDER BY created_at DESC LIMIT %s
            """, (limit,))
            return [dict(r) for r in cur.fetchall()]


def write_audit_log(actor_user_id, actor_role, action, target_type=None, target_id=None, details=None):
    """Record a security-sensitive action (role change, account status change,
    verification decision) for the Super Administrator's audit view.
    Best-effort: never raises — a logging failure must not block the
    underlying action it is describing."""
    try:
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO audit_logs (actor_user_id, actor_role, action, target_type, target_id, details)
                    VALUES (%s, %s, %s, %s, %s, %s)
                    """,
                    (actor_user_id, actor_role, action, target_type, target_id, Json(details or {})),
                )
                conn.commit()
    except Exception as exc:
        print(f"Audit log write failed (non-fatal): {exc}")


def get_audit_logs(limit: int = 200):
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT a.id, a.action, a.target_type, a.target_id, a.details, a.created_at,
                       a.actor_role, u.username AS actor_username, u.email AS actor_email
                FROM audit_logs a
                LEFT JOIN users u ON u.id = a.actor_user_id
                ORDER BY a.created_at DESC
                LIMIT %s
                """,
                (limit,),
            )
            return [dict(r) for r in cur.fetchall()]


def admin_update_user(user_id: int, role=None, is_active=None, actor_user_id=None, actor_role=None):
    """Super Administrator-only role/status change (caller is gated by
    require_super_admin in fastapi_app.py). Only the three finalized
    GeoSustain roles are assignable going forward — legacy synonyms
    (analyst/planner/admin) are still accepted as *input* for backward
    compatibility with older admin UI builds, but are normalized to their
    canonical value before being written, so the database never gains a new
    non-canonical role value from this point on."""
    allowed = {'farmer', 'agricultural_planning_analyst', 'super_admin'}
    legacy_aliases = {
        'analyst': 'agricultural_planning_analyst',
        'planner': 'agricultural_planning_analyst',
        'admin': 'super_admin',
    }
    before = get_user_by_id(user_id)
    sets=[]; vals=[]
    if role is not None:
        role=str(role).strip().lower()
        role = legacy_aliases.get(role, role)
        if role not in allowed:
            raise ValueError('Unsupported role')
        sets.append('role=%s'); vals.append(role)
    if is_active is not None:
        sets.append('is_active=%s'); vals.append(bool(is_active))
    if not sets:
        return get_user_by_id(user_id)
    sets.append('updated_at=NOW()'); vals.append(user_id)
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(f"UPDATE users SET {', '.join(sets)} WHERE id=%s RETURNING id,username,email,role,location,is_active,email_verified,auth_provider,created_at,updated_at", tuple(vals))
            row=cur.fetchone(); conn.commit()
    updated = dict(row) if row else None
    if updated and before:
        details = {}
        if role is not None and before.get('role') != updated.get('role'):
            details['role'] = {'from': before.get('role'), 'to': updated.get('role')}
        if is_active is not None and before.get('is_active') != updated.get('is_active'):
            details['is_active'] = {'from': before.get('is_active'), 'to': updated.get('is_active')}
        if details:
            write_audit_log(
                actor_user_id, actor_role, 'user_update',
                target_type='user', target_id=user_id,
                details={**details, 'target_username': updated.get('username')},
            )
    return updated


def admin_list_analyses(limit: int = 200):
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT s.id AS session_id, s.place_name, s.analysis_source, s.analyzed_at,
                       s.verification_status, s.area_hectares, s.center_lat, s.center_lon,
                       u.id AS user_id, u.username, u.email, u.role,
                       c.predicted_crop, c.crop_compatibility_pct
                FROM analysis_sessions s
                LEFT JOIN users u ON u.id=s.user_id
                LEFT JOIN crop_recommendations c ON c.session_id=s.id
                ORDER BY s.analyzed_at DESC LIMIT %s
            """, (limit,))
            return [dict(r) for r in cur.fetchall()]


# ---------------------------------------------------------------------------
# Super Administrator: crop reference management (Section 17)
# ---------------------------------------------------------------------------
def list_crop_reference():
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM crop_reference ORDER BY label ASC")
            return [dict(r) for r in cur.fetchall()]


def get_active_crop_keys():
    """Returns the set of crop_key values currently marked active. Used to
    let a Super Administrator temporarily remove a crop from recommendations
    (e.g. a seed/seedling shortage) WITHOUT touching the approved crop list
    in code (Section 9) or its scoring — this can only ever narrow the
    approved set, never add to it. Fails open (returns None, meaning "no
    restriction") on any DB error so a transient admin-table hiccup never
    blocks Farmer analysis."""
    try:
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT crop_key FROM crop_reference WHERE is_active = TRUE")
                keys = {r['crop_key'] for r in cur.fetchall()}
                return keys if keys else None
    except Exception as exc:
        print(f"get_active_crop_keys failed, defaulting to unrestricted: {exc}")
        return None


def update_crop_reference(crop_key: str, label=None, growth_cycle=None, est_yield=None,
                           suitability_note=None, is_active=None, actor_user_id=None, actor_role=None):
    """Super Administrator-only. Editing only ever changes DISPLAY metadata
    and the active/inactive toggle for one of the finalized approved crops —
    it cannot add a new crop_key (no INSERT path here) or change the
    environmental scoring ranges, so this cannot be used to reintroduce an
    unapproved crop or corrupt the ML-adjacent scoring logic."""
    sets = []; vals = []
    for col, val in [('label', label), ('growth_cycle', growth_cycle), ('est_yield', est_yield),
                      ('suitability_note', suitability_note)]:
        if val is not None:
            sets.append(f"{col}=%s"); vals.append(val)
    if is_active is not None:
        sets.append('is_active=%s'); vals.append(bool(is_active))
    if not sets:
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT * FROM crop_reference WHERE crop_key=%s", (crop_key,))
                row = cur.fetchone()
                return dict(row) if row else None
    sets.append('updated_by=%s'); vals.append(actor_user_id)
    sets.append('updated_at=NOW()')
    vals.append(crop_key)
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                f"UPDATE crop_reference SET {', '.join(sets)} WHERE crop_key=%s RETURNING *",
                tuple(vals),
            )
            row = cur.fetchone()
            conn.commit()
    updated = dict(row) if row else None
    if updated:
        write_audit_log(
            actor_user_id, actor_role, 'crop_reference_update',
            target_type='crop_reference', target_id=updated.get('id'),
            details={'crop_key': crop_key, 'is_active': updated.get('is_active')},
        )
    return updated


# ---------------------------------------------------------------------------
# Farm parcel management
# ---------------------------------------------------------------------------
def create_farm_parcel(farmer_id: int, farm_name: str, polygon, location_name=None,
                       mapping_method='manual_draw', gps_accuracy_m=None):
    area_m2 = _polygon_area_m2(polygon or [])
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO farm_parcels
                    (farmer_id, farm_name, location_name, polygon, area_m2, area_hectares,
                     mapping_method, gps_accuracy_m)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s)
                RETURNING *
            """, (farmer_id, farm_name.strip(), location_name, Json(polygon or []),
                  area_m2, area_m2 / 10000.0 if area_m2 else None,
                  mapping_method, gps_accuracy_m))
            row = cur.fetchone()
        conn.commit()
        return dict(row) if row else None
    finally:
        conn.close()


def list_farm_parcels(farmer_id: int, include_archived=False):
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT f.*,
                       (SELECT COUNT(*) FROM analysis_sessions s WHERE s.farm_id=f.id) AS analysis_count,
                       (SELECT MAX(s.analyzed_at) FROM analysis_sessions s WHERE s.farm_id=f.id) AS last_analyzed_at,
                       latest.verification_status AS latest_verification_status,
                       latest.predicted_crop AS latest_predicted_crop
                FROM farm_parcels f
                LEFT JOIN LATERAL (
                    SELECT s.verification_status, c.predicted_crop
                    FROM analysis_sessions s
                    LEFT JOIN crop_recommendations c ON c.session_id = s.id
                    WHERE s.farm_id = f.id
                    ORDER BY s.analyzed_at DESC
                    LIMIT 1
                ) latest ON TRUE
                WHERE f.farmer_id=%s AND (%s OR f.is_archived=FALSE)
                ORDER BY f.updated_at DESC
            """, (farmer_id, include_archived))
            return [dict(r) for r in cur.fetchall()]
    finally:
        conn.close()


def get_farm_parcel(farmer_id: int, farm_id: int):
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM farm_parcels WHERE id=%s AND farmer_id=%s", (farm_id, farmer_id))
            row=cur.fetchone()
            return dict(row) if row else None
    finally:
        conn.close()


def update_farm_parcel(farmer_id: int, farm_id: int, **changes):
    allowed={'farm_name','location_name','polygon','mapping_method','gps_accuracy_m','is_archived'}
    data={k:v for k,v in changes.items() if k in allowed and v is not None}
    if 'polygon' in data:
        area=_polygon_area_m2(data['polygon'] or [])
        data['area_m2']=area
        data['area_hectares']=area/10000.0 if area else None
        data['polygon']=Json(data['polygon'] or [])
        allowed |= {'area_m2','area_hectares'}
    if not data:
        return get_farm_parcel(farmer_id, farm_id)
    sets=', '.join(f"{k}=%s" for k in data)
    vals=list(data.values())+[farm_id,farmer_id]
    conn=get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(f"UPDATE farm_parcels SET {sets}, updated_at=NOW() WHERE id=%s AND farmer_id=%s RETURNING *", vals)
            row=cur.fetchone()
        conn.commit()
        return dict(row) if row else None
    finally:
        conn.close()


def attach_analysis_to_farm(session_id: int, farmer_id: int, farm_id: int):
    conn=get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute("""UPDATE analysis_sessions s SET farm_id=%s
                           WHERE s.id=%s AND s.user_id=%s
                             AND EXISTS (SELECT 1 FROM farm_parcels f WHERE f.id=%s AND f.farmer_id=%s)
                           RETURNING id""", (farm_id,session_id,farmer_id,farm_id,farmer_id))
            row=cur.fetchone()
        conn.commit()
        return bool(row)
    finally:
        conn.close()


def get_climate_baseline(lat: float, lon: float, month: int):
    lk=round(float(lat),2); ok=round(float(lon),2)
    conn=get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute("""SELECT * FROM climate_monthly_baselines
                           WHERE latitude_key=%s AND longitude_key=%s AND month_number=%s""",(lk,ok,month))
            row=cur.fetchone(); return dict(row) if row else None
    finally: conn.close()


def save_climate_baseline(lat: float, lon: float, month: int, values: dict):
    lk=round(float(lat),2); ok=round(float(lon),2)
    conn=get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute("""
              INSERT INTO climate_monthly_baselines
                (latitude_key,longitude_key,month_number,mean_temperature_c,mean_rainfall_mm,
                 mean_humidity_pct,baseline_start_year,baseline_end_year,source_name)
              VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)
              ON CONFLICT(latitude_key,longitude_key,month_number) DO UPDATE SET
                mean_temperature_c=EXCLUDED.mean_temperature_c,
                mean_rainfall_mm=EXCLUDED.mean_rainfall_mm,
                mean_humidity_pct=EXCLUDED.mean_humidity_pct,
                baseline_start_year=EXCLUDED.baseline_start_year,
                baseline_end_year=EXCLUDED.baseline_end_year,
                source_name=EXCLUDED.source_name,
                fetched_at=NOW()
              RETURNING *
            """,(lk,ok,month,values.get('mean_temperature_c'),values.get('mean_rainfall_mm'),
                 values.get('mean_humidity_pct'),values.get('baseline_start_year'),values.get('baseline_end_year'),
                 values.get('source_name','NASA POWER')))
            row=cur.fetchone()
        conn.commit(); return dict(row) if row else None
    finally: conn.close()
