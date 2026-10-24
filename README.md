> Current implementation and QA evidence: [readiness execution](defense-evidence/readiness-execution/README.md), [updated QA](defense-evidence/readiness-execution/QA_CURRENT.html), [phase index](defense-readiness-plan/README.md). Scientific/provider/device and deployment acceptance remain explicit; local test passes are not whole-project signoff.

# GeoSustain

Defense implementation and evidence: [handover index](defense-evidence/2026-10-23/README.md), [work-item register](defense-evidence/2026-10-23/docs/WORK_ITEM_REGISTER.md), and [deployment/rollback](defense-evidence/2026-10-23/docs/DEPLOYMENT_AND_ROLLBACK.md). External account, push, device and scientific acceptance dependencies remain explicit in that register.

Implementation notes: [model ranking](docs/MODEL_RANKING_2026-10-14.md), [environmental recovery](docs/ENVIRONMENTAL_RECOVERY_2026-10-14.md), and [analysis/CORS fixes](docs/ANALYSIS_CORS_FIX_2026-10-14.md).

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

The backend loads `backend/.env`; deployment environment variables take precedence. The mobile-update source ZIP excludes local secrets and `.env` files. Keep your existing Render environment values and configure local credentials separately.

Use `backend/.env.example` as a guide and retain your existing values for:

- `DATABASE_URL`: existing PostgreSQL/Supabase database.
- `SECRET_KEY`: your existing strong deployment signing secret. Changing it invalidates existing sessions/tokens.
- `OPENWEATHER_API_KEY`: existing weather key.
- `GEE_PROJECT_ID` and `GEE_SERVICE_ACCOUNT_JSON`, or locally authenticated Earth Engine credentials.
- Email/password authentication uses PostgreSQL and bcrypt. Email-code signup and one-use email recovery are implemented with TLS SMTP or Resend HTTPS; production defaults to required verification, while the explicit example `0` is for local development. Google sign-in, explicit password-account linking, profile phone editing and Firebase SMS proof exchange are implemented. They require an owned Firebase project and real mail sender, which have not been supplied. See [provider setup](deployment/IDENTITY_AND_DELIVERY_SETUP.md). The existing-account migration script is `backend/migrate_password_auth.py`.

**Before deploying the cleaned backend to Render, ensure `OPENWEATHER_API_KEY` is configured in Render Environment.** The local `.env` is intentionally ignored by Git. The old public source-code fallback key has been removed. Consider rotating that previously embedded key separately.

The current changes have not been deployed. Root `render.yaml` and `backend/render.yaml` support the two existing repository-root layouts and enable durable analysis jobs. Read [release/signing/rollback handover](deployment/RELEASE_HANDOVER.md) before publishing matching backend/web/Android artifacts. Main Android release transport is HTTPS-only; local cleartext is restricted to the debug overlay. Release builds require the private signing configuration.

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

Generated build intermediates, test logs, and caches can be regenerated. Release artifacts remain under `build/app/outputs/`. Local Python tools, environments, and soil reference data are excluded from Git and retained locally.
