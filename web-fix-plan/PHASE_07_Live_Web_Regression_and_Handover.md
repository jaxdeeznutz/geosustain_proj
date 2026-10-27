# Phase 07: Deploy the matched fixes and reconcile web QA

[Plan index](README.md) · [Execution rules](EXECUTION_RULES.md) · [Issue crosswalk](ISSUE_CROSSWALK.md)

**Status:** PARTIAL — see current execution below.

**Goal:** Close only evidence-supported findings on a matched deployed release and deliver a truthful web-only acceptance decision.

**Primary skill:** [geosustain-web-final-qa](skills/geosustain-web-final-qa/SKILL.md). Read this skill before executing the phase.

**Dependencies:** [Phase 00](PHASE_00_Web_Baseline_and_Hosting.md); [Phase 01](PHASE_01_Web_Identity_and_Delivery.md); [Phase 02](PHASE_02_Analysis_Grades_Charts_and_Statistics.md); [Phase 03](PHASE_03_Responsive_Shell_Theme_and_Navigation.md); [Phase 04](PHASE_04_Data_States_Refresh_and_Pagination.md); [Phase 05](PHASE_05_Account_Actions_and_Web_Session_Security.md); [Phase 06](PHASE_06_Accessibility_and_Browser_Acceptance.md)

Dependencies establish baseline/final acceptance order. Provider setup in Phase 01 does not block independent source fixes in Phases 02–05; its live gates remain open until completed.

**Issues owned:** Final cross-phase regression and acceptance for WEB-01 through WEB-18; no additional finding invented.

## Relevant implementation

- [deployment/RELEASE_HANDOVER.md](../deployment/RELEASE_HANDOVER.md)
- [defense-evidence/web-live-2026-10-26/WEB_REVIEW.md](../defense-evidence/web-live-2026-10-26/WEB_REVIEW.md)
- [defense-evidence/readiness-execution/checklist-results.json](../defense-evidence/readiness-execution/checklist-results.json)
- [defense-evidence/readiness-execution/QA_CURRENT.html](../defense-evidence/readiness-execution/QA_CURRENT.html)

## External inputs and limitations

Real provider receipt, actual browser journeys, owned deployment/backup access, independent review where required and adviser acceptance of scientific claims remain external gates. Web acceptance does not complete deferred mobile criteria.

## Work and acceptance

### W07-01: Freeze the final tested candidate and run appropriate regression

Record source/frontend/API/model/rule/schema/config identities. Run the relevant Flutter and backend tests, analysis/lints and web build after changes, with the completed counts and command exit status. Repeat only affected checks after later changes and retain the seven-test review baseline as historical evidence.

**Acceptance:** The test results and delivered artifacts match the final candidate; build/local fixtures are not substituted for provider/browser acceptance.

**Evidence:** final manifest, test logs and build identity.

**Initial status:** NOT_STARTED.

### W07-02: Deploy and execute full real role journeys

Publish the matching frontend/backend through the existing authorized workflow. On controlled test identities, execute signup/recovery, analyst selection/analysis/save/report, planner decision/activity and admin users/audits. Include partial results, authorization denial and session/route/cache recovery. Capture a failed or unavailable step honestly.

**Acceptance:** Each required web journey finishes on the same candidate with correct permissions, truthful analysis and actual configured provider receipt; unmet dependencies remain open.

**Evidence:** end-to-end web case matrix with redacted live evidence.

**Initial status:** NOT_STARTED.

### W07-03: Rehearse staging rollback and verify operations

Use the named previous compatible release and backup to rehearse staging rollback/forward recovery including intervening writes and queued work. Verify actual monitor/alert receipt with authorized recipients and record operational ownership. Do not roll production backward merely to generate a test.

**Acceptance:** Timed recovery reconciles the documented data window and retains owned records; monitoring evidence distinguishes /health from /ready and actual action completion.

**Evidence:** staging rollback/forward recovery record and monitor receipt.

