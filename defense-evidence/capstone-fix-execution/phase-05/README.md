# Phase 5 - local explanations complete

Owner accepted the local Phase 5 workflow on 2026-10-29. See [closure.json](closure.json),
[manual results](manual-results.json) and [method documentation](../../../docs/LOCAL_MODEL_EXPLANATIONS.md).

- 440 backend tests and real disposable PostgreSQL/API checks passed.
- Offline dependencies, Flutter analyzer, 247 Flutter tests and web build passed.
- Actual farmer/analyst PDF builders passed rendering and full saved-value checks.
- Owner mobile and analyst checks passed: crop-specific signed factors, alternatives,
  details, History, submission and both app report exports.
- Model, model metadata, ranking/pipeline and legacy estimated NPK sources are unchanged.

Wordy-copy and layout refinements were deferred to Phase 7 at the owner's request.
Draft files are preserved under `deferred-phase-07-ui`; active sources match the
passed candidate exactly. Do not overwrite future Phase 7 work blindly with that draft.

Failed test attempts remain recorded. Acceptance uses synthetic workflow inputs
and the unchanged real forest; scientific, provider and production validity are
separate later gates. No deployment or publication was performed.
