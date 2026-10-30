# GeoSustain capstone fix plan

Created 28 October 2026 from the capstone gap review. This is a plan, not a claim that the fixes have been implemented. The owner's requested order places dataset-dependent NPK work in Phase 8, immediately before final evaluation and release.

## Purpose and scope

Complete the accepted capstone objectives with focused changes to the existing Flutter/FastAPI application. Preserve the working farmer, analyst and Super Administrator flows. Avoid a general redesign or unrelated features.

The baseline is the signed `ACCEPTANCE FORM.pdf` and the reviewed 144-page `GEOSUSTAIN_MANUSCRIPT.pdf` in Downloads. The separately revised outline is supplemental until confirmed as the accepted version. The detailed review is `C:/Users/jasph/Downloads/GeoSustain-Capstone-Gap-Review-2026-10-28.md`.

This folder is the current order for the eight gaps identified by that review. Older readiness/web plans and their evidence remain historical references; their unresolved applicable checks are carried into Phases 7 and 9. They are not deleted, marked passed, or automatically re-executed wholesale.

## Phase order

| Phase | Work | Completion requirement |
| --- | --- | --- |
| [0 - Baseline and requirements](PHASE_00_Baseline_and_Requirements.md) | Preserve the current work and map requirements to evidence. | Exact starting state and gap checklist recorded. |
| [1 - Roles and formal analysis workflow](PHASE_01_Roles_and_Formal_Analysis.md) | Align analyst review and farmer submission with the accepted scope. | Formal submissions require an owned saved polygon; point inspection stays distinct. |
| [2 - Seasonal assessment](PHASE_02_Seasonal_Assessment.md) | Connect the selected month to a saved seasonal summary. | Monthly baseline, recent conditions and calendar evidence stay separate and understandable. |
| [3 - Polygon statistics and heatmaps](PHASE_03_Polygon_Statistics_and_Heatmaps.md) | Implement spatial statistics, clipped layers and legends. | Results describe actual valid spatial coverage and stay inside the farm boundary. |
| [4 - Model evidence and evaluation tooling](PHASE_04_Model_Evidence_and_Evaluation.md) | Audit model provenance and prepare reproducible comparisons. | Existing claims are traceable or explicitly unresolved; no premature retraining. |
| [5 - Individual prediction explanations](PHASE_05_Individual_Explanations.md) | Add and verify local feature contributions. | Explanation matches the exact crop score, inputs, model and parcel aggregation. |
| [6 - Super Administrator controls](PHASE_06_Controlled_Administration.md) | Complete the specific management records promised in scope. | Validated, versioned changes affect their intended consumers and are audited. |
| [7 - Integrated app and device verification](PHASE_07_Integration_and_Device_Verification.md) | Exercise the role journey, exports, security and failure recovery. | A stable candidate is ready for scientific integration and final evaluation. |
| [8 - NPK datasets and final scientific validation](PHASE_08_NPK_and_Final_Scientific_Validation.md) | Integrate defensible nutrient evidence when available; finalize affected model validation. | Nutrient claims match the evidence; final model and explanations are revalidated if changed. |
| [9 - Final evaluation, manuscript and release](PHASE_09_Final_Evaluation_and_Release.md) | Collect actual evaluation results and publish matching artifacts. | Objective-by-objective evidence, completed manuscript results and final acceptance. |

NPK remains near the end. Phase 8 is the second-to-last phase. Obtaining and documenting the requested dataset can happen in the background without blocking independent earlier work.

## Interim nutrient behavior

- Keep CAGRO disabled under the current configuration. Do not make matching a prerequisite for environmental analysis.
- Preserve the current estimated N/P/K display and its provenance. Nitrogen sourcing and P/K heuristics are different; do not describe all three as measured SoilGrids nutrients.
- Keep NPK **Not assessed** until compatible observations and defensible crop criteria support a grade. Dataset arrival alone does not justify a Suitable status.
- Preserve current model behavior and saved snapshots while the data contract is unresolved. Do not retrain, convert units, invent observations, or assign regional defaults new scientific meaning.
- Current humidity/NDVI checks remain visibly labelled **Application screening**; they do not establish nutrient suitability or local model attribution.

## Dependencies and work that can proceed

Phases 0-3 establish the workflow and environmental contracts. Phase 4 audits the existing model and prepares an isolated experiment runner; it does not wait for new nutrient data merely to document missing evidence. Phase 5 can explain the existing model while retaining its legacy limitations, and must be rechecked if Phase 8 changes it. Phase 6 can proceed once the schema/version contracts are defined. Phase 7 tests those integrated changes.

Phase 8 needs documented nutrient sources, compatible methods/units and any required qualified agricultural review. Climate-period and training-data gaps identified in Phase 4 are separate dependencies and must also be resolved before replacing the production model. Obtaining NPK data alone does not clear those gates.

While Phase 8 is waiting, continue documentation preparation, non-nutrient verification, evaluation-instrument preparation and release tooling. Keep data-dependent checks pending. Final participant evaluation must identify the exact candidate; material later changes require affected retesting. Do not claim final scientific acceptance or change signed objectives to hide unavailable evidence. If the accepted study can conclude with clearly limited proxies, record that qualified/adviser decision and its limitations rather than fabricate dataset completion.

## Status and evidence

Use [EXECUTION_TRACKER.md](EXECUTION_TRACKER.md) as the live checklist and [EXECUTION_RULES.md](EXECUTION_RULES.md) for consistent execution. Store evidence only when work runs under `defense-evidence/capstone-fix-execution/phase-XX/`. Paths in this plan are proposed destinations, not existing proof.

Suggested states: `NOT_STARTED`, `IN_PROGRESS`, `CODE_COMPLETE`, `VERIFIED_LOCAL`, `PENDING_EXTERNAL`, `VERIFIED_TARGET`, `COMPLETE`. A phase with a missing gate remains partial even if its code is complete.

## Immediate next work

Phase 0's local baseline review is [recorded here](../defense-evidence/capstone-fix-execution/phase-00/README.md). Phase 1's [automated checks now pass](../defense-evidence/capstone-fix-execution/phase-01/README.md), including 373 backend tests, real SQL/API journeys, analyzer, 221 Flutter tests and web compilation. The separate manual UI journey remains pending. The owner requires each phase's issues and acceptance checks to be closed before advancing; Phase 2 has not started. NPK remains in Phase 8.
