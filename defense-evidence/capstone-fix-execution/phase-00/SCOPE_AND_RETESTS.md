# Baseline analysis scope and affected retests

This records the current starting behavior and proposed distinctions. It does not add fields or change the application.

| Case | Current behavior | Required distinction in later work |
| --- | --- | --- |
| Owned saved-farm polygon | Server chooses the stored farm geometry and records its boundary version; persistence checks current version. | Formal submission must additionally enforce owned active farm, matching analyzed polygon and boundary version. |
| Single point | Can return model-ranked estimates, with an empty selected polygon. | Preliminary inspection, clearly labelled and ineligible for formal farmer submission. Do not invent a farm polygon. |
| Unsaved drawn polygon | Can generate an account-owned analysis without a saved farm association. | Distinguish inspection from formal saved-farm assessment; do not silently associate a farm. |
| Legacy submitted case | Existing snapshots/review history may have missing farm or environmental metadata. | Remain readable with original limitations. Do not silently erase/regrade prior decisions or infer missing metadata. Define any transition handling explicitly. |
| Known water/built-up result | Existing land-cover blocking/advisory behavior. | Preserve bounded advisory scope; review does not establish crop suitability. |
| Unknown/unavailable land cover | Current estimates may proceed with an explicit unverified-land-cover warning. | Never present this as verified agricultural land. Preserve source/coverage warnings. |
| Estimated NPK | Model inputs/display are estimates with unverified physical-unit compatibility; CAGRO disabled. | Preserve values/provenance and Not assessed grades until Phase 8 has defensible compatible evidence. |
| Environmental factor grade | Compatible documented reference comparisons are distinct from model class scores. | Preserve measurement unit/period/quality protections and do not treat green factors as field validation. |
| Humidity/NDVI application check | Approved new local source labels legacy heuristic ranges as Application screening. | Preserve the distinction from agronomic validation, local model explanation and historical results lacking the new metadata. |

## Affected consumers to inventory before changes

- Farmer saved-farm analysis entry, point/manual inspection, result summaries, submission controls, drafts/history/saved records, status/notes and correction/resubmission.
- Analyst dashboard/sidebar/routes, submitted case map, review queue/workbench/checklists, historical account-owned records and report views.
- Super Administrator user/crop/reference/model/configuration controls and audit views.
- Analysis API and durable jobs, persistence/owner checks, submission and linked corrected-revision APIs, geometry/boundary validation.
- Snapshot normalization, ranking/model provenance, climate metadata, source/quality display and export helpers.
- Farmer/analyst printed/PDF/downloaded reports and reopened historical results. Screen-only labels do not prove report parity.

## Retest assignment

| Phase | Meaningful checks |
| --- | --- |
| 1 | Owned formal submission; point/unsaved/stale/archived/cross-user rejection; server-owned geometry; duplicate initial/corrected submission; old submitted record and review preservation; analyst/admin separation. |
| 2 | Selected-month baseline versus annual/current/recent periods; missing calendar/provider handling; saved/report parity; unchanged model score/rank. |
| 3 | Independent known-raster statistics; edge/irregular/small parcels; no-data masks/coverage; actual polygon clipping; accurate per-layer metadata; bounded workload. |
| 4 | Artifact/input identity; manuscript table traceability; independent partition/leakage controls; reproducible same-data DT/SVM/RF runner; unresolved scientific gates. |
| 5 | Correct class/feature/output mapping; contribution conservation; same parcel aggregation as ranking; unavailable attribution and stale context; saved/export parity. |
| 6 | Typed/versioned admin edits; direct API negatives; real consumer integration; audited actor/date; unchanged old snapshots and trusted artifact controls. |
| 7 | Complete controlled role journey; Android/browser/large text/accessibility; expired sessions/provider failure; offline account isolation/sync recovery; exact report parity; applicable actual provider receipt; security and bounded operations. |
| 8 | Dataset unit/method/depth/period/coverage validity; missing/incompatible nutrients remain unassessed; no CAGRO city block; affected training/model/explanation/display/report retests. |
| 9 | Matching signed APK/web/backend/source; actual evaluation participants/results; applicable QA closure; final manuscript tables/conclusions; controlled recovery/rollback and real acceptance. |

Regression references include `backend/tests/test_mobile_workflow.py`, `test_analysis_scope.py`, `test_legacy_npk_restore.py`, `test_climate_contract.py`, `test_model_ranking.py`, `test_explainability.py`, client analyst/operator/farm/result tests and the original dated QA register. A reference is not a new execution result.
