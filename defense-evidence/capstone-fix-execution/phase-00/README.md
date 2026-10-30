# Phase 0 - Baseline and requirements completed

Recorded 28 October 2026. **COMPLETE for local baseline/documentation scope.** No deployment, installed-device, scientific or user-acceptance PASS is implied.

## Starting candidate

- Branch: `defense/implementation-2026-10-23`.
- HEAD: `2eb82c725a2c50b64e3febfe610fe4958c11b75a`.
- The starting worktree already included the approved, uncommitted humidity/NDVI application-screening changes, their tests/documentation and unrelated user evidence. Those were preserved.
- [Original baseline](baseline.json) records the initial status and selected source/model/APK hashes. [Source inventory](source-inventory.json) identifies 224 tracked/required new source files. [Document identities](document-identities.json) identify the reviewed acceptance/manuscript PDFs without changing them.
- [Artifact inventory](artifact-inventory.json) records the APK and model/metadata identities available locally. The current APK's equivalence to the dirty source is **not established**. No local built web bundle was available at the checked paths. Live hosts and the installed phone were not inspected.

## Scope and requirement map

[REQUIREMENTS_CROSSWALK.csv](REQUIREMENTS_CROSSWALK.csv) contains all **36 functional and 14 non-functional requirements**, the accepted wording, current source locations, baseline finding, assigned phases and required verification. Rows are planning/traceability records, not 50 newly passed tests.

| Accepted objective / scope | Baseline observation | Planned closure |
| --- | --- | --- |
| Farmer mobile and analyst review | Core applications exist; analyst independent analysis extends the written scope and saved-polygon submission eligibility is not yet enforced. | Phase 1, then 7/9 acceptance. |
| Environmental integration | Retrieval/reference comparisons exist; monthly seasonality and complete polygon statistics/metadata need work. | Phases 2/3; nutrient work in 8. |
| DT/SVM/RF comparison | Comparison code exists; the manuscript table lacks a reproducible link to the deployed legacy artifact. | Phase 4 tooling/audit; final affected experiments in 8/9. |
| Explainable recommendations and maps | Rankings and global importance exist; local prediction attribution and clipped, fully described spatial layers are missing. | Phases 3/5; recheck changed models in 8. |
| ISO/IEC 25010 evaluation | Final respondent/evaluation results and test-table completion remain outstanding. | Phase 9, using the candidate stabilized in 7/8. |
| Super Administrator management | User/crop/audit functions exist; documented reference/calendar/source/model/configuration management is incomplete. | Phase 6, then 7/9 acceptance. |
| Nutrient limitations | Explicit proxies are permitted; missing compatible criteria must remain Not assessed. CAGRO is disabled by the owner's current instruction. | Preserve interim behavior; defer dataset-dependent changes to Phase 8. |

The signed acceptance form and its readable counterpart define the baseline. The additional revised outline is supplemental until its applicability is established. No objective, signature, dataset or participant result was changed or invented.

## Validation

- Restored baseline backend suite: **342 passed**, four dependency/deprecation warnings, 42.91 seconds. Command: `.\.tools\python\python.exe -m pytest backend/tests -q -p no:cacheprovider`.
- SDK execution check: Flutter could not open `C:\flutter\bin\cache\lockfile`; client tests and current compilation remain **not verified here**. Dart formatting is not a replacement for them.
- [Restoration verification](restoration-verification.json) confirms all originally hashed source/model/APK files match their pre-Phase-1 identities and the three new Phase 1 source files are absent from active paths.
- Crosswalk row numbers and source paths were checked: 36 FR + 14 NFR, with no missing referenced source paths.
- Existing authentication behavior and nutrient/model artifacts were preserved. No live database write, deployment, provider request, external message or APK installation was performed for this baseline.

## Phase 1 ordering correction

A Phase 1 draft was started after the initial baseline capture, before all Phase 0 documentation was finished. At the owner's correction, it was set aside in `.tools/phase-01-draft/` and the active source was restored to the recorded baseline. That draft is **not an implemented or accepted phase**. Its focused checks passed, but the full draft run had two roleless-fixture failures and Flutter remained blocked; these must be addressed if that draft is resumed. The draft was never committed, pushed or deployed.

## Preservation and rollback

[baseline-source.patch](baseline-source.patch) preserves the starting tracked application changes relative to HEAD. [baseline-new-source/](baseline-new-source/) preserves the four required new screening source/test/document files. The original narrower pre-phase patch is also retained.

To reconstruct the reviewed source, use an isolated checkout of the recorded HEAD, apply the baseline source patch, add the saved new baseline files and verify the source inventory. Check newline conventions when comparing byte hashes. Do not reset the user's live working directory or remove unrelated evidence. This is source recovery; no production database/deployment rollback was exercised or claimed.

## Carried acceptance and dependency register

- Preserve all original 191 QA rows and history. The older recorded distribution (69 PASS, 83 PARTIAL, 3 FAIL, 17 NEEDS-MANUAL, 19 N/A) describes its dated candidate, not this baseline's final acceptance.
- The six earlier N/A-to-applicable rows (`5.8`, `9.9`, `9.10`, `11.3`, `11.4`, `11.9`) retain their provider/identity/message acceptance obligations. Applicable Google/SMS/push receipt and lifecycle checks remain pending; no requirement is dropped here.
- Physical P02/REG02 passes remain dated evidence. OFF05 interruption/recovery and the full Android/browser/accessibility matrix remain pending for the final candidate.
- Actual verification-email receipt was recorded on 27 October. Completed recovery and other pending journeys are separate; do not repeat the stale claim that no verification email has ever been received.
- Dataset/source units, climate training periods, independent model/field validation and any qualified scientific review remain explicit Phase 4/8 dependencies. NPK data are not yet obtained.
- Candidate parity, live role journeys, reports, privacy/security, controlled backup/restore, operations and actual human signoff remain Phase 7/9 gates.

See [scope and affected consumers](SCOPE_AND_RETESTS.md) before resuming Phase 1. The next phase is Phase 1; it has not been resumed after this correction.
