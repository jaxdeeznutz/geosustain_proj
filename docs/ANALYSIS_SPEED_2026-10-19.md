# Analysis latency and loading overlay

The active pipeline now reuses NDVI, pH and elevation observations for the existing nutrient proxies, avoiding three repeated GEE calls per sample. Nitrogen retrieval joins the existing four-worker provider pool instead of running after the other providers. The existing nine-point sampling and model ranking are preserved. No local soil data or retraining is introduced.

Successful provider values are cached in process using exact coordinates, capped at 2,048 entries. TTL: current weather 5 minutes, rainfall 15 minutes, NDVI 1 hour, climate baseline 6 hours, terrain/pH/nitrogen 24 hours. Failures and fallback results are not cached. Copies prevent downstream mutation. Restarts clear the cache. No user identity, saved analysis or crop-ranking result is cached here. Logs record source elapsed time and cache hits without coordinates or credentials.

The loading dialog uses the root navigator to cover pushed farm-detail pages and bottom navigation. Back/tap dismissal is blocked while the request runs; completion/failure removes this dialog only. A spinner and elapsed-time text describe waiting without invented percentages or stage completion. Compact screens can scroll the dialog.

Offline validation: backend suite passed (103 tests), four cache regression tests passed, Flutter analysis and existing navigation/mapping/session tests passed. Live latency is not yet measured; first requests still depend on provider speed and Render startup. Deploy both frontend and backend to see these changes online.

## Controlled before/after comparison

Compared the pipeline from commit 1f2155f with the optimized pipeline using the real saved Random Forest and fixed, mocked provider readings. No live provider credentials or production database writes were used.

Five regression cases passed: three environmental scenarios, a nine-sample parcel, and weather-cache expiry. Inputs were identical, top-five crop order was identical, and probabilities agreed within 1e-12 (scores within 1e-10 percentage points). Parallel forest accumulation yields machine-precision differences; unique explanation IDs also differ by design.

Provider-function invocations: 11 to 8 per cold sample; 99 to 72 for nine samples (27.3% fewer). A fully warm repeat required zero provider calls in the tested successful-provider scenario. These counts are not HTTP request counts or a measured percentage speedup.

When fixture humidity changed from 80 to 35, cached analysis retained 80 before the five-minute weather expiry. After expiry (301 seconds), refreshed inputs and model outputs matched the uncached baseline. Freshness delay is intentional and can affect predictions before expiry. Live runtime and production-provider parity remain unmeasured.
