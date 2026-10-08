# GeoSustain mobile update — 2 October 2026

The updated source and release web bundle are ready for deployment. They have not been pushed to GitHub or deployed to Vercel/Render. The original downloaded project remains unchanged.

## What changed

- Five persistent tabs: Home, My Farms, Analysis, History, Profile. Back navigation returns to Home before leaving the app. Farmers can also use this interface in a desktop browser; existing analyst/admin dashboards remain role protected.
- Home explains mapping, analysis, and analyst review, with real saved-farm/review counts and recent records.
- A reusable method picker opens dedicated GPS walking and manual drawing screens. The existing analyst mapping interface remains available.
- GPS walking supports permissions, accuracy feedback, Start/Pause/Resume/Finish, undo, review, area estimates, naming, and saving. Backgrounding pauses recording and requires an explicit Resume. Leaving or finishing stops the location stream. Weak/stale/duplicate fixes and excessive jumps are rejected with guidance.
- Both mapping methods validate a closed lat/lng ring within the existing Panabo coverage rectangle. Crossings, overlapping edges, degenerate areas, and unsupported point counts are rejected. This is the application's coverage rectangle, not an official administrative boundary or a land ownership survey.
- A saved farm can have multiple analyses. Historical analyses preserve their own geometry, boundary version, farm name, and result snapshot. New analyses begin as Not Submitted, even if an earlier analysis was approved.
- Analysis displays the exact selected run, actual crop results, supported environmental indicators, existing XAI output, recommendations, and review feedback. Missing values stay unavailable; no synthetic confidence or feature contributions were added.
- History separates completed processing from review status. Supported review labels are Not Submitted, Pending Review, Approved, and Rejected. Refreshing or returning to the app retrieves analyst decisions and notes.
- Profile exposes supported account fields, a read-only role, password change, location guidance, About/version, and logout. Missing account location no longer borrows the map location. Placeholder preference switches were removed.
- Authentication now validates fields, restores saved sessions, preserves sessions during a temporary service outage, and clears account/retry state at logout. Password changes revoke older sessions. Public registration creates farmer accounts; privileged roles remain an administrator responsibility.
- Per-user request IDs prevent duplicate farm and analysis records during retries. Ownership checks occur before analysis and saving. The existing analysis model and datasets were preserved.

## Registration and login findings

On 2 October, the deployed Render API returned HTTP 409, `Email is already registered. Please log in.`, for a fresh, randomly generated diagnostic email at the reserved example.com domain. No diagnostic account was reported as created. The Vercel bundle points to the expected Render host, and the registration CORS preflight succeeded. Render was intermittently slow/unresponsive during other checks.

The supplied backend converted **every PostgreSQL unique-constraint violation** into that duplicate-email message. An account ID collision therefore looked like an email conflict. The new code returns that message only when the email actually exists. It detects a primary-key collision, safely advances an out-of-sync SERIAL/IDENTITY sequence while holding the required table lock, and retries once. It does not change existing user IDs, passwords, or records. An isolated PostgreSQL test reproduced this exact imported-ID condition and verified recovery and preservation of the existing account.

The precise constraint failing on the live Render database is not visible from its public response. An out-of-sync user ID sequence is a tested explanation and is now handled, but should not be presented as conclusively confirmed on production without the corresponding Render/PostgreSQL error. If registration still fails after deployment, inspect the server log's database exception/constraint and verify the users table schema and sequence. Do not reset the database.

Existing bcrypt accounts keep their passwords. Plaintext passwords, Firebase-only accounts, and unsupported legacy hashes cannot safely be accepted as bcrypt credentials. The existing `backend/migrate_password_auth.py` provides a dry run for legacy password/pending-registration cleanup; confirm any plaintext account IDs explicitly before applying that separate migration. Existing accounts are never overwritten by a signup retry. Firebase and email OTP are not required by the password login flow.

A separate confirmed persistence defect was fixed: the environmental-data INSERT had 18 values but only 17 SQL placeholders. Successful analysis could previously appear without a saved session. The updated mobile route saves atomically and returns a service error if persistence fails.

## Main files

