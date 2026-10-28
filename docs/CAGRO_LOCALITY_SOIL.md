# CAGRO historical locality soil observations

Current admission/display policy: [restored estimated NPK analysis](LEGACY_NPK_RESTORE.md).
CAGRO matching remains a separate historical reference and is not required for
new model analyses inside the supported city boundary.

## Scope and scientific meaning

Nine reconstructed location anchors and 31 historical observation rows are stored
in `backend/data/cagro_locations.json` and `backend/data/cagro_observations.json`.
All nine locations have `original_cagro_gps: false`. Confidence describes the
user-supplied locality identification, not sample-point accuracy. The coordinate
notes are preserved as supplied; their external map sources were not provided
and have not been independently verified.

The workbook contributes 20 separate rows, with original address text and source
row numbers. Its rounded estimated N values are preserved, not recalculated.
The 2025 image transcription contributes 11 rows with reported N; these values
are **not** relabelled as OM-derived estimated N. No duplicate-address rows are
discarded, averaged or selected as the representative sample.

Units are those confirmed by the user: pH scale; organic matter and N in percent;
P and K in ppm. The workbook's N is estimated using approximately OM / 20.
Laboratory extraction methods, sample depth, exact sample dates and original GPS
coordinates remain unknown. Year 2025 is preserved only for the 2025 image rows.
The workbook resolves the ambiguous potassium punctuation in the older image;
the workbook is the recorded source for those rows.

## Stored locations and matching rules

| Catalog location | Precision | Confidence | Rule |
| --- | --- | --- | --- |
| FARM 1, DAPCO | barangay_anchor | low_medium | Reviewed DAPCO boundary |
| FARM 2, DAPCO | farm_area_anchor | medium | Reviewed DAPCO boundary |
| FARM 3, DAPCO | mapped_farm | high | Entire polygon within 250 m |
| PRK. CAIMITO, DATU ABDUL | barangay_area_anchor | medium | Reviewed Datu Abdul Dadia boundary |
| PRK. 1, NANYO | barangay_anchor | medium | Reviewed Nanyo boundary |
| PRK. RAMIHAN, DATU ABDUL | mapped_purok | high_medium | Entire polygon within 250 m |
| PRK. 6, TAGPORE | barangay_anchor | medium | Reviewed Tagpore boundary |
| BUENAVISTA | barangay_anchor | high_for_barangay | Reviewed Buenavista boundary |
| TAGPORE | barangay_anchor | high_for_barangay | Reviewed Tagpore boundary |

The **250 m** radius is a conservative application association rule for the two
mapped localities, not a scientifically validated soil-representativeness radius.
Every polygon vertex must lie within it; the matcher does not select the nearest
point to the centroid. Proximity does not establish ownership, exact sample
location or uniform soil conditions. A verified conflicting locality prevents
the proximity match.

Other anchors are never matched by coordinate distance. Matching them requires
full polygon containment in a reviewed locality boundary. Touching/crossing
edges, enclosed holes and overlapping conflicting locality claims are rejected.
Matching a barangay returns historical locality context, **not** a claim that
the selected farm is the named sample farm or purok.

All matched rows are returned separately. No interpolation, city-wide average
or model-input substitution occurs. A polygon is required; a point query,
unmatched polygon, invalid geometry or unreadable configuration returns
unavailable CAGRO observations.

## Reviewed locality boundary configuration

No verified barangay boundary dataset exists in this repository. Consequently,
the seven approximate anchors are stored but cannot match in production until
one is configured. Farm 3 and Ramihan proximity matching can operate without it.
Reverse-geocoder display labels, farm names and client request strings are
deliberately not used as verified geographic evidence.

Set `CAGRO_LOCALITY_BOUNDARIES_PATH` on the backend to a readable GeoJSON
FeatureCollection reviewed by a project administrator. Each feature requires:

- `properties.locality_id`: `dapco`, `datu_abdul_dadia`, `nanyo`, `tagpore` or `buenavista`.
- `properties.verified`: boolean `true`, only after checking the actual boundary.
- `properties.source`: a traceable source URL or dataset citation.
- Recommended: feature `id` and `properties.verified_on`.
- Geometry: a valid Polygon or MultiPolygon with closed longitude/latitude rings;
  interior rings represent holes.

Do not generate circles around anchors and label them barangay boundaries. This
file is backend-admin configuration, not an upload or user-selectable override.
This change adds no geographic web requests or new runtime packages.

## Model compatibility

Existing inference still uses N/P/K from `environmental_pipeline.py` and
`rainfallDatasets.py`. N from SoilGrids is divided by 100, multiplied by 6 and
clamped to 20–120; the backup also rescales/clamps its reading. P/K remain
formula-based proxies from NDVI, pH and elevation.

`training/train_model.py` uses Kaggle rows plus generated local profiles. The
training contract has N/P/K feature names but no validated mapping to CAGRO N%,
P ppm and K ppm or to the laboratory methods. For example, training N profile
values are on a tens-to-hundreds scale, not the workbook's fractional percent
scale. Numerical scaling alone cannot establish analytical compatibility.

