# Execution tracker

Plan created: 28 October 2026. Phase 0 has now been executed for local baseline/documentation scope. A prematurely started Phase 1 draft was set aside after the owner's correction; the active source matches the starting baseline. Previously completed features and test runs are not blanket acceptance of later phases.

| Phase | State | Required evidence / unresolved dependency |
| --- | --- | --- |
| 0 - Baseline | COMPLETE - LOCAL BASELINE | [Evidence](../defense-evidence/capstone-fix-execution/phase-00/README.md): 50 requirement rows, source/artifact identities, source recovery records and 342 restored-baseline backend tests passed. Flutter/device/live parity remain explicit pending later gates. |
| 1 - Scope and formal workflow | COMPLETE - OWNER ACCEPTED 2026-10-29 | 373 backend tests, isolated SQL/API negatives, analyzer, 221 Flutter tests and web build passed. Owner emulator/browser screenshots demonstrate submission, review and farmer-visible approval/feedback. Owner explicitly confirmed the preliminary-inspection check and signed off Phase 1. See the manual record for distinctions between screenshots, owner reports and automated-only negatives. |
| 2 - Seasonality | COMPLETE - OWNER ACCEPTED 2026-10-29 | [Closure evidence](../defense-evidence/capstone-fix-execution/phase-02/closure.json): 383 backend tests, SQL/API checks, analyzer, 226 Flutter tests and web build passed. Owner manual checks and both reports accepted; source identities and unchanged model verified. Real monthly-provider probe returned unavailable, handled explicitly without a positive scientific claim. No push/deployment; Phase 3 started after owner authorization. |
| 3 - Spatial analysis | COMPLETE - OWNER ACCEPTED 2026-10-29 | [Closure evidence](../defense-evidence/capstone-fix-execution/phase-03/closure.json): 405 backend tests, 22 targeted provider/spatial followups, isolated SQL/API and formal-workflow regressions passed. Final analyzer, 231 Flutter tests and web build passed. Independent polygon arithmetic, saved snapshot parity, Android/analyst map checks, history/zoom/crop-access checks, rendered PDFs and both owner app exports accepted. Model unchanged; synthetic local acceptance, no live-provider/field validation or deployment claimed. |
| 4 - Model evidence | COMPLETE - LOCAL AUDIT / TOOLING VERIFIED 2026-10-29 | [Closure evidence](../defense-evidence/capstone-fix-execution/phase-04/closure.json): local artifact/data/Table 13 audit, leakage-safe grouped DT/SVM/RF runner, all five metrics/per-class/confusion/uncertainty/timing outputs and exact controlled replay passed; 421 backend tests and static checks passed. Production model/data and Phase 3 sources unchanged; training guard remains active. Table 13 origin, scientific inputs/selection and live runtime parity stay explicit later gates (Phases 8/9 and integration). |
| 5 - Local explanations | COMPLETE - OWNER ACCEPTED 2026-10-29 | [Closure evidence](../defense-evidence/capstone-fix-execution/phase-05/closure.json): 440 backend tests, real disposable SQL/API snapshot/failure checks, analyzer, 247 Flutter tests and web build passed. Both rendered reports match all saved crop baselines/scores/contributions. Owner mobile, analyst, History, submission and both actual app exports accepted. Model/ranking/NPK unchanged; wording/layout refinements deferred to Phase 7. |
| 6 - Administration | COMPLETE - OWNER ACCEPTED 2026-10-30 | [Closure evidence](../defense-evidence/capstone-fix-execution/phase-06/closure.json): 475 backend tests, real disposable SQL/API migration/revision/activation/audit/consumer checks, analyzer, 254 Flutter tests, web build and rendered report parity passed. Owner create/activate, invalid-date correction, old/new calendar snapshots, fixed History expander, audit and both actual exports accepted. Model/ranking/attribution/NPK unchanged; trusted model installation remains developer-maintained. |
| 7 - Integrated verification | COMPLETE - LOCAL OWNER ACCEPTED 2026-10-30 | [Closure evidence](../defense-evidence/capstone-fix-execution/phase-07/closure.json): 489 backend tests, 266 Flutter tests, analyzer/web build, owner multi-role journey, saved exports, browser/GPS/rotation/large-text/offline/account isolation, exact test-export parity and real disposable SQL queue/retry/restore checks passed. Original model unchanged. Applicable live-provider, physical-device and production-release gates remain explicit in RELEASE_GATES.json; no broad 191-row or scientific signoff. |
| 8 - NPK and scientific validation | PAUSED - OWNER REQUEST 2026-10-30; DATA/METADATA PENDING_EXTERNAL | Intake preparation is retained. Owner has no new NPK data and requested a break from remaining phases to redesign the analyst web dashboard/pages. Runtime nutrients and model remain unchanged. |
| 9 - Evaluation and release | PAUSED / NOT_STARTED - OWNER REQUEST 2026-10-30 | Owner paused remaining phases while NPK data are unavailable and selected analyst web redesign. Evaluation, matching releases, rollback and signoff remain uncompleted. |

## Requirement coverage

These objective labels summarize the manuscript's five objectives; copy exact accepted wording into the Phase 0 crosswalk before execution.

| Objective | Main phases | Evidence required |
| --- | --- | --- |
| Mobile farmer app and analyst review | 1, 7, 9 | Saved farms, formal submission, authorized review, notes/status and complete role journeys. |
| Environmental/soil/climate/terrain integration | 2, 3, 8 | Compatible observations, seasonal evidence, polygon statistics, truthful nutrient limitations. |
| Compare DT, SVM and RF | 4, 8, 9 | Reproducible same-data evaluation and traceable production-model selection. |
| Explainable recommendations and visualizations | 2, 3, 5, 8 | Local contributions, alternative-crop context, spatial maps and preserved limitations. |
| ISO/IEC 25010 evaluation | 7, 9 | Approved instrument, actual participants/results, system evidence and objective conclusions. |

Super Administrator and data-integrity requirements cut across Phases 1, 6, 7 and 9.

## Execution entry template

- Phase/task:
- Date and source revision / working-tree delta:
- Requirement or review finding:
- Changes made:
- Validation command or user task:
- Actual outcome and evidence path:
- External dependency / untested behavior:
- Affected historical data, clients and reports:
- Rollback or recovery note when applicable:
- Next action and state:
