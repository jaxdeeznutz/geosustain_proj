# Production nutrient contract audit

## Findings and flow

`fastapi_app.build_analysis_result` uses `environmental_pipeline.analyze_location`.
The provider cache retrieves `rainfallDatasets.get_soil_nitrogen`; the pipeline
computes P/K from its already retrieved NDVI, pH and elevation. The new contract
validates those values before the ordered DataFrame reaches Random Forest
`predict`/`predict_proba`. The exact contract is retained in each
`model_explanation.samples` entry. Polygon ranking retains every sample, without
averaging nutrient records into a fictitious measurement. CAGRO matching happens
after inference. `nutrient_layers` exposes the separate API layers; database
`result_snapshot` stores them and `enrich_history_rows` restores them unchanged.
The older `rainfallDatasets.get_ai_prediction` entry point also validates and
records the contract; numeric-only callers retain undocumented-provenance labels.

| Input | Source and existing preprocessing | Quality / unit | Training compatibility |
| --- | --- | --- | --- |
| N | SoilGrids nitrogen 0–5cm: raw / 100, multiplied by 6, rounded, clamped 20–120; backup OpenLandMap b0: raw multiplied by 0.7, rounded, clamped 20–120; otherwise configured default 80 | Estimated proxy or fallback default; physical output unit unverified | Legacy adapter accepted; scientific equivalence unverified |
| P | Existing NDVI/pH/elevation piecewise heuristic; clamp 20–72; configured default on missing inputs | Estimated proxy; physical unit unverified | Same limitation |
| K | Same heuristic; clamp 25–65; configured default on missing inputs | Estimated proxy; physical unit unverified | Same limitation |
| CAGRO N | Original reported N% or workbook OM-derived N%, unchanged | Historical reported observation or OM estimate; % | Not admitted |
| CAGRO P/K | Original reported values, unchanged | Historical observations; ppm; extraction methods/depth undocumented | Not admitted |

These formulas describe existing software, not validated agronomic conversions.
The former N `measured` flag was misleading and is now `estimated_proxy`.
No numeric formula, crop list, ranking rule, model binary or CAGRO raw value changed.
Existing N defaults remain admitted and explicitly labelled to preserve behavior.

`training/train_model.py` trains directly on CSV N/P/K and generated local ranges;
it does not establish physical units, analytical methods or a validated mapping
from these providers. Random Forest uses raw features (no nutrient scaler).
`crop_model_features.pkl` records names, not nutrient units. The loader hashes the
actual `crop_model.pkl` bytes as `MODEL_VERSION`; no scientific nutrient metadata
sidecar establishes equivalence. The new adapter version is separate from that
model hash and does not retroactively certify training. `crop_requirements.py`
contains environmental comparison criteria, no NPK conversion evidence.
The CAGRO JSON retains 31 observations and reconstructed locality anchors, not
original sample GPS. Matching does not establish present parcel soil chemistry.

## Additive API schema

- `soil_nutrients_observed`: existing schema/version, status and separate records;
  `used_for_prediction=false`. Each nutrient now additionally has `date` (source
  sample date or null), `sample_year` (source year or null), `compatible=false`
  and `used_for_prediction=false`. Existing value/unit/source/quality/method and
  row/file provenance are retained.
- `soil_location_match`: unchanged association status and per-record spatial provenance.
- `model_nutrient_inputs`: `schema_version=1`, `contract_version=legacy-nutrient-adapter-v1`,
  actual `model_version` hash (null when absent), `compatible_with_cagro=false`,
  `compatibility_scope=legacy_adapter_representation_only`,
  `scientific_compatibility=unverified`, `status` (`recorded` only when all samples
  have contracts; otherwise `not_recorded`), and `samples`.
- Each model sample has zero-based `sample_index`, `location` (recorded coordinates
  or null), and `nutrients` keyed N/P/K. These same nutrient objects are stored in
  `model_explanation.samples[].model_nutrient_inputs` at inference time.
- Each model nutrient includes `value`, `unit=legacy_model_scale_unknown_physical_unit`,
  `source`, `quality` (`estimated_proxy`, `fallback_default`, or `unavailable`),
  `method`, `date` (null: providers do not return observation dates), `compatible`,
  `compatibility_scope`, `scientific_compatibility`, and `contract_version`.
  `compatible=true` means accepted by this legacy adapter only; it does **not**
  mean validated training-unit equivalence. Missing/nonfinite values, foreign
  units, incompatible flags and missing required provenance are rejected before
  inference. No %, ppm or other physical unit is guessed for legacy outputs.
- `soil_model_warning`: explicit proxy/default, unverified training compatibility
  and evidence-only CAGRO warning. `legacy_model_nutrient_inputs` and `cagro_soil`
  remain available unchanged for existing clients.

## Limitations and rollout

Direct CAGRO-to-model mapping is unsupported. Scientific compatibility cannot be
fixed from the repository alone: source methods, training units, field association
and independent validation are missing. Numerical production predictions remain
unchanged for valid existing inputs. Model scores remain uncalibrated class scores.
No retraining, database migration or frontend migration is required for this
additive contract. Deploy/restart the backend. Old saved analyses remain readable
and need no rerun; rerun only to obtain newly recorded contract metadata. Do not
backfill provenance or relabel historic snapshots as validated measurements.

Run tests from the repository root:

```powershell
py -m pytest backend/tests -q -p no:cacheprovider
```