**Initial status:** NOT_STARTED.

### W07-04: Reconcile every web finding without rewriting history

For WEB-01 through WEB-18, record before/after, exact change, artifact and retest outcome. Compare affected original QA criteria before promoting any row; preserve all 191 IDs/instructions and history. A source fix may be complete while its live gate remains pending. Do not alter scientific FAILs or mark mobile checks passed because this web plan finished.

**Acceptance:** All 18 issues have traceable evidence or a precise open reason; original QA counts recompute from actual records with no unsupported status changes.

**Evidence:** finding closure register and scoped QA delta.

**Initial status:** NOT_STARTED.

### W07-05: Deliver the web handover and real acceptance decision

Provide web URL/build, role-specific operating steps, configuration ownership, known limits, rollback path and actual reviewer decisions. Preserve provider/scientific/browser/mobile scope distinctions. Keep evidence free of credentials, OTPs, device tokens and private farm payloads.

**Acceptance:** The owner can reproduce the offered web workflow and understands outstanding gates. No final sign-off or independent reviewer is invented.

**Evidence:** web handover, remaining-gates register and dated actual decisions.

**Initial status:** NOT_STARTED.

## Focused verification

- Retest all 18 findings on the matched deployed candidate and complete the required real role/provider/browser matrix.
- Use the installed computer-use skill only when an actual supported browser surface is available; otherwise record manual user steps/outcomes explicitly.

## Exit and handover

Store actual execution under `defense-evidence/web-fix-execution/phase-07/`; start from [EVIDENCE_TEMPLATE.json](EVIDENCE_TEMPLATE.json). Link source/frontend/backend identity, expected versus actual results, test/provider/browser scope and remaining gates.

The phase is complete only when its full acceptance is supported. Source-only fixes can be handed on with pending live dependencies recorded; do not mark the whole phase complete from a build or plan file.

| Task | Current state | Evidence | Remaining gate |
| --- | --- | --- | --- |
| W07-01 | VERIFIED_LOCAL | Current execution below | The test results and delivered artifacts match the final candidate; build/local fixtures are not substituted for provider/browser acceptance. |
| W07-02 | PENDING_EXTERNAL | Current execution below | Each required web journey finishes on the same candidate with correct permissions, truthful analysis and actual configured provider receipt; unmet dependencies remain open. |
| W07-03 | PENDING_EXTERNAL | Current execution below | Timed recovery reconciles the documented data window and retains owned records; monitoring evidence distinguishes /health from /ready and actual action completion. |
| W07-04 | COMPLETE | Current execution below | All 18 issues have traceable evidence or a precise open reason; original QA counts recompute from actual records with no unsupported status changes. |
| W07-05 | CODE_COMPLETE | Current execution below | The owner can reproduce the offered web workflow and understands outstanding gates. No final sign-off or independent reviewer is invented. |

## Current execution

All available web code implemented using eight phase skills. Passed 289 backend tests, 186 Flutter tests, nine affected theme/web checks, three hosted-builder regressions, clean Flutter analysis and real isolated PostgreSQL integration. Final application release build passed. GitHub main, Vercel manifest and Render health match e03c7a1. Downloaded hosted JS matches its manifest hash, and hosted application fingerprint matches committed Git blobs. Intended frontend/JS security and cache headers are live. Full provider/browser/role/scientific acceptance remains separate.

**Remaining:** Real owned email/Firebase/OAuth/SMS/web-push receipt remains unconfigured or unverified; /ready is 503 specifically because required email configuration is unavailable.; Complete hosted role, network/cache, browser and human accessibility acceptance remains open.; Staging rollback/forward rehearsal, actual alert receipt and configuration ownership are not demonstrated.; CAGRO methods/units/dates/farm selection and nutrient criteria require adviser/custodian input; mobile acceptance remains deferred.

[Execution evidence](../defense-evidence/web-fix-execution/phase-07/README.md).
