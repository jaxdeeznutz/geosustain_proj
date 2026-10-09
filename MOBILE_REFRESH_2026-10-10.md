# GeoSustain mobile refresh ? 10 October 2026

Implemented locally in the existing Flutter app. No account data, farms, completed analyses, model files, or datasets were modified. Nothing has been deployed. The attachment contained the written brief only; no reference image was available.

## Confirmed findings

- **Misleading connection message:** `friendlyErrorMessage` previously classified generic fetch/socket/client failures as ?No internet connection, or the server is temporarily unreachable.? It also inspected exception text before typed HTTP status. Transport failures cannot establish whether a device is offline; CORS, DNS, startup delays, and an unreachable service can look alike. HTTP status now takes precedence, uncertain transport failures say ?Couldn't reach the analysis service. Try again.?, authentication and service failures have separate messages, boundary validation stays specific, and unexpected exceptions are not printed in the UI.
- **Actual request path:** farm action ? `AnalysisState.analyzeSavedFarm` ? `ApiService.analyzePolygon` ? persisted request key/status lookup ? authenticated JSON POST `/api/mobile/analysis` ? FastAPI `_perform_mobile_analysis` ? `build_analysis_result` / existing `rainfallDatasets.analyze_location` ? saved analysis. Render runs `fastapi_app:app`; the IDE's `backend/app.py` is the retained legacy Flask entry point. No connectivity precheck blocks this path. API_BASE_URL defaults to `https://geosustain.onrender.com` and the release build explicitly uses that URL.
- **Public service evidence:** first GET `/health` exceeded a 60-second timeout. Subsequent GET `/openapi.json` succeeded and included analysis and recovery routes. OPTIONS `/api/mobile/analysis` returned 200 and allowed the Vercel origin plus authorization, content-type, and idempotency-key headers. A startup delay is plausible, not proven. These unauthenticated reads do not establish the original authenticated/provider failure.
- **GPS paused-state mismatch:** stopping before the first location fix previously displayed Ready/Start even though recording had been started and paused. A separate started flag now shows Paused/Resume consistently, including after undoing all vertices.
- **GPS noise acceptance:** the existing 4 m spacing rule accepted approximately 5.6 m displacement even when reported accuracy was ?8 m. The revised rule requires displacement from the last accepted vertex to exceed `max(4 m, current accuracy, previous accepted accuracy)`. This conservatively rejects movement within reported uncertainty. It is not a survey accuracy guarantee and needs field calibration.
- The existing continuous subscription, cancellation-generation guards, last-accepted-point distance calculation, and marker/camera separation worked in controlled tests. The cause of the user's particular one-point outdoor recording cannot be confirmed without their readings. Debug builds now log timestamp, freshness, accuracy, distance, acceptance, and rejection reason, without coordinates.

## Implementation

- Shared rich green, mint, and cream styling; code-drawn field/sprout accents; colored icon backgrounds; illustrated farm and analysis empty states; concise Home entry cards; compact farm and history identity. Existing five tabs, profile controls, real results, ownership, review status, and expandable XAI remain functional.
- Real flutter_map content, boundaries, markers, camera controls, and attribution remain unobscured. Agricultural art is outside the map.
- The recording indicator pulses only during active recording with a fresh fix. Point-count changes briefly crossfade. Both respect reduced motion. Existing Material press/route feedback and real loading/saved-state feedback remain in place.
- Analysis diagnostic logs include exception type, HTTP status, and elapsed duration, never request bodies, tokens, raw exceptions, or coordinates. Existing persistent retry keys, lookup-before-resubmit, server locks, account/selection guards, and exact-farm completion checks remain intact.
- GPS retains its existing ?20 m accuracy ceiling, 20-second freshness limit, 5-second future tolerance, 80 m jump limit, and 12 m/s outlier limit. No artificial points or movement are introduced. Geometry still requires distinct vertices, supported coverage, noncrossing edges, and at least 4 m?.

## Verification

- Flutter analyzer: no issues.
- Flutter full run: 55 checks passed; two newly added test-harness cases initially failed due to an offscreen tap and initial ticker-frame timing. After correcting the harness, all seven GPS workflow tests passed, including those two cases. Total passing coverage: 57 checks.
- Coverage includes failed requests, lost-response recovery without duplicate POST, persisted keys across clients/farms, wrong-farm responses, double taps, permission denial, foreground/background pause, live marker updates for rejected points, staleness, accuracy, uncertainty filtering, pause before first fix, Resume, Undo, Finish/save, and reduced motion.
- Backend: 46 tests passed in an isolated `.venv`, with live database access explicitly blocked by the test fixture. Existing FastAPI/Starlette deprecations and a pytest-cache permission warning remain. No live PostgreSQL/provider analysis was performed in this turn.
- Release Flutter web build passed with the explicit production API URL; output is `build/web`.
- Screenshots generated at 360 and 402 px and visually reviewed. They use test fixtures and neutral offline map tiles, not production results or fake operational maps. See `build/mobile-qa/october/` for Home, My Farms, Analysis, expanded explanation, History, Profile, farm details, and GPS recording.

## Remaining verification

No physical phone was connected (Flutter enumerated Windows, Chrome, and Edge only). An outdoor perimeter walk still needs to verify real accuracy, accepted spacing, pause/resume, GPS interruptions, and reopening the saved boundary on a phone. The originally failing authenticated farm analysis also still needs a live attempt and its corresponding sanitized server logs. Public CORS/schema checks and substituted-provider backend tests cannot establish live Earth Engine success. No deployment was requested or performed.
