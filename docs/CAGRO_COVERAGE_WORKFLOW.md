# CAGRO-supported formal analysis

## Before this change

Both formal analysis routes called `build_analysis_result`. That function checked
the Panabo study rectangle, retrieved environmental variables, ran the existing
Random Forest and only then called the CAGRO locality matcher. Thus an unmatched
farm could receive a completed model ranking with legacy N/P/K proxies. CAGRO
was optional historical evidence in the saved JSON snapshot. Farm mapping and
creation validated geometry but did not expose a CAGRO coverage decision.
The analysis center was a vertex average (including a duplicate closing vertex),
not an area-weighted polygon centroid. Reports omitted CAGRO provenance.

## New flow and admission rule

Saved server-owned farm polygon (or a newly supplied valid polygon) → geometry
validation → CAGRO coverage check → land-cover screening → environmental retrieval
and unchanged Random Forest → separate reference assessments → versioned saved
snapshot → Farmer/Analyst views and PDF report.

Both `/api/analysis` and `/api/mobile/analysis` enforce the same gate before any
provider retrieval or ranking. Client claims of coverage are ignored. When a farm
ID is supplied, its owned server geometry is authoritative. Unsupported requests
return HTTP 422 with code `cagro_coverage_unsupported` and the coverage decision
(mobile wraps these in `detail`). No ranking or successful analysis is saved.
Point-only requests cannot establish coverage. Map browsing and saving a farm are
still allowed. Invalid geometry/out-of-study-rectangle requests retain HTTP 400.
Reading/retrying an already completed idempotent request does not run new inference.
These are the active FastAPI routes used by Flutter and the repository's Render
configuration. The archived Flask `backend/app.py` is not the production entry
point and must not be deployed as an alternative formal-analysis service.

1. A reviewed, sourced GeoJSON locality boundary configured through
   `CAGRO_LOCALITY_BOUNDARIES_PATH` takes priority. The complete parcel must be
   contained, including edges and exclusion of holes. Crossing/outside parcels
   cannot fall back to proximity for that locality. Conflicting localities fail closed.
2. Without a reviewed boundary for that locality, only the existing `mapped_farm`
   or `mapped_purok` rules apply: every vertex within the existing 250 m limit.
   This is a locality association policy, **not** a scientifically established
   soil homogeneity radius or a barangay boundary. No thresholds were increased.
3. Approximate barangay/farm anchors do not qualify by proximity. No records,
   missing configuration, or ambiguous geographic evidence means no admission.

The repository ships no reviewed locality boundary polygons. Default eligible
reference locations are Farm 3, DAPCO (`mapped_farm`, high confidence), and
Purok Ramihan, Datu Abdul Dadia (`mapped_purok`, high_medium confidence). Confidence
describes reconstructed locality identification, not soil-sample precision.
All matching records are retained separately; no newest/first/average selection.

## API and snapshot schema

New analyses carry `analysis_schema_version = cagro-supported-analysis-v1`.
No database migration or rewrite of existing JSON snapshots is required.

| Field/endpoint | Meaning |
|---|---|
| `analysis_coverage.schema_version` | Coverage policy version above |
| `analysis_coverage.supported` | Server admission decision, boolean |
| `reason`, `message` | Decision explanation and historical/coverage limitation |
| `matches` | All matched record IDs, locality IDs/names, original source addresses (`location_name`), catalog name, reconstructed coordinates, precision/confidence, GPS availability, coordinate source, source file/row and match evidence |
| `matches[].match` | Existing method; proximity radius and maximum vertex distance, or reviewed boundary source/ID/review date |
| `locality_ids` | Distinct matched localities; no representative row implied |
| `matching_policy` | Human-readable matcher policy |
| `nutrient_source` | Panabo City CAGRO historical soil record only when supported; otherwise null |
| `used_for_model_prediction` | False: coverage does not change the RF feature contract |
| `nutrient_basis` | Explicit historical CAGRO vs legacy RF distinction |
| `historical_soil_notice` | Historical/locality-level limitation for both roles |
| `center_lat`, `center_lon`, `centroid_method` | Area-weighted polygon center in local planar lon/lat coordinates; not sample GPS |
| `area_m2`, `area_hectares` | Approximate farm area; not cadastral survey |
| `POST /api/mobile/analysis-coverage` | Authenticated informational preflight of `{polygon}`; current coverage plus center/area |
| `GET /api/mobile/analysis-coverage/catalog` | Authenticated catalogue: `reference_locations`, reviewed GeoJSON `boundaries`, policy `schema_version`, `note`; optional `error` when configuration unavailable |

