# Phase 3 - polygon raster statistics and maps

State: COMPLETE - OWNER ACCEPTED, 29 October 2026. [Closure record](closure.json). Phase 4 remains NOT STARTED. No push or deployment performed.

## Implementation and evidence

- [Contract](../../../docs/POLYGON_RASTER_ASSESSMENT.md): clipped geometry, area-weighted statistics, masks, units, metadata, bounds and map interpretation.
- [Independent arithmetic references](REFERENCE_CASES.md): known raster/full/concave/partial/tiny/constant/missing cases, derived separately from the reducer.
- `backend-tests.log`: 405 passed, four existing warnings; 22 targeted spatial/provider tests passed after final provider guard/quality-label edits.
- `sql-api-results.json`, `sql-api.log`: disposable actual PostgreSQL/API snapshot persistence and model-score/input/grade/NPK preservation passed.
- `phase01-regression/sql-api-results.json`: formal workflow and authorization regressions passed. Its log includes a nonfatal native-stderr deprecation warning.
- `attempts/20261029-123149-022/`: final analyzer, all 231 Flutter tests and web build passed. The earlier 360 px legend overflow is retained in its original attempt and remediated; no failed check was ignored.
- `candidate-source-hashes.json`: source identities verified against the final candidate; the existing model artifact hash is unchanged. Only completion documentation changed after client verification.
- `manual-observations.json` and `manual/`: owner Android NDVI, constant/coarse pH, unavailable rainfall, crop access, history/zoom, analyst parity and both actual export previews. Screenshot-visible facts and owner-reported actions are distinguished.
- `pdf-qa/final-footer/inspection.json`: generated fixture farmer/analyst reports rendered and inspected on all 17 pages; no clipped text, layer headings stay with maps, legends and saved metadata present. Actual owner reports have additional case/crop/seasonal content (13 farmer and 9 analyst pages).
- `baseline/` and `baseline-source-hashes.json`: Phase 3 entry copies/identities. Earlier phases and unrelated working-tree changes remain intact.

## Acceptance scope

Owner accepted both actual export previews with six screenshots and ?all goods?. This completes the local synthetic workflow scope. No successful real-provider retrieval, field measurement, agronomic validity, physical printing or deployed/installed-production parity is implied. Real raster adapter graphs and bounded REST/NPY decoding were checked offline; unavailable sources remain explicit. Optional grid/geometry limits and coarse-source limitations are documented in the contract.

The model and sampled inference semantics remain unchanged. Phase 4 model evidence work has not begun.
