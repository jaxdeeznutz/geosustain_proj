# GeoSustain

AI-driven geospatial decision support for sustainable landscape management in Panabo City.

## Run the current application

The current application uses **Flutter + FastAPI**, with PostgreSQL/Supabase, Google Earth Engine, OpenWeather, Open-Meteo and NASA POWER. `backend/app.py` is an older Flask entry point; the Flutter app and both Render configurations use `backend/fastapi_app.py`.

Prerequisites: Flutter 3.41.9 / Dart 3.11.5 or a compatible newer SDK, Python 3.11+, and your existing database and provider configuration.

From the project root:

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
python -m pip install -r backend/requirements.txt
python -m uvicorn fastapi_app:app --app-dir backend --host 0.0.0.0 --port 8000
```

Open `http://127.0.0.1:8000/health` to check the server and `/docs` for the API schema. Startup initializes the configured database as in the original project. Use a development database for local testing.

In a second terminal:

```powershell
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

For the Android emulator, use `http://10.0.2.2:8000`; for a physical phone, use your computer's reachable LAN address. Without `API_BASE_URL`, the app continues to use `https://geosustain.onrender.com`, exactly as the original.

The Windows shortcuts remain available: `start_backend.bat` and `run_flutter.bat`. The latter runs against the existing online backend by default.

## Configuration

The backend now loads `backend/.env`; deployment environment variables take precedence. The private delivered ZIP includes the OpenWeather key carried over from your original source in this Git-ignored file. Keep it private. No database password, email credentials or Earth Engine service-account key was supplied or added.

Use `backend/.env.example` as a guide and retain your existing values for:

- `DATABASE_URL`: existing PostgreSQL/Supabase database.
- `SECRET_KEY`: your existing strong deployment signing secret. Changing it invalidates existing sessions/tokens.
- `OPENWEATHER_API_KEY`: existing weather key.
- `GEE_PROJECT_ID` and `GEE_SERVICE_ACCOUNT_JSON`, or locally authenticated Earth Engine credentials.
- Your existing OTP email settings; see `OTP_RENDER_SETUP.md`.

**Before deploying the cleaned backend to Render, ensure `OPENWEATHER_API_KEY` is configured in Render Environment.** The local `.env` is intentionally ignored by Git. The old public source-code fallback key has been removed. Consider rotating that previously embedded key separately.

No changes were deployed during this review. Keep your current Render environment and database settings. Root `render.yaml` and `backend/render.yaml` are retained for the two existing repository-root layouts.

## Verification

```powershell
flutter analyze
flutter test
flutter build web
python -m pip install -r backend/requirements-dev.txt
python -m pytest backend/tests -q
python -m ruff check backend --select F
```

Backend regression tests replace database and external-provider calls with controlled responses. They do not require or modify your production data. Flutter API tests use a mock HTTP client. The trained model and datasets are unchanged; scikit-learn is pinned to the model's recorded training version, 1.8.0.

For the optional older Flask application, install `backend/requirements-legacy.txt` first. It is retained for compatibility and is not the supported entry point for the current farmer/analyst/admin workflow.

## Project layout

- `lib/`: Flutter application, mobile screens and analyst/admin web screens.
- `backend/fastapi_app.py`: active API and existing HTML routes.
- `backend/database.py`: database schema and persistence helpers.
- `backend/rainfallDatasets.py`: environmental data collection and model inference.
- `backend/training/`, model files and CSVs: unchanged training/inference assets.
- `backend/templates/` and `backend/static/`: still used by FastAPI; not dead files.
- `backend/tests/` and `test/`: regression tests added during this cleanup.
- `android/`, `web/`, `assets/`: platform configuration and application assets.

Historical panel-update notes are preserved for context. See `CLEANUP_REPORT.md` for the changes and validation limits.