Farm create/get/list/update responses also include current coverage and center.
That preflight status is distinct from the immutable coverage in a saved analysis.
Existing `cagro_soil`, `soil_nutrients_observed`, `soil_location_match`,
`model_nutrient_inputs`, `soil_model_warning`, and `soil_nutrient_reference`
retain their documented schema. Raw CAGRO files and nutrient units are unchanged.

## Model, scientific limitations, and XAI

CAGRO is **local historical evidence alongside the clearly identified legacy
Random Forest prediction path**. It is not directly passed to production RF and
no new model was trained. Available observations have neither sufficient compatible
analytical-method metadata nor supervised crop outcome labels. Nitrogen includes
OM/20 estimates and separately reported N; P/K ppm do not establish extraction
method compatibility. Do not infer crop thresholds or labels from training profiles.
All seven approved crops still have no compatible documented CAGRO N/P/K criterion;
nutrient reference statuses remain Not assessed.

Unchanged model artifact SHA-256/version:
`6dee915ad58e55e376bcfb5a74ecee9db086491cf5fe29a1b3149f5b45be9278`.
Ranking contract: `random-forest-probability-2026-10-14-v1`.
Features: `N, P, K, temperature, humidity, ph, rainfall, ndvi, elevation, slope`.
N/P/K use `legacy-nutrient-adapter-v1`, physical units unverified. Operational
climate contract `climate-periods-v1`: 30-day rainfall for RF, five-year mean
temperature, current humidity. Training period equivalence remains unverified.
Repository training provenance is Kaggle base rows with synthetic GIS features
and local crop profiles, not field-labelled CAGRO data. The existing retraining
guard remains in place. No artifact, metadata, crop list, or RF scores were altered.
Corrected polygon centroids may change sampling positions for a rerun; this is a
geometry correction, not a nutrient or reference-score adjustment to probabilities.

Published rainfall comparison remains the validated annual five-year mean in
mm/year against saved documented annual crop requirements. No 30-day annualization.
Other environmental retrieval, seasonality, land-cover checks, verification controls,
and native XAI remain. XAI is model-wide impurity importance, not causal per-farm
attribution; model version, prediction context, selected crop and score stay bound.

## UI, reports, deployment and old analyses

Farmer mapping offers server coverage preflight and an optional catalogue map.
Only reviewed polygons are shaded; reconstructed reference locations are markers,
without radius circles. Saved farm details show center, area and current coverage.
Farmer/Analyst analysis views show saved coverage, admission evidence, original
CAGRO rows and historical warnings. Reference comparisons remain separate from
AI Crop Ranking. New reports include coverage provenance, individual nutrient
values/units/methods/source rows, environmental comparisons and native XAI context.

Redeploy the backend and rebuild/redeploy Flutter mobile/web (including Vercel if
it hosts the Flutter web build). No retraining or DB migration is required. Do not
configure speculative boundaries to enlarge coverage. Review authentic new
boundary/soil evidence before adding it. No old saved analyses must be rerun merely
to read them; a new analysis is required to obtain a current coverage admission.
Older snapshots are explicitly labelled as lacking the new coverage decision.

## Validation commands

```powershell
.tools/python/python.exe -m pytest backend/tests -q -p no:cacheprovider
C:/flutter/bin/flutter.bat test test/analysis_coverage_test.dart test/annual_rainfall_display_test.dart test/model_explanation_test.dart test/cagro_nutrient_reference_test.dart test/cagro_soil_card_test.dart test/farm_geometry_test.dart test/analysis_scope_test.dart
```

Coverage tests exercise both APIs, stored-farm bypass attempts, reviewed boundary
priority/crossing, proximity acceptance/rejection, missing records, catalogues,
centroids, provenance persistence and legacy reading. Existing tests cover nutrient
unit admission/no substitution, model-score separation, annual rainfall, XAI and
analyst verification. Flutter tests cover shared role provenance, unsupported
warnings, API errors, map holes/no invented buffers, report values/PDF generation,
legacy farm history and annual rainfall reference cards.

Validation result: 205 backend tests and 59 relevant Flutter tests passed.
Backend warnings concern existing FastAPI/Starlette deprecations. PDF generation
passes; the existing built-in Helvetica font still warns about Unicode support.
No live provider, deployed UI, or production-database end-to-end test was performed.

## Defense rationale

**Why is analysis limited?** The available CAGRO soil information was provided for
specific locations. GeoSustain limits formal analysis to locations supported by
that local evidence, rather than assigning unsupported Panabo City NPK values to
the entire city. Additional areas can be supported when more validated CAGRO soil
records become available.

**Is this a limitation?** Yes. Geographic coverage is limited by the available
dataset. The restriction is also a data-integrity decision: historical local soil
evidence is never invented for unmatched farms. It does not make the legacy model
CAGRO-trained or establish exact current soil conditions within a farm.
