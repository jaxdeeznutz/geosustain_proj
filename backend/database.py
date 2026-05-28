"""
database.py
-----------
PostgreSQL connection pool, schema initialisation, and all DB helper
functions used by GeoSustain.

Tables created automatically on first run:
  users               – registered accounts
  analysis_sessions   – every analysis run (linked to a user)
  saved_analyses      – bookmarked analysis sessions
  reports             – generated/downloadable reports
  environmental_data  – GEE + weather readings per session
  soil_nutrients      – N / P / K per session
  crop_recommendations – ML output per session
  analysis_cache      – 5-min coordinate-level cache
"""

import os
import psycopg2
from psycopg2.extras import RealDictCursor, Json
from datetime import datetime

# ---------------------------------------------------------------------------
# Connection
# ---------------------------------------------------------------------------
# Set DATABASE_URL in your environment, e.g.:
#   postgresql://geosustain:password@localhost:5432/geosustain_db
DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://postgres:postgres@localhost:5432/geosustain_db"
)


def get_conn():
    """Open and return a fresh psycopg2 connection."""
    return psycopg2.connect(DATABASE_URL, cursor_factory=RealDictCursor)


# ---------------------------------------------------------------------------
# Schema bootstrap
# ---------------------------------------------------------------------------
SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS users (
    id            SERIAL PRIMARY KEY,
    username      VARCHAR(50)  NOT NULL,
    email         VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role          VARCHAR(20)  NOT NULL DEFAULT 'farmer',
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

CREATE TABLE IF NOT EXISTS analysis_sessions (
    id              SERIAL PRIMARY KEY,
    user_id         INTEGER REFERENCES users(id) ON DELETE SET NULL,
    center_lat      FLOAT NOT NULL,
    center_lon      FLOAT NOT NULL,
    place_name      VARCHAR(200),
    analysis_source VARCHAR(50),
    season_name     VARCHAR(80),
    season_advice   TEXT,
    analyzed_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
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
    infrastructure_recommendation TEXT
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
    alternative_crops     JSONB
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
    role VARCHAR(20) NOT NULL DEFAULT 'farmer',
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
            cur.execute("ALTER TABLE crop_recommendations ADD COLUMN IF NOT EXISTS alternative_crops JSONB")
            # Usernames are display names; only email must be unique.
            cur.execute("ALTER TABLE users DROP CONSTRAINT IF EXISTS users_username_key")
        conn.commit()
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# User helpers
# ---------------------------------------------------------------------------

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
                (username, email, password_hash, role, email_verified, auth_provider, google_sub),
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
            cur.execute("SELECT * FROM users WHERE email = %s", (email,))
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
    """Update editable user profile fields and return the updated public row."""
    allowed_roles = {"farmer", "analyst"}
    updates = []
    values = []
    if username:
        updates.append("username = %s")
        values.append(username)
    if role in allowed_roles:
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
                     season_name, season_advice)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
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
                     infrastructure_status, infrastructure_recommendation)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
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
                     recommendation, crop_label, crop_growth_cycle, crop_est_yield, alternative_crops)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
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
                ),
            )

        conn.commit()
        return session_id
    finally:
        conn.close()


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
                    s.analyzed_at,
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
                    n.nitrogen,
                    n.phosphorus,
                    n.potassium,
                    c.predicted_crop,
                    c.compatibility_pct,
                    c.suitability_level,
                    c.is_crop_recommended,
                    c.land_status,
                    c.recommendation_title,
                    c.alternative_crops
                FROM analysis_sessions s
                LEFT JOIN environmental_data  e ON e.session_id = s.id
                LEFT JOIN soil_nutrients      n ON n.session_id = s.id
                LEFT JOIN crop_recommendations c ON c.session_id = s.id
                WHERE s.user_id = %s
                ORDER BY s.analyzed_at DESC
                LIMIT %s
                """,
                (user_id, limit),
            )
            rows = cur.fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()


def _history_select_sql(extra_select="", extra_join="", where_prefix="s.user_id = %s"):
    return f"""
                SELECT
                    s.id            AS session_id,
                    s.center_lat,
                    s.center_lon,
                    s.place_name,
                    s.analysis_source,
                    s.season_name,
                    s.analyzed_at,
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
                    n.nitrogen,
                    n.phosphorus,
                    n.potassium,
                    c.predicted_crop,
                    c.compatibility_pct,
                    c.suitability_level,
                    c.is_crop_recommended,
                    c.land_status,
                    c.recommendation_title,
                    c.alternative_crops
                    {extra_select}
                FROM analysis_sessions s
                LEFT JOIN environmental_data  e ON e.session_id = s.id
                LEFT JOIN soil_nutrients      n ON n.session_id = s.id
                LEFT JOIN crop_recommendations c ON c.session_id = s.id
                {extra_join}
                WHERE {where_prefix}
                ORDER BY s.analyzed_at DESC
            """


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
        return [dict(r) for r in rows]
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
        return [dict(r) for r in rows]
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

