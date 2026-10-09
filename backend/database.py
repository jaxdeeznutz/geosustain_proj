import os
from contextlib import contextmanager
import config  # noqa: F401 -- load local environment before reading settings
import psycopg2
from psycopg2.extras import RealDictCursor, Json
from geometry import normalize_polygon, polygon_area_m2

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
            cur.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS password_version INTEGER NOT NULL DEFAULT 0")
            cur.execute("ALTER TABLE farm_parcels ADD COLUMN IF NOT EXISTS boundary_version INTEGER NOT NULL DEFAULT 1")
            cur.execute("ALTER TABLE farm_parcels ADD COLUMN IF NOT EXISTS request_key VARCHAR(128)")
            cur.execute("ALTER TABLE farm_parcels ADD COLUMN IF NOT EXISTS request_hash VARCHAR(64)")
            cur.execute("ALTER TABLE analysis_sessions ADD COLUMN IF NOT EXISTS result_snapshot JSONB")
            cur.execute("ALTER TABLE analysis_sessions ADD COLUMN IF NOT EXISTS farm_name_snapshot VARCHAR(160)")
            cur.execute("ALTER TABLE analysis_sessions ADD COLUMN IF NOT EXISTS boundary_version INTEGER")
            cur.execute("ALTER TABLE analysis_sessions ADD COLUMN IF NOT EXISTS submitted_at TIMESTAMPTZ")
            cur.execute("ALTER TABLE analysis_sessions ADD COLUMN IF NOT EXISTS request_key VARCHAR(128)")
            cur.execute("ALTER TABLE analysis_sessions ADD COLUMN IF NOT EXISTS request_hash VARCHAR(64)")
            cur.execute("CREATE UNIQUE INDEX IF NOT EXISTS farm_request_unique ON farm_parcels (farmer_id, request_key) WHERE request_key IS NOT NULL")
            cur.execute("CREATE UNIQUE INDEX IF NOT EXISTS analysis_request_unique ON analysis_sessions (user_id, request_key) WHERE request_key IS NOT NULL")
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
    """Create an account; only an actual duplicate email returns None."""
    normalized_email = email.strip().lower()
    conn = get_conn()
    try:
        for attempt in range(2):
            try:
                with conn.cursor() as cur:
                    # Serialize normalized-email retries on legacy schemas too.
                    cur.execute("SELECT pg_advisory_xact_lock(hashtextextended(%s, 0))", ('register:' + normalized_email,))
                    cur.execute("SELECT id FROM users WHERE LOWER(BTRIM(email))=%s", (normalized_email,))
                    if cur.fetchone():
                        return None
                    cur.execute(
                        """
                        INSERT INTO users (username, email, password_hash, role, email_verified, auth_provider, google_sub)
                        VALUES (%s, %s, %s, %s, %s, %s, %s)
                        RETURNING id, username, email, role, location, profile_photo, is_active, email_verified, auth_provider, created_at
                        """,
                        (username.strip(), normalized_email, password_hash, role, email_verified, auth_provider, google_sub),
                    )
                    user = cur.fetchone()
                conn.commit()
                return dict(user)
            except psycopg2.errors.UniqueViolation as exc:
                conn.rollback()
                with conn.cursor() as cur:
                    cur.execute("SELECT contype FROM pg_constraint WHERE conrelid='users'::regclass AND conname=%s", (exc.diag.constraint_name,))
                    constraint = cur.fetchone()
                    if attempt == 0 and constraint and constraint['contype'] == 'p':
                        # Explicitly imported IDs can leave the SERIAL/IDENTITY
                        # sequence behind existing users. Block concurrent INSERTs
                        # during repair; advance it without changing any user row.
                        cur.execute("LOCK TABLE users IN SHARE ROW EXCLUSIVE MODE")
                        cur.execute("SELECT pg_get_serial_sequence('users', 'id') AS sequence_name")
                        sequence = cur.fetchone()['sequence_name']
                        if sequence:
                            cur.execute(
                                "SELECT setval(%s::regclass, GREATEST(COALESCE(MAX(id), 0), nextval(%s::regclass)), true) FROM users",
                                (sequence, sequence),
                            )
                            conn.commit()
                            continue
                    cur.execute("SELECT id FROM users WHERE LOWER(BTRIM(email))=%s", (normalized_email,))
                    if cur.fetchone():
                        return None
                # A different unique constraint is a server/schema issue, not
                # evidence that this email belongs to an existing account.
                raise
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
    updates = []
    values = []
    if username:
        updates.append("username = %s")
        values.append(username)
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

