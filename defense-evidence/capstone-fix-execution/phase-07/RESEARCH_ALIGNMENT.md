# Phase 7 explanation summary candidate

Owner authorized Phase 7 on 2026-10-30, including the previously deferred concise
explanations and the request to explain why a crop is suggested and ranks first.
This is an implementation candidate; full client, rendered export and integrated
device/browser acceptance are pending. Phase 6 remains closed on its own evidence.

## Accepted requirement

The Phase 0 crosswalk FR-19 requires a summary covering supporting and limiting
factors, season, terrain, vegetation, alternatives and data-quality limitations.
NFR-08 requires understandable explanations with traceable evidence. The original
manuscript pages 15-16 discuss interpretation and these summary components;
pages 93 and 100 discuss compatible feature attribution, including SHAP. Extracts
from the supplied manuscript are retained in manuscript-explanation-excerpts.json.

The installed implementation remains the Phase 5 additive random-forest tree-path
class-probability decomposition, not SHAP. Reconcile the final method name and
evaluation in the manuscript during scientific validation/final documentation;
do not rename the actual method or imply a different algorithm was implemented.

## What the candidate explains

- Why this crop: its largest saved positive and negative model contributions.
- Why this rank: saved class score, comparison with the runner-up for first place
  or the leader for other crops, and the principal signed feature differences.
  Equal scores, zero scores and a single enabled crop have explicit wording.
- Research/reference fit: saved observations, compatible units/periods, saved
  preferred ranges and recorded grades, with source title, section, URL and scope.
  Missing criteria, citations or compatible observations remain not assessed.
- Saved season, calendar match, elevation, slope and vegetation in details/exports.
- Model uncertainty and nutrient estimates remain visible; full matrices, method,
  sample inputs and checksums remain available in details and both report types.

Condition comparisons do not set, justify as biological proof, or alter the RF
ranking. A top model score is not a harvest probability. A positive model rainfall
contribution cannot supply a missing annual-rainfall criterion. Controlled test
references remain software fixtures, not research or field validation.

## Primary sources checked 2026-10-30

[Palczewska et al., Interpreting random forest classification models using a
feature contribution method](https://arxiv.org/abs/1312.1121) describes individual
feature contributions to RF classifications. This supports the interpretation
method, not crop-specific agronomic validity or causal claims.

[FAO EcoCrop, Oryza sativa](https://ecocrop.apps.fao.org/ecocrop/srv/en/dataSheet?id=1574)
lists preferred temperature 20-30 C, annual rainfall 1500-2000 mm and pH 5.5-7,
with a wet-rice production-system scope. These match the existing frozen Rice
reference fields. No threshold was changed. The saved synthetic example has
27 C and pH 6 within those preferred ranges, and 2100 mm/year outside the preferred
rainfall range but within its recorded absolute range. This example tests software
behavior; it is not validation of a real parcel or provider.

The original accepted criteria and their other citations remain unchanged.
Phase 8 retains the scientific, dataset, nutrient and criteria evaluation work.

## Candidate checks and next step

Targeted Dart analysis passed for recommendation_summary.dart, local explanation
widget, crop-detail sheets, reference analysis and shared summary regression cases.
Full package execution in the agent environment is restricted by Pub-cache access.
The owner must run deployment/verify-phase-07.ps1. It records each actual outcome
under a dated attempt and cannot close the phase from automated checks alone.

New summary regression cases cover the saved score gap and signed differences,
reference evidence and limits, incompatible periods/units/proxy grades/citations,
saved controlled criteria/calendar revisions, immutable history and unavailable or
mismatched model explanations. Widget cases exercise the concise panel and citation
sheet at 360 px with normal/large text and at 1280 px. Report tests write actual
farmer and analyst PDFs to build/phase-07/export-qa for subsequent rendering.

After a passing full client run, render and inspect both updated PDFs, then record
the matched farmer/analyst/admin journey and the device/browser/provider checks in
PHASE_07_Integration_and_Device_Verification.md. No deployment, field validation,
provider receipt, participant evaluation or whole-project pass is implied here.
