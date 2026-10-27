# Phase 04: Fix resource states, refresh and large-record loading

[Plan index](README.md) · [Execution rules](EXECUTION_RULES.md) · [Issue crosswalk](ISSUE_CROSSWALK.md)

**Status:** PARTIAL — see current execution below.

**Goal:** Make loading, failure, empty, no-match and stale data visible and keep first-page fetching bounded.

**Primary skill:** [geosustain-web-data](skills/geosustain-web-data/SKILL.md). Read this skill before executing the phase.

**Dependencies:** [Phase 00](PHASE_00_Web_Baseline_and_Hosting.md)

Dependencies establish baseline/final acceptance order. Provider setup in Phase 01 does not block independent source fixes in Phases 02–05; its live gates remain open until completed.

**Issues owned:** WEB-09: Desktop history/report empty states can hide loading or fetch failures, WEB-16: History pagination limits rendered rows after downloading the entire history

## Relevant implementation

- [lib/main.dart](../lib/main.dart)
- [lib/api_service.dart](../lib/api_service.dart)
- [lib/web/widgets/web_common.dart](../lib/web/widgets/web_common.dart)
- [lib/web/screens/web_history_reports_screen.dart](../lib/web/screens/web_history_reports_screen.dart)
- [lib/web/screens/web_dashboard_screen.dart](../lib/web/screens/web_dashboard_screen.dart)
- [lib/web/screens/web_planner_queue_screen.dart](../lib/web/screens/web_planner_queue_screen.dart)
- [lib/web/web_admin_shell.dart](../lib/web/web_admin_shell.dart)
- [backend/fastapi_app.py](../backend/fastapi_app.py)

## External inputs and limitations

Actual compiled-browser network/memory measurements require a representative owned staging dataset and browser. Do not stress shared production or providers to create evidence.

## Work and acceptance

### W04-01: Give each resource explicit display state

Track and display first-load progress, valid empty, no search matches, refresh failure with stale rows and retry for history, saved analyses, reports, counts and trends. Replace swallowed errors with resource-specific state while preserving valid panels. Do not present an unavailable count as verified zero.

**Acceptance:** Controlled initial and refresh failures never look like successful empty lists. A retry recovers only the intended resources and retains valid data where appropriate.

**Evidence:** failure/empty/stale fixture cases and UI observations.

**Initial status:** NOT_STARTED.

### W04-02: Make refresh and navigation labels match actions

Make Refresh Data refresh the current resource or label it explicitly as weather refresh. Make History navigate when offered as navigation. Coalesce duplicate refreshes and guard stale responses when the owner, route or query changes.

**Acceptance:** Each control has one predictable action; old responses cannot overwrite a new query or account; success feedback corresponds to the request that actually succeeded.

**Evidence:** control/action matrix and delayed-response tests.

**Initial status:** NOT_STARTED.

### W04-03: Fetch desktop pages and searches from the server

Replace all-history bootstrap for the affected desktop list flows with bounded server query/filter/page requests. Keep total counts and analytic aggregates explicit and consistently scoped rather than calculating whole-account claims from one loaded page. Retain the already bounded admin implementation unless changed behavior is justified.

**Acceptance:** First page loads without retrieving every history page; full-dataset search remains correct; next/previous and changed queries have stable boundaries with no missing/duplicate rows.

**Evidence:** request-count/bytes evidence and server pagination/search regressions.

**Initial status:** NOT_STARTED.

### W04-04: Measure a realistic browser dataset and recovery

Agree the staging dataset, browser/network/host conditions and response budget before measurement. Exercise a large account, rapid query changes, empty results, offline/reconnect and expired token; record startup and first-page requests/bytes/latency rather than extrapolating SQL benchmarks.

**Acceptance:** The recorded first-page budget passes with bounded fetches and useful recovery; failures and unfinished runs remain visible instead of being counted as passes.

**Evidence:** browser network/latency/memory notes, dataset identity and outcomes.

**Initial status:** NOT_STARTED.

## Focused verification

- **WEB-09:** Simulate first-load failure and refresh failure independently: no false empty success, previous data is marked stale, and retry recovers the intended resource.
- **WEB-16:** With a representative large account, first-page request count and bytes stay bounded, search covers the full intended dataset and the recorded browser latency/memory budget passes.

## Exit and handover

Store actual execution under `defense-evidence/web-fix-execution/phase-04/`; start from [EVIDENCE_TEMPLATE.json](EVIDENCE_TEMPLATE.json). Link source/frontend/backend identity, expected versus actual results, test/provider/browser scope and remaining gates.

The phase is complete only when its full acceptance is supported. Source-only fixes can be handed on with pending live dependencies recorded; do not mark the whole phase complete from a build or plan file.

| Task | Current state | Evidence | Remaining gate |
| --- | --- | --- | --- |
| W04-01 | VERIFIED_LOCAL | Current execution below | Controlled initial and refresh failures never look like successful empty lists. A retry recovers only the intended resources and retains valid data where appropriate. |
| W04-02 | CODE_COMPLETE | Current execution below | Each control has one predictable action; old responses cannot overwrite a new query or account; success feedback corresponds to the request that actually succeeded. |
| W04-03 | VERIFIED_LOCAL | Current execution below | First page loads without retrieving every history page; full-dataset search remains correct; next/previous and changed queries have stable boundaries with no missing/duplicate rows. |
| W04-04 | REQUIRES_MANUAL | Current execution below | The recorded first-page budget passes with bounded fetches and useful recovery; failures and unfinished runs remain visible instead of being counted as passes. |

## Current execution

Added owner-scoped bounded history search, paginated history/report controllers, stale-query discard, explicit loading/error/no-match/refresh states and a separate whole-account summary endpoint. Local SQL proves owner/zero/preliminary aggregate and bounded-search behavior; controller tests prove delayed query isolation and stale-data preservation.

**Remaining:** Representative compiled-browser request/latency/memory budget and reconnect matrix; Hosted endpoint/frontend matching deployment

[Execution evidence](../defense-evidence/web-fix-execution/phase-04/README.md).
