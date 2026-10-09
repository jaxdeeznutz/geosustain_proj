# GeoSustain mobile repairs — 7 October 2026

Implemented in the existing `Downloads/GeoSustain-mobile-update` checkout, starting from commit `66e4223`. Changes are local and ready to review. They have not been committed, pushed, or deployed. This report supersedes the verification and packaging notes in the earlier `MOBILE_UPDATE.md` for this follow-up.

**Findings and evidence**

| Reported issue | Finding |
| --- | --- |
| Failed Analyze This Farm | Confirmed: the state layer exposed raw network exceptions and could retain the previous result after failure. The original authenticated production failure has **not** been reproduced. Live health/OpenAPI and the Vercel-origin analysis preflight returned 200. The 401 in the supplied log was our deliberate unauthenticated probe, not evidence of a bad user session. The log excerpt contains no failing authenticated analysis or provider exception. |
| Unexpected results | Confirmed: profile loading automatically selected the newest account-wide analysis, without a farm selection. Opening a different farm did not clear that selection. Delayed requests lacked account/selection guards. Local history also merged separate runs with matching coordinates/crop. No hardcoded demo records were found in these production flows. Actual suspicious production rows were not available for inspection; legitimate history was retained. |
| Constant weak GPS / apparent freezing | Confirmed: the app already used a continuous location stream. Missing/zero accuracy was incorrectly grouped with poor accuracy, and the camera moved only for the first accepted point. There was no recenter control. Fresh live position, accepted boundary vertices, and camera movement are now handled separately. Physical phone accuracy and the original device's readings remain unverified. |
| Blank map | The exact reported rendering failure was not reproduced. Sample live OpenStreetMap tiles at zooms 15 and 19 returned 200 PNG responses. The prior library already defaulted to native zoom 19, so unsupported tile zoom was not established as the cause. Maps now explicitly cap native tile zoom, fit the boundary with padding, and show a retry action when a tile actually fails. Vector boundaries remain visible. |

The 0.002 ha example is approximately 20 m². The existing geometry minimum is 4 m²; there is no separate larger analysis minimum in this code. A regression test confirms a roughly 20 m² ring passes the existing constraint. Vegetation sampling uses 10 m imagery, with coarser elevation/weather sources. The UI therefore shows a small-boundary limitation without expanding the polygon or inventing a new minimum. GPS accuracy within 20 m does not make a tiny parcel a survey-quality boundary.

**Implemented behavior**

- Farm details fetch the owned farm and its own history. Only completed runs appear, newest first. Unanalyzed farms have a compact status and Analyze action, with no Previous analyses heading or disabled result button. Loading/fetch failures are distinct from an empty history.
- Analysis opens an exact saved result, or the focused farm's empty state. Without a selection it offers completed records. History defaults to the selected farm and has an explicit All farms control. Unassociated legacy records use “Unnamed area.” Farm name, associated account's actual display name, location, area, date, and review status identify each record.
- Logout clears account data, farm/result selection, location state, and retry data. Generation checks reject late history/result responses after an account or farm change. Concurrent refreshes are coalesced, and refresh startup is deferred until after widget construction.
- Analyze sends the selected farm ID and polygon. The backend checks ownership and uses the saved server boundary. Failed inference or persistence cannot create a successful result. Repeated taps are blocked and raw network URLs are replaced with actionable messages.
- Persistent retry keys are scoped by account and input. Before another POST, the client checks `/api/mobile/analysis-requests/{request_id}`. PostgreSQL advisory locks prevent concurrent computation for the same user/key across server workers. Completed requests return their saved result; active requests report processing. A worker crash releases its lock. This is recovery for the existing synchronous analysis flow, not a durable background job queue. No completed result is fabricated for a stopped worker.
- GPS requests continuous fixes, follows/recenters the camera, and updates the live marker for fresh valid fixes even when accuracy prevents recording a boundary vertex. Paused/stale positions are visibly inactive; missing accuracy is unknown. Existing acceptance limits remain: at most ±20 m reported accuracy, at most 20-second age, at least 4 m movement, no gap over 80 m or apparent speed over 12 m/s. Nonmonotonic/future readings are rejected. Stream generations fence canceled listeners.
- Farm details, GPS recording, Analysis, and History use compact green/neutral layouts. Management actions moved into a menu. Detailed XAI interpretation, definitions, and limitations are expandable under “Why this result?”. Automated results and analyst decisions remain distinct and tied to each saved run.
- Backend logs mark inference, saving, completion, and failure with user/farm IDs, elapsed time, and exception type. New diagnostic lines omit tokens, passwords, provider credentials, and coordinates. The duplicate OpenAPI operation-ID warning for the legacy GET/POST route was also removed.

**Verification**

- Flutter analyzer: no issues.
- Complete Flutter suite: **52 tests passed**, including account/farm isolation, failed and lost-response requests, duplicate-tap prevention, GPS stream/filter/lifecycle behavior, navigation/logout, and 402 px / 360 px layouts. The affected geometry/scope tests were rerun after the final small cleanup.
- Python: **46 tests passed**. Ruff syntax/undefined-name checks passed. Existing FastAPI/Starlette deprecation warnings remain.
- Real local PostgreSQL integration: passed registration/login, farm creation without analysis, ownership enforcement, in-flight locking/status recovery, exact farm/owner identity, per-farm history, immutable boundary snapshots, analysis retry, analyst approval, and password/session revocation. A disposable schema was removed afterward; existing records were not modified.
- Release Flutter web build: passed. No dependency/model/dataset replacement was needed.
- Screenshots at 402 px and 360 px were generated and inspected. They use explicit test fixtures and neutral offline map tiles; they are layout evidence, not live agronomic results or proof of outdoor GPS performance.

Provider output is substituted in the PostgreSQL workflow test; the separate model-inference regression exercises the existing model. No authenticated live Earth Engine analysis was verified. Android device enumeration could not run because the environment denied execution of the installed ADB binary, so no Android runtime or outdoor walking claim is made.

**Deployment and remaining checks**

1. Deploy this backend to Render **before** the new frontend. Confirm OpenAPI lists `/api/mobile/analysis-requests/{request_id}` and the existing database startup succeeds. The new client deliberately requires that route for safe retries. Keep the existing database and credentials; do not reset users or historical analyses.
2. Rebuild/deploy the frontend to the existing Vercel project:

   ```sh
   flutter pub get
   flutter build web --release --dart-define=API_BASE_URL=https://geosustain.onrender.com
   ```

   Deploy `build/web` and reload the site to load the new bundle. The source ZIP is the only ZIP needed for source development.
3. Sign in and analyze the originally failing farm. If it fails, inspect the new Render inference/saving/failure lines around that attempt. The public preflight/401 probe cannot identify an Earth Engine, timeout, database, or device-network failure. An authenticated deployed end-to-end check is still required.
4. On a real phone outdoors, walk a known perimeter. Check live movement, accepted points, accuracy, closure, pause/resume/background behavior, save/reopen, and analysis/review. Also test denied permission and temporary loss of GPS. Resizing a desktop browser is not a phone GPS test.

The source package excludes `.git`, credentials, build output, and development caches. The existing Git-connected project folder already contains these edits; there is no need to initialize another repository to review or commit them.
