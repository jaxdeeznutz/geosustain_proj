# Phase 02: Correct analytical results, charts and statistics

[Plan index](README.md) · [Execution rules](EXECUTION_RULES.md) · [Issue crosswalk](ISSUE_CROSSWALK.md)

**Status:** PARTIAL — see current execution below.

**Goal:** Ensure every web result and statistic expresses the evidence actually available, without fabricated distribution values or unsupported nutrient conclusions.

**Primary skill:** [geosustain-web-analysis](skills/geosustain-web-analysis/SKILL.md). Read this skill before executing the phase.

**Dependencies:** [Phase 00](PHASE_00_Web_Baseline_and_Hosting.md)

Dependencies establish baseline/final acceptance order. Provider setup in Phase 01 does not block independent source fixes in Phases 02–05; its live gates remain open until completed.

**Issues owned:** WEB-04: The analysis distribution graphic uses a fixed percentage, WEB-07: The main web results still mix model scores and suitability language, WEB-08: Some KPI names and denominators do not match their calculations

## Relevant implementation

- [lib/web/screens/web_dashboard_screen.dart](../lib/web/screens/web_dashboard_screen.dart)
- [lib/web/screens/web_analyze_screen.dart](../lib/web/screens/web_analyze_screen.dart)
- [lib/web/widgets/web_common.dart](../lib/web/widgets/web_common.dart)
- [lib/web/screens/web_history_reports_screen.dart](../lib/web/screens/web_history_reports_screen.dart)
- [lib/web/screens/web_planner_queue_screen.dart](../lib/web/screens/web_planner_queue_screen.dart)
- [lib/web/screens/web_trends_weather_soil_settings_screen.dart](../lib/web/screens/web_trends_weather_soil_settings_screen.dart)
- [lib/main.dart](../lib/main.dart)
- [lib/widgets/analysis_coverage.dart](../lib/widgets/analysis_coverage.dart)
- [lib/screens/reference_analysis.dart](../lib/screens/reference_analysis.dart)
- [backend/soil_nutrient_screening.py](../backend/soil_nutrient_screening.py)

## External inputs and limitations

Complete CAGRO-based nutrient grades still need compatible units/methods, an accepted sample-to-farm rule and documented crop criteria or validated model evidence. These are not replaced by code or analyst approval.

## Work and acceptance

### W02-01: Define one web analysis presentation contract

Inventory live analysis, map popup, historical detail, planner review and PDF fields. Document AI model score versus factor grade, full versus preliminary, unknown land cover versus non-arable evidence, and raw observations versus estimates. Reuse shared factor/coverage/CAGRO components where appropriate.

**Acceptance:** All result surfaces use the same definitions and retain source, period, units and missing-value meaning. Suitable/Limited/Not suitable/Not assessed are text labels, not just colors.

**Evidence:** field/label contract and representative fixtures.

**Initial status:** NOT_STARTED.

### W02-02: Remove invented distribution graphics

Replace the 5%/72% constant in _WebDistributionPanel with actual categories/counts from an explicitly scoped eligible dataset, or remove the panel until meaningful. Treat missing, zero, preliminary and not assessed distinctly. Do not treat the separate Crop Trends implementation as already fixed by this repair.

**Acceptance:** Empty data displays no invented segment. Different documented fixture distributions change the chart and visible counts correctly.

**Evidence:** dataset-to-chart assertions and before/after screenshots.

**Initial status:** NOT_STARTED.

### W02-03: Repair KPI and trend definitions

Choose labels and denominators that match calculations: recommendation frequency is not most suitable crop, verified requires status filtering, zero is not missing, and unique farm area is not the sum of repeated analysis areas. Make personal history versus reviewed submissions explicit; document tie and duplicate behavior.

**Acceptance:** Zero/missing/duplicate-farm/preliminary/pending/rejected/verified fixtures yield the documented totals, percentages and labels.

**Evidence:** metric definitions, calculation regressions and fixture outputs.

