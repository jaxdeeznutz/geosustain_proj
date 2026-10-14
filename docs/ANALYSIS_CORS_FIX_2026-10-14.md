# Analysis save failure and CORS fix — 14 October 2026

## Confirmed causes

The supplied Render traceback shows inference completed for all nine polygon
samples. Saving `analysis_sessions.result_snapshot` then failed inside psycopg2's
JSON adapter: `historical_climate_baseline.fetched_at` was a Python datetime.
This is a persistence serialization failure, not a failed crop prediction.

Starlette's outer ServerErrorMiddleware generated the unhandled 500 outside the
previous CORSMiddleware. The response lacked CORS headers, so browsers reported
a network/CORS failure instead of the actual server error. Production preflight
and unauthenticated POST already returned appropriate CORS headers before this fix.

## Changes

- `backend/json_safe.py`: recursively converts dates/timestamps to ISO strings,
  NumPy scalars/arrays to JSON primitives, and non-finite/missing values to null.
  Unsupported objects still fail; no blanket `default=str` or invented measurements.
- `backend/database.py`: normalizes the entire analysis before opening the save
  transaction, covering every JSONB field and scientific SQL scalar.
- `backend/http_config.py`: explicit trusted origins and CORS around the entire
  FastAPI middleware stack, including unexpected 500s. No wildcard preview trust.
- `backend/fastapi_app.py`: uses that stack, returns sanitized generic errors,
  logs failure tracebacks and geometry/save/serialization stages, normalizes the
  response, and exposes the non-secret Render commit revision in health responses.
- `backend/environmental_pipeline.py`: logs retrieval, model and scoring stages
  without request coordinates, credentials or payloads.
- `backend/.env.example`: documents FRONTEND_ORIGINS.
- `backend/render.yaml`: matches the root blueprint's Python 3.11.9 setting.
- `lib/main.dart`: distinguishes HTTP 500 from unavailable service/network errors.
- `backend/tests/test_analysis_serialization_cors.py`: actual psycopg2 JSON adapter,
  endpoint persistence, missing/scientific values, allowed/denied origins and CORS
  on unexpected dependency errors.
- `test/error_classification_test.dart`: HTTP 500 message regression.

No schema migration, record rewrite, model replacement or scoring change is needed.
The existing frontend payload (`farm_id` or `polygon` / `lat` / `lon`, plus optional
place name/month) matches AnalysisBody. Saved farms use the server-owned polygon.
The model and CSV files are tracked in `backend/` and resolved relative to the module.

## Render settings

For repository-root deployment (current root render.yaml):

```sh
pip install -r backend/requirements.txt
cd backend && uvicorn fastapi_app:app --host 0.0.0.0 --port $PORT
```

If Render's Root Directory is `backend`, use:

```sh
pip install -r requirements.txt
uvicorn fastapi_app:app --host 0.0.0.0 --port $PORT
```

Set `FRONTEND_ORIGINS=https://geosustain.vercel.app` for production, optionally
adding comma-separated exact trusted preview origins or localhost ports. Origins
must have no paths; trailing slashes are normalized. Without this variable the
production origin and localhost ports 3000, 5173 and 8080 are allowed.

Keep existing DATABASE_URL, SECRET_KEY, OPENWEATHER_API_KEY, GEE_PROJECT_ID and
GEE_SERVICE_ACCOUNT_JSON (if service-account auth is used). Do not rotate keys as
part of this fix. Firebase/SUPABASE_URL/SUPABASE_KEY are not needed by this pipeline;
database access uses DATABASE_URL. The successful authenticated queries and nine
completed samples in the supplied logs demonstrate these stages ran, but their
Render environment values were not independently inspected.

The supplied runtime traceback is Python 3.14.3 despite the root blueprint's
PYTHON_VERSION=3.11.9. Set the dashboard variable to 3.11.9 to match the repository
and local tests; editing a blueprint alone may not alter an existing manual service.
This discrepancy is separate from the datetime serialization crash.

## Verification

Local: 68 backend tests and 24 Flutter API/scope/error tests pass. The new endpoint
test uses the real psycopg2 JSON adapter with a fake database/provider; it is not a
claim of a completed production farm analysis. Existing Ruff F811 fixture-import
warnings remain in test_analysis_scope.py and test_explainability.py; changed Python
files are checked separately.

After Render deploys the pushed commit, compare `revision` with that commit:

```sh
curl -i https://geosustain.onrender.com/health
curl -i -X OPTIONS https://geosustain.onrender.com/api/mobile/analysis \
  -H 'Origin: https://geosustain.vercel.app' \
  -H 'Access-Control-Request-Method: POST' \
  -H 'Access-Control-Request-Headers: authorization,content-type,idempotency-key'
```

Expect health 200 and preflight 200 with the exact frontend origin, credentials,
POST and requested headers allowed. An unauthenticated POST must return 401 with
CORS, not 200. This verifies auth/error handling, not analysis success.

For a real analysis, log in on the Vercel site and analyze an owned farm. Or use a
valid bearer token locally (never paste it into chat) and that user's farm ID:

```sh
curl -i https://geosustain.onrender.com/api/mobile/analysis \
  -H 'Origin: https://geosustain.vercel.app' \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -H 'Idempotency-Key: use-a-new-unique-request-key' \
  --data '{"farm_id":2}'
```

Replace 2 with the authenticated user's farm ID. Expect 200, session_id,
analysis_status=completed and the same farm_id; a concurrent retry can return 202
while the original is running. Check history and crop rankings and Render's
`Analysis response serialized` / `Analysis completed` logs. Reuse the same retry
key if the response is lost, to avoid duplicate records.

CHIRPS missing-precipitation warnings preceded the crash but were handled by the
existing fallback. They are not the JSONB exception. No rainfall values or provider
fallback rules were changed in this fix. Missing measurements remain unavailable.

## Follow-up: cold-start Earth Engine failure

Production revision 9731c46 passed live health/CORS checks, but the user's next
analysis failed earlier with HTTP 503: all nine samples failed after
`Earth Engine initialization unavailable: AssertionError`. This is a separate
startup bug, not a recurrence of the datetime serialization error.

The installed earthengine-api 1.7.47 reproduces that assertion when
`ee.data.setDeadline(30000)` runs before `ee.Initialize`: setting the deadline
rebuilds the Cloud API resource, which requires an initialized requests session.
`backend/rainfallDatasets.py` now sets the retry limit, initializes Earth Engine,
then sets the deadline. The existing lock, one-minute failure cooldown and
30-second provider deadline are retained. Initialization failures now log their
traceback rather than only the exception type.

`backend/tests/test_earth_engine_startup.py` reproduces the assertion using the
real installed deadline implementation with network discovery mocked, then checks
the corrected cold start, concurrent workers and failed-authentication cooldown.
No credential changes or fabricated environmental values are part of this fix.
Open-Meteo's reported overload is an independent upstream outage; it does not
explain the Earth Engine assertion.