| Module | Responsibility |
|---|---|
| `lib/main.dart`, `lib/api_service.dart`, `lib/screens/session_gate.dart` | Navigation, state, authentication, exact-result loading, retries |
| `lib/farm_geometry.dart`, `lib/screens/land_mapping_screen.dart` | Shared geometry validation, GPS recording, polygon drawing |
| `lib/screens/my_farms_screen.dart` | Farm list, details, saved-boundary analysis and past runs |
| `lib/screens/home_screen.dart`, `mobile_results.dart`, `history_screen.dart`, `profile_screen.dart` | Farmer screens and account settings |
| `backend/fastapi_app.py`, `backend/database.py`, `backend/geometry.py` | API contracts, ownership, persistence, migrations and geometry |
| `test/`, `backend/tests/` | Regression coverage and isolated PostgreSQL workflow test |

## Database and configuration

Keep the existing deployment's `DATABASE_URL`, strong `SECRET_KEY`, `GEE_PROJECT_ID`, Earth Engine credentials, and `OPENWEATHER_API_KEY`. Source packages exclude `.env` and machine-specific caches. Use `backend/.env.example` for a local environment. No Firebase or email-provider setup is needed for these flows.

`init_db()` applies compatible additions: farms and request indexes, `users.password_version`, `farm_parcels.boundary_version`, and analysis snapshots/version/submission/request fields. Existing historical data is retained; old analyses lacking full snapshots display only the information that was actually stored. Historical information that was never saved cannot be reconstructed.

Deploy the FastAPI backend first. Its normal startup runs `init_db()`. Confirm `Database initialized successfully` in Render logs; `/health` alone does not prove migration/database readiness because the existing startup catches initialization failures. If a controlled migration step is preferred, run from the backend directory against the intended deployment database:

```sh
python -c "from database import init_db; init_db()"
```

Use the existing Render start command, `uvicorn fastapi_app:app --host 0.0.0.0 --port $PORT`, with the backend directory as working directory. Install `backend/requirements.txt` if the service root is the repository root.

Then deploy the supplied web bundle to the existing Vercel project, or rebuild from source:

```sh
flutter pub get
flutter build web --release --dart-define=API_BASE_URL=https://geosustain.onrender.com
```

The supplied web ZIP contains the contents of `build/web`, including `index.html`, at its root. Keep backend credentials on Render. Reload the site after deployment so an older cached Flutter bundle is not used. Confirm the deployed OpenAPI includes `/api/mobile/change-password` and `/api/mobile/analyses/{session_id}`, then test signup/login using the updated frontend.

For local development, Android emulators use `http://10.0.2.2:8000`; a physical phone needs a reachable LAN address or the HTTPS Render endpoint. The source defaults to the Render endpoint. Browser GPS requires a secure origin and permission.

## Verification

- Flutter static analysis: no issues.
- Flutter regression coverage: 37 tests, covering authentication transport/session failures, navigation/back/logout, actual theme at phone width, result/status rendering, geometry/GPS filters, permission denial, lifecycle pause, and a four-corner GPS recording saved as a closed farm without automatic analysis/review. Full 36-test suite passed before the final GPS-save test was added; the affected four-test mapping suite and final visual/navigation rerun passed afterward.
- Python: 41 tests passed; Ruff F checks passed. Existing FastAPI/Starlette deprecation warnings remain.
- Local PostgreSQL integration: passed registration, imported-ID sequence recovery, duplicate signup, login, farm/analysis retry handling, persistence, analyst queue/approval/feedback, ownership restrictions, immutable history, fresh reanalysis status, password change and token revocation. It used a disposable schema that was removed afterward; existing public-schema records were not changed.
- Release web build: passed, including the Wasm dry run. The delivered bundle uses the Render API URL above.
- Phone-width previews were inspected. Automated map tests intentionally do not fetch live tiles.

The database integration substitutes analysis-provider output to isolate persistence and workflow behavior. It is not a live Earth Engine or agronomic-accuracy validation. No Android emulator image or attached Android device was available, so no Android runtime or outdoor GPS claim is made. Android release signing remains the project's existing development setup.

## Remaining deployment/device checks

1. Deploy backend/migrations and frontend together, then retest the account that failed and one new signup. Capture the Render exception if a database failure remains; the public error cannot identify the exact production constraint.
2. With real Earth Engine credentials, run one drawn polygon and one saved GPS farm through analysis, submit to an analyst, approve/reject, and refresh the farmer's History.
3. On a phone outdoors, walk a known farm perimeter, check positional accuracy/closure, background and resume, finish/save, restart, and confirm the saved farm/result is restored. Test disabled GPS and denied permissions as well.

Saving or drawing a boundary records the user's proposed parcel; it does not establish legal ownership. Analyst review remains a distinct action tied to an analysis run.