**Initial status:** NOT_STARTED.

### W02-04: Apply truthful factors and CAGRO states everywhere

Replace legacy '% final'/'% suitability' fallbacks that misrepresent model rank. Surface the shared coverage, factor status, source and uncertainty in the main workspace and historical detail as well as planner review. Keep unavailable NPK and unknown satellite states useful without labelling them complete or non-arable by default.

**Acceptance:** The same record has consistent scientific meaning in map, analysis, history, planner detail and export. No unsupported CAGRO substitution, unit conversion or score-to-grade invention is introduced.

**Evidence:** cross-screen fixture matrix and actual partial-result screenshots.

**Initial status:** NOT_STARTED.

### W02-05: Verify report provenance and analytic regressions

Check PDF output from the exact saved record, including original model/rule/source versions and partial outcomes. If PDF layout changes, use the installed PDF skill and render every affected page for visual inspection. Retest point/polygon admission and stale-score suppression using existing regression coverage.

**Acceptance:** Saved/exported content does not silently recompute history under current rules or upgrade a partial result; actual PDF pages are readable and claims match the screen.

**Evidence:** PDF/source identity, rendered affected pages and focused test logs.

**Initial status:** NOT_STARTED.

## Focused verification

- **WEB-04:** Empty history shows no fabricated segment; deliberately different fixture distributions produce matching segment values and visible counts.
- **WEB-07:** The same saved record has consistent meaning on every surface. Missing satellite/NPK evidence never becomes a negative soil/land diagnosis or a complete recommendation.
- **WEB-08:** Fixtures containing zero, missing, duplicate-farm, preliminary, pending, rejected and verified rows produce documented totals and labels.
- If an actual XLSX is reconciled, read the available spreadsheets skill; if PDF appearance changes, read the available PDF skill and render/inspect pages. Neither skill supplies missing scientific criteria.

## Exit and handover

Store actual execution under `defense-evidence/web-fix-execution/phase-02/`; start from [EVIDENCE_TEMPLATE.json](EVIDENCE_TEMPLATE.json). Link source/frontend/backend identity, expected versus actual results, test/provider/browser scope and remaining gates.

The phase is complete only when its full acceptance is supported. Source-only fixes can be handed on with pending live dependencies recorded; do not mark the whole phase complete from a build or plan file.

| Task | Current state | Evidence | Remaining gate |
| --- | --- | --- | --- |
| W02-01 | CODE_COMPLETE | Current execution below | All result surfaces use the same definitions and retain source, period, units and missing-value meaning. Suitable/Limited/Not suitable/Not assessed are text labels, not just colors. |
| W02-02 | VERIFIED_LOCAL | Current execution below | Empty data displays no invented segment. Different documented fixture distributions change the chart and visible counts correctly. |
| W02-03 | VERIFIED_LOCAL | Current execution below | Zero/missing/duplicate-farm/preliminary/pending/rejected/verified fixtures yield the documented totals, percentages and labels. |
| W02-04 | CODE_COMPLETE | Current execution below | The same record has consistent scientific meaning in map, analysis, history, planner detail and export. No unsupported CAGRO substitution, unit conversion or score-to-grade invention is introduced. |
| W02-05 | VERIFIED_LOCAL | Current execution below | Saved/exported content does not silently recompute history under current rules or upgrade a partial result; actual PDF pages are readable and claims match the screen. |

## Current execution

Replaced the fixed distribution with real counted model score bands; retained valid zero and excluded preliminary/missing scores. Added owned whole-history SQL aggregates with explicit cumulative-area/frequency labels. Shared coverage/CAGRO/model/factor views now appear in main web results and history. Removed misleading model-score suitability labels from map/planner/trends. Real isolated SQL and focused calculation/widget checks passed.

**Remaining:** Exact final compiled-browser/PDF cross-screen smoke; Independent scientific acceptance for complete CAGRO nutrient claims remains external

[Execution evidence](../defense-evidence/web-fix-execution/phase-02/README.md).