The CAGRO snapshot explicitly records `compatible: false` and
`used_for_prediction: false`: the current production training representation is
**not directly compatible**, as confirmed by the project owner.
It does not mean the laboratory data is invalid. Do not convert or feed it into
the current model. Do not rescale, normalize, multiply, divide or otherwise convert CAGRO nutrients
to resemble legacy training values. Direct integration is allowed only after a
new compatible model is trained and validated; it is outside this implementation.
The existing model's soil pH and other environmental inputs also remain unchanged.

## Integration and persistence

The Farmer nutrient-reference display and its new additive schema are documented
in [CAGRO_NUTRIENT_REFERENCE.md](CAGRO_NUTRIENT_REFERENCE.md). No compatible
production crop N/P/K criterion has been established; historical values are
visible but remain **Not assessed**. Model nutrient inputs remain separate.

`fastapi_app.build_analysis_result` calls `lookup_soil_observations` once per
analysis after existing inference/land-cover screening. Its `cagro_soil` result
is preserved by the existing `analysis_sessions.result_snapshot` JSON field.
No database migration or changes to authentication, routes, rainfall retrieval,
model ranking, saved farms or reports are required.

Flutter adds an expandable **CAGRO historical soil observations** card to the
overview/key-factor views and the non-crop advisory view. It shows source address,
precision, locality confidence, reconstructed coordinates, original-GPS flag,
sample year/date availability, individual soil values with units, estimation
method and source row. These values are visibly separate from prediction inputs.

Old history records are not retroactively matched or rewritten. Deploy the
backend and frontend, configure reviewed boundaries if available, and run a new
analysis to save the new provenance. Records from failed/incomplete model runs
are not saved by this integration; existing analysis failure behavior is retained.

## Remaining limitations

- No original sample GPS, field validation, extraction methods or exact dates.
- No reviewed boundary dataset shipped; most anchors therefore remain unmatched.
- Multiple samples cannot be attributed to a specific farm polygon or current
  soil condition, even when their locality matches.
- CAGRO values do not add crop-specific suitability thresholds.
- Existing model nutrient proxies remain in use and are not improved by this
  display-only historical-data integration.
- Locality/matching rules are an association policy, not a soil interpolation
  model or an agronomic validation.

## Nutrient display terminology

- OM-derived N: **Estimated Nitrogen (%) derived from Organic Matter**.
- P: **Reported soil Phosphorus (ppm)**.
- K: **Reported soil Potassium (ppm)**.

The 2025 image rows supply reported N without an OM-derived method; they retain
**Reported Nitrogen (%)** rather than falsely claiming an OM derivation.
CAGRO observations remain distinct from **legacy model nutrient inputs/proxies**.

## Explicit API separation (schema version 1)

The additive production nutrient contract and its scientific limitations are
documented in [NPK_PRODUCTION_CONTRACT_AUDIT.md](NPK_PRODUCTION_CONTRACT_AUDIT.md).
`model_nutrient_inputs` records validated legacy-adapter provenance per inference
sample; legacy-adapter acceptance does not establish scientific compatibility.

New analysis snapshots additionally include:
- `soil_nutrients_observed`: status, used_for_prediction=false, and records.
  Every record has nitrogen/phosphorus/potassium objects with original value,
  unit, source, quality and method, plus source row/file and sample date/year.
- `soil_location_match`: status and one provenance entry per record_id with
  original address, anchor coordinates, precision, confidence, match type and note.
- `legacy_model_nutrient_inputs`: recorded inference samples with model_N,
  model_P and model_K in the unchanged legacy representation. Empty samples
  mean no inference inputs were recorded; no values are reconstructed.
- `soil_model_warning`: the explicit production-model incompatibility warning.

Arrays are intentional: multiple historical rows must not become a single
arbitrarily selected or averaged polygon nutrient vector. The existing
`cagro_soil` snapshot and UI remain backwards compatible. All new fields are
saved by the existing result snapshot mechanism. P/K methods display as not
documented; no crop suitability grades are assigned to these observations.

Inspection found base CSV ranges N 0-140, P 5-145, K 5-205. These are base data
ranges, not verified extrema of the deployed model training split (training adds
rows, filters and balances classes). CAGRO estimated N ranges 0.05-0.20%, reported
N 0.04-0.13%, P 5.85-86.83 ppm, K 0.13-6564.25 ppm across the stored sources.

## Future training contract (not activated)

A future model adapter may map a validated, explicitly associated record's
nitrogen.value to N_actual (%), phosphorus.value to P_actual (ppm), and
potassium.value to K_actual (ppm). That mapping is not implemented as a production
feature-vector path. Before activation:
1. Document analytical methods and compatible training units, and distinguish
   OM-estimated nitrogen from other nitrogen measurements.
2. Obtain defensible sample-to-field associations, dates, and observed crop/outcome
   labels; these historical locality records alone are not labelled training data.
3. Build a consistent dataset for all ten features; define missing-data handling
   and sample selection without invented conversions or crop labels.
4. Retrain and compare Decision Tree, SVM and Random Forest using spatial/temporal
   holdouts that prevent locality/sample leakage; validate per-crop performance
   and calibration against independent field evidence.
5. Version the feature contract, provenance, model and evaluation together; only
   switch the production adapter after validation and explicit release approval.

No training or inference algorithm is changed by this implementation.
