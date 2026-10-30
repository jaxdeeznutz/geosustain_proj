# Phase 1 - Roles and formal analysis workflow

29 October 2026. **COMPLETE - OWNER ACCEPTED.** Analyzer, all 221 Flutter tests, web build and 373 backend tests passed. Owner emulator/browser evidence shows saved-farm submission, analyst approval and farmer-visible feedback; the owner reported the preliminary-inspection check passed and explicitly authorized Phase 2. See MANUAL_JOURNEY.md for the precise distinction between screenshots, owner reports and automated-only negatives.

## Implemented

- The analyst dashboard, sidebar and submitted-case map use the review workflow. Independent area selection/new analysis actions are unavailable. An old analysis URL displays a review-only notice. Existing analyst account-owned records/reports remain readable.
- New inference is farmer-only, enforced before synchronous or queued work and again in worker execution. This does not change login, passwords or verification providers.
- Formal submission checks the owned draft and farmer role, then the owned active saved farm, valid analyzed polygon, snapshot geometry and boundary version. Session/farm locks protect the transition against concurrent changes.
- Updated farmer clients include the expected boundary version. Stale versions, a replacement accompanying polygon and invalid geometry fail before inference; older requests still cannot override server-owned farm geometry.
- Point/unsaved-polygon results retain their estimates and model scores, but save explicit inspection scope and cannot enter formal review. Result screens and shared report text disclose that scope.
- Corrected linked revisions use the same formal eligibility checks. Stale/archived candidates are excluded. Earlier revisions stay immutable.
- Already submitted/decided retries preserve status, notes and events. Historical incomplete records remain readable, with notices instead of invented farm information. A historical case without a farm link cannot offer an impossible linked correction; the farmer is directed to a new formal case.
- Existing self-review protection is retained. No NPK formula, CAGRO flag, crop model artifact, seasonal ranking adjustment or authentication-provider configuration was changed.

Implementation details: [formal analysis workflow](../../../docs/FORMAL_ANALYSIS_WORKFLOW.md) and [analyst workflow](../../../docs/ANALYST_WORKFLOW.md).

## Acceptance matrix

| Gate | Actual evidence | State |
| --- | --- | --- |
| Owned saved-polygon draft -> submission | Real SQL/API run on verified disposable instance; controlled inference | PASS |
| Concurrent first submissions / retries | One review case/submitted event; decisions and notes preserved | PASS |
| Point / unsaved polygon blocked from formal review | Saved inspection scope and HTTP 409 submission rejection | PASS |
| Stale/replaced/invalid boundary and archived farm | Regression tests plus actual SQL/API negatives | PASS |
| Owner and role boundaries | Foreign reads/submissions/inference denied; farmer cannot access queue; analyst cannot access admin or start inference | PASS |
| Information request -> linked correction -> verification | New current-boundary revision; old revision unchanged; farmer sees verified status/notes | PASS |
| Rejection notes and self-review | Actual rejected status/notes visible to owner; promoted analyst's own earlier case denied | PASS |
| Historical incomplete submissions | Original status/notes retained; no invented farm link; retry does not mutate history | PASS - SQL/API |
| Broader operator behavior | Existing isolated SQL suite: checklist/reason requirements, stale reviewers, follow-ups, bounded 500-case map/inbox and aggregates | PASS |
| Backend regression and static checks | 373 tests passed, four dependency/deprecation warnings; Ruff F and diff whitespace checks passed | PASS |
| Client formatting | Changed Dart files parse/format under Dart 3.11 | PASS - formatting only |
| Flutter analyzer | Owner run `20261028-094446-202`: No issues found; exit 0 | PASS |
| Full Flutter tests | Same run: all 221 tests passed, including repaired dashboard selectors and offline tile fixtures; exit 0 | PASS |
| Web compilation | Same run: HTTPS-API web build completed; exit 0 | PASS |
| Separate manual UI journey | Owner-run local emulator/browser workflow and explicit Phase 1 signoff; scoped evidence recorded in MANUAL_JOURNEY.md | OWNER ACCEPTED |

The SQL harness uses the existing verified disposable PostgreSQL target and creates/drops only its random schema. Environmental inference is a controlled fixture. No production farm/account record, external email/push delivery or deployed host was involved. These passes are not field/scientific or installed-device validation.

## Evidence

- [SQL/API results](sql-api-results.json): explicit successful cases, including initial submission concurrency.
- [Synthetic review fixture](synthetic-review-report.json): output of the existing controlled operator workflow suite. Synthetic values only.
- `local-validation.json`: observed local commands/results, invariant hashes and source state.
- [Client validation](client-validation.json): latest owner-run analyzer/tests/web-build outcome; all three exit codes are zero and `checks_passed` is true. This does not establish the separate manual journey.
- [Manual journey checklist](MANUAL_JOURNEY.md): final unconfirmed Phase 1 check; record the exact client/backend candidate and actual outcomes.
- `attempts/`: retained client failure/rerun history where available. Do not erase initial failure history after a successful retry.

## Automated checks passed

In the VS Code PowerShell terminal:

```powershell
cd C:\Users\jasph\Downloads\GeoSustain-mobile-update
.\deployment\verify-phase-01.ps1
```

The script ran successfully for this candidate. Repeat it after relevant changes; it stops on failure and retains dated evidence. It does not push or deploy. Final manual acceptance is listed separately below and in the checklist.

## Owner acceptance

The owner completed the local farmer/analyst approval and feedback journey, reported the unsaved-inspection outcome, and accepted Phase 1 on 2026-10-29. Stale geometry and other role negatives have automated SQL/API evidence; individually unobserved manual steps are identified in MANUAL_JOURNEY.md. Phase 2 may proceed under the owner's explicit instruction.

The successful web build does not update the deployed backend/site or Android APK. An older installed/live candidate cannot certify these new source changes. Broader deployment, device, provider and final evaluation gates remain in their planned later phases.

No commit, push or deployment has been performed for this phase. No database migration is needed. Rollback means restoring the Phase 0 source baseline and its saved uncommitted screening files, while preserving existing production records; this phase has not changed them.
