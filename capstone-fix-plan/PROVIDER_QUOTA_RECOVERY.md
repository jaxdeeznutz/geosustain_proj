# Confirmed environmental-provider quota failure

The owner's Render logs identify an active API with successful farm/history/me
requests while analysis returns 503. The trace ends with the existing strict
model gate: required climate input humidity unavailable. Open-Meteo reports its
daily request quota exhausted; its humidity fallback fails, and CHIRPS has not
yet supplied all of the exact 30 requested completed dates. Push subscription
503s are separate provider configuration failures, not failed farm analysis.
No raw owner logs, addresses or farm identifiers are committed here.

## Narrow repair

- The existing independent primary humidity provider is OpenWeather. The owner
  confirmed `OPENWEATHER_API_KEY` is not configured. Skip empty-key requests;
  no inferred/default humidity is promoted to a model observation.
- Cache successful Open-Meteo humidity for five minutes at the exact requested
  coordinate, matching the primary current-weather cache lifetime. Do not round
  parcel sample locations, share values between coordinates, use stale readings
  beyond the TTL or cache a missing reading as a successful measurement.
- Limit backend Open-Meteo calls to two concurrent requests. A 429 creates a
  shared process-local cooldown across forecast/archive call sites. Honor a
  valid Retry-After (bounded to 24 hours); otherwise use increasing 60-second to
  one-hour cooldowns. Waiting polygon workers recheck before sending requests.
  No endpoint rotation or automatic retry bypasses the provider quota.
- Route humidity, rainfall fallback and backend weather HTTP through the guard.
  Existing source/period validation and the exact 30-completed-day rainfall
  requirement remain intact. Unit conversion, ranking, NPK, approved crops,
  aggregation and model files are unchanged.
- Mobile distinguishes a known missing-model-input error from a proxy outage.
  It shows a short missing-readings message and does not imply that a rejected
  inference is still running. Unknown interrupted writes still recover by the
  original idempotency key, as documented in MOBILE_RECOVERY_FIXES.md.

This is an authorized repair to provider HTTP scheduling/caching after the
owner supplied the server failures. It is separate from the earlier UI-only
backend baselines. Do not overwrite those baselines to make their checks pass.
Five existing files are changed: environmental_pipeline.py, provider_cache.py,
rainfallDatasets.py, fastapi_app.py (weather fetch only), and tests/conftest.py
(isolate provider state). The new provider module/tests are included explicitly.

## Owner configuration and acceptance

Create or use an owned OpenWeather API key for Current Weather Data and enter
it privately in Render as `OPENWEATHER_API_KEY`, then redeploy the matching
backend. Do not paste the key into chat, Git or Flutter configuration. The
official API describes relative humidity in its current-condition response:
https://openweathermap.org/api/current .

A key being present does not prove validity, activation, quota or actual data
retrieval. Perform a new saved-farm analysis on the intended deployed build.
Confirm successful completion and the actual saved source metadata. Retest
same-farm/account recovery and the mobile fixes, not only `/health`.

Adding the key gives humidity another source; it cannot reset Open-Meteo's
existing quota or force complete recent rainfall. If the exact 30-day rainfall
series remains unavailable, analysis must still fail clearly until compatible
provider data are available. Do not repeatedly retry an exhausted daily quota.
No paid provider subscription is started by this change.

## Verification

```powershell
.\deployment\verify-provider-recovery.ps1
```

The combined verifier checks all non-provider backend hashes, full backend and
build-helper tests, full Flutter analysis/tests, the Firebase-configured Web
build and debug APK. It includes the pending Review Inbox and mobile UI fixes.
Agent run: 535 backend/build-helper tests passed, 5 warnings. Full Flutter and
live provider receipt remain owner-terminal/device checks. Scientific Phases
8-9 remain paused. No deployment is claimed for these fixes.
