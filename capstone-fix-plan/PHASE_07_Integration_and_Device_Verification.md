# Phase 7 - Integrated application and device verification

Dependency: implemented portions of Phases 1-6. Nutrient dataset-dependent checks remain deferred to Phase 8.

## Main journey

On a matched controlled candidate: farmer signs in, creates/opens an owned farm, captures or draws a boundary, reviews approximate area/accuracy, selects month, analyzes, inspects statistics/maps/explanation/limits, saves a draft and submits. Analyst opens the submitted evidence, reviews it, adds notes and records a decision. Farmer sees the decision/notes and reopens or exports the same evidence. Super Administrator manages the authorized records and views audit history.

## Additional checks

- Test cross-user/cross-role API access, stale boundaries, duplicate retries, expired sessions, failed providers, missing observations, no-result states and preserved historical results. Preserve working email-code verification behavior.
- Verify reports match screen/API snapshots, including scope, month, polygon, sources/periods, model/config versions, explanation, NPK limitations and decision history. Report preview is separate from actual export validation.
- Exercise Android permission refusal, approximate GPS accuracy, rotation/large text, offline restart, account switching and interrupted synchronization. Confirm no cross-account farm leakage or duplicate submission.
- Exercise supported analyst/admin browsers, keyboard/focus, narrow layouts, loading/error states and accessible status text. Collect a planned sweep before batching non-blocking cosmetic fixes.
- Confirm sign-in/recovery on the intended host/device. Credit the already recorded verification-email receipt correctly. Google/SMS/push infrastructure is not proven by local mocks; retain applicable prior requirements and their actual receipt/tap/lifecycle gates without adding unrelated providers.
- Measure representative polygon workloads and bounded provider failures. Verify durable job recovery, user-visible wait/retry behavior and relevant backup/restore procedures on controlled infrastructure.

## Evidence and acceptance

Record source/build/API identities, actual device/browser details, case outcomes and applicable original QA IDs under the phase evidence directory. Run focused checks after fixes and broader required checks before candidate freeze. No unsupported whole-project PASS follows from a backend test count.

Complete only the verified scope. Record unavailable devices/providers separately and continue independent tasks. If Phase 8 changes nutrients, model, criteria or reports, identify and rerun affected checks. This is stabilization before final evaluation, not final scientific or participant signoff.