def validate_farm_polygon(polygon):
    try:
        normalize_polygon(polygon)
        return True, None
    except ValueError as exc:
        return False, str(exc)


def _polygon_area_m2(polygon):
    if not polygon:
        return None
    return polygon_area_m2(polygon)


def save_analysis_session(user_id, result: dict, analysis_source: str, request_key=None, request_hash=None):
    """
    Persist a full analysis result across the four related tables.
    Returns the new session_id.
    """
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            # 1. analysis_sessions
            if request_key:
                cur.execute("SELECT pg_advisory_xact_lock(hashtextextended(%s, 0))", (f'analysis:{user_id}:{request_key}',))
                cur.execute("SELECT id, request_hash FROM analysis_sessions WHERE user_id=%s AND request_key=%s", (user_id,request_key))
                prior=cur.fetchone()
                if prior:
                    if prior['request_hash'] != request_hash:
                        raise ValueError('This retry key was already used for different analysis inputs.')
                    return prior['id']
            farm_id = result.get('farm_id')
            if farm_id:
                cur.execute("SELECT boundary_version FROM farm_parcels WHERE id=%s AND farmer_id=%s AND is_archived=FALSE FOR SHARE", (farm_id,user_id))
                farm=cur.fetchone()
                if not farm or farm['boundary_version'] != result.get('boundary_version'):
                    raise ValueError('Farm boundary changed or is no longer available. Reload the farm before analyzing.')
            cur.execute(
                """
                INSERT INTO analysis_sessions
                    (user_id, center_lat, center_lon, place_name, analysis_source,
                     season_name, season_advice, intended_planting_month, season_status,
                     season_adjusted_score, environmental_suitability_pct, recommended_planting_window,
                     selected_polygon, heatmap_grid, area_m2, area_hectares, analysis_summary,
                     farm_id, farm_name_snapshot, boundary_version, result_snapshot, request_key, request_hash)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                        %s, %s, %s, %s, %s, %s)
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
                    farm_id, result.get('farm_name'), result.get('boundary_version'), Json(result), request_key, request_hash,
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
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
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
    """Restore persisted results without fetching today's values for historic runs."""
    enriched = []
    for row in rows:
        item = dict(row)
        snapshot = item.pop('result_snapshot', None) or {}
        restored = dict(snapshot)
        restored.update(item)
        restored['analysis_status'] = 'completed'
        restored['lat'] = restored.get('center_lat')
        restored['lon'] = restored.get('center_lon')
        restored['crop_compatibility_pct'] = restored.get('compatibility_pct', snapshot.get('crop_compatibility_pct'))
        enriched.append(restored)
    return enriched


def get_user_history(user_id: int, limit: int = 20, offset: int = 0, farm_id=None):
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            where = 's.user_id = %s'
            params = [user_id]
            if farm_id is not None:
                where += ' AND s.farm_id = %s'
                params.append(farm_id)
            cur.execute(_history_select_sql(where_prefix=where) + ' LIMIT %s OFFSET %s', (*params, limit, offset))
            return enrich_history_rows(cur.fetchall())
    finally:
        conn.close()


def get_user_analysis(user_id: int, session_id: int):
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(_history_select_sql(where_prefix='s.user_id = %s AND s.id = %s'), (user_id, session_id))
            row = cur.fetchone()
            return enrich_history_rows([row])[0] if row else None
    finally:
        conn.close()


def find_analysis_request(user_id, key, request_hash):
    if not key:
        return None
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute('SELECT id, request_hash FROM analysis_sessions WHERE user_id=%s AND request_key=%s', (user_id,key))
            row=cur.fetchone()
            if not row:
                return None
            if row['request_hash'] != request_hash:
                raise ValueError('This retry key was already used for different analysis inputs.')
            return get_user_analysis(user_id,row['id'])
    finally:
        conn.close()


def change_user_password(user_id, old_hash, new_hash):
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute('UPDATE users SET password_hash=%s, password_version=password_version+1, updated_at=NOW() WHERE id=%s AND password_hash=%s AND is_active=TRUE RETURNING *', (new_hash,user_id,old_hash))
            row=cur.fetchone()
        conn.commit()
        return dict(row) if row else None
    finally:
        conn.close()


@contextmanager
def analysis_request_lock(user_id, key):
    """One live computation per retry key, across API processes. Crash-safe PG lock."""
    if not key:
        yield True
        return
    conn = get_conn()
    conn.autocommit = True
    lock_name = f'analysis-running:{user_id}:{key}'
    acquired = False
    try:
        with conn.cursor() as cur:
            cur.execute('SELECT pg_try_advisory_lock(hashtextextended(%s, 0)) AS acquired', (lock_name,))
            acquired = cur.fetchone()['acquired']
        yield acquired
    finally:
        try:
            if acquired:
                with conn.cursor() as cur:
                    cur.execute('SELECT pg_advisory_unlock(hashtextextended(%s, 0))', (lock_name,))
        finally:
            conn.close()


def analysis_request_status(user_id, key):
    # A free lock means no server worker still owns this request. Check the
    # completed row after acquiring it, to avoid a completion/check race.
    with analysis_request_lock(user_id, key) as available:
        if not available:
            return {'status': 'processing'}
        conn = get_conn()
        try:
            with conn.cursor() as cur:
                cur.execute('SELECT id FROM analysis_sessions WHERE user_id=%s AND request_key=%s', (user_id, key))
                row = cur.fetchone()
            if row:
                return {'status': 'completed', 'analysis': get_user_analysis(user_id, row['id'])}
            return {'status': 'not_found'}
        finally:
            conn.close()


def _history_select_sql(extra_select="", extra_join="", where_prefix="s.user_id = %s"):
    return f"""
                SELECT
                    s.id            AS session_id,
                    s.user_id AS owner_id, owner.username AS owner_display_name,
                    s.farm_id, s.boundary_version, s.submitted_at, s.result_snapshot,
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
                    c.recommendation, c.crop_label, c.crop_growth_cycle, c.crop_est_yield,
                    c.alternative_crops,
                    c.xai_explanation,
                    COALESCE(s.farm_name_snapshot, fp.farm_name) AS farm_name
                    {extra_select}
                FROM analysis_sessions s
                LEFT JOIN environmental_data  e ON e.session_id = s.id
                LEFT JOIN soil_nutrients      n ON n.session_id = s.id
                LEFT JOIN crop_recommendations c ON c.session_id = s.id
                LEFT JOIN farm_parcels        fp ON fp.id = s.farm_id AND fp.farmer_id = s.user_id
                LEFT JOIN users owner ON owner.id = s.user_id
                {extra_join}
                WHERE {where_prefix}
                ORDER BY s.analyzed_at DESC
            """



def submit_analysis_to_planner(user_id: int, session_id: int):
    """Submit once; retries return the current review without erasing decisions."""
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE analysis_sessions
                SET verification_status = 'pending',
                    submitted_at = NOW()
                WHERE id = %s
                  AND user_id = %s
                  AND verification_status = 'draft'
                  AND EXISTS (SELECT 1 FROM users WHERE id=%s AND role='farmer')
                RETURNING id, verification_status, analyzed_at
                """,
                (session_id, user_id, user_id),
            )
            row = cur.fetchone()
            if not row:
                cur.execute("""SELECT id, verification_status, analyzed_at, planner_notes, verified_at
                               FROM analysis_sessions WHERE id=%s AND user_id=%s
                               AND verification_status IN ('pending','verified','rejected')""", (session_id,user_id))
                row=cur.fetchone()
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
        s.farm_id, s.boundary_version, s.submitted_at, s.result_snapshot,
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
        COALESCE(s.farm_name_snapshot, fp.farm_name) AS farm_name
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
            farmer_only = " WHERE LOWER(COALESCE(u.role, 'farmer')) = 'farmer' AND s.verification_status IN ('pending','verified','rejected') "
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
                       mapping_method='manual_draw', gps_accuracy_m=None, request_key=None, request_hash=None):
    polygon = normalize_polygon(polygon)
    area_m2 = _polygon_area_m2(polygon or [])
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            if request_key:
                cur.execute("SELECT pg_advisory_xact_lock(hashtextextended(%s, 0))", (f'farm:{farmer_id}:{request_key}',))
                cur.execute("SELECT * FROM farm_parcels WHERE farmer_id=%s AND request_key=%s", (farmer_id,request_key))
                prior=cur.fetchone()
                if prior:
                    if prior['request_hash'] != request_hash:
                        raise ValueError('This retry key was already used for different farm inputs.')
                    return dict(prior)
            cur.execute("""
                INSERT INTO farm_parcels
                    (farmer_id, farm_name, location_name, polygon, area_m2, area_hectares,
                     mapping_method, gps_accuracy_m, request_key, request_hash)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                RETURNING *
            """, (farmer_id, farm_name.strip(), location_name, Json(polygon or []),
                  area_m2, area_m2 / 10000.0 if area_m2 else None,
                  mapping_method, gps_accuracy_m, request_key, request_hash))
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
                SELECT f.*, (SELECT username FROM users WHERE id=f.farmer_id) AS owner_display_name,
                       (SELECT COUNT(*) FROM analysis_sessions s WHERE s.farm_id=f.id AND s.user_id=f.farmer_id) AS analysis_count,
                       (SELECT MAX(s.analyzed_at) FROM analysis_sessions s WHERE s.farm_id=f.id AND s.user_id=f.farmer_id) AS last_analyzed_at,
                       latest.verification_status AS latest_verification_status,
                       latest.id AS latest_analysis_id,
                       latest.analyzed_at AS latest_analysis_date,
                       latest.verification_status AS latest_review_status,
                       latest.predicted_crop AS latest_predicted_crop
                FROM farm_parcels f
                LEFT JOIN LATERAL (
                    SELECT s.id, s.analyzed_at, s.verification_status, c.predicted_crop
                    FROM analysis_sessions s
                    LEFT JOIN crop_recommendations c ON c.session_id = s.id
                    WHERE s.farm_id = f.id AND s.user_id = f.farmer_id
                    ORDER BY s.analyzed_at DESC, s.id DESC
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
            cur.execute("SELECT f.*, (SELECT username FROM users WHERE id=f.farmer_id) AS owner_display_name FROM farm_parcels f WHERE f.id=%s AND f.farmer_id=%s", (farm_id, farmer_id))
            row=cur.fetchone()
            return dict(row) if row else None
    finally:
        conn.close()


def update_farm_parcel(farmer_id: int, farm_id: int, **changes):
    allowed={'farm_name','location_name','polygon','mapping_method','gps_accuracy_m','is_archived'}
    data={k:v for k,v in changes.items() if k in allowed and v is not None}
    if 'polygon' in data:
        data['polygon']=normalize_polygon(data['polygon'])
        area=_polygon_area_m2(data['polygon'] or [])
        data['area_m2']=area
        data['area_hectares']=area/10000.0 if area else None
        data['polygon']=Json(data['polygon'] or [])
        allowed |= {'area_m2','area_hectares'}
    if not data:
        return get_farm_parcel(farmer_id, farm_id)
    sets=', '.join(f"{k}=%s" for k in data)
    if 'polygon' in data:
        sets += ', boundary_version=boundary_version+1'
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
