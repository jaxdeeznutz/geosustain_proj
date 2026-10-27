# GeoSustain detailed web review

Date: 2026-10-27. Scope: web operator/analysis/planning workflow. NPK and soil pH changes, replacement dataset integration and retraining are on hold at the owner's request while external dataset requests are pending.

## Assessment

GeoSustain has a useful analysis-and-review foundation. The next release should prioritize a clear operational workflow: an analyst prepares and explains an analysis; a planner reviews the submitted evidence, records a decision and follows up. One Agricultural Planning Analyst account can perform both responsibilities through clearly separated workspaces.

The current portal is stronger as an analysis viewer than as a day-to-day review inbox. Its personal dashboard, map, review queue and result detail still apply different scopes, state handling and terminology. The most useful next work is workflow and evidence consistency; the held soil datasets do not block that work.

## What was actually checked

- Read the current checkout, including operator navigation, analysis workspace, planning map, review queue/dialog, shared state, API pagination and server review transitions.
- Rechecked public frontend build identity, API revision and readiness; see [the timestamped snapshot](public-deployment-check.json).
- The checked live frontend and backend report e03c7a1. Frontend/API HTTP success does not establish real email delivery; readiness remains HTTP 503 specifically for email_configuration=unavailable, while database/model are ready.
- The earlier implementation run recorded 289 backend and 186 Flutter tests, followed by focused theme/host-builder checks. Those are historical test scopes; no full suite or authenticated live operator journey was rerun for this review.
- Source-confirmed observations, proposed workflow gaps and layout/control-flow risks are identified separately. Original 191-row QA statuses and prior evidence remain unchanged.
- This review adds documentation only. No application code, configuration, database or deployment was changed.

## Foundations to retain

1. The frontend has a public build identity and the API identifies its revision, making reports traceable to a real release.
2. The combined operator role is already explicit. Keep one canonical role and improve the workspaces before adding more account types.
3. Shared coverage/explanation/factor components, model-score statistics and a whole-owned-history summary exist. Extend their consistent use to the remaining legacy queue/map sections.
4. Server-side queue/detail access excludes never-submitted farmer drafts. Review decisions update currently pending farmer submissions only; an already-decided case cannot simply be flipped by another request.
5. Review decisions already write audit activity and queue notification work transactionally. Extend the existing event path for information requests and revisions.
6. Analysis snapshots, submitted timestamps and version fields already exist. They are useful building blocks for historical review evidence.

## Priority findings

P1 means resolve before claiming a reliable analyst/planner acceptance workflow. P2 means the next usability/operational improvement. These priorities are review recommendations, not replacements for original QA statuses.

### AP-01 ? Operator dashboard measures personal analysis activity, not review workload

**Priority:** P1 ? **Basis:** SOURCE_CONFIRMED

The dashboard uses owned history and the owner-scoped summary endpoint. Review counts are a separate queue resource. This is valid personal activity reporting, but it does not answer how many farmer submissions need attention.

**Recommended change:** Add a Review overview with pending cases, oldest submitted age, information requests, reviewed this period and unavailable/partial evidence. Keep My analyses as a separately named scope.

**Acceptance:** An operator with zero personal analyses and several pending farmer submissions sees the pending workload accurately.

**Source:** [lib/web/screens/web_dashboard_screen.dart:32](../lib/web/screens/web_dashboard_screen.dart), [backend/web_summary.py:18](../backend/web_summary.py), [backend/database.py:1448](../backend/database.py).

### AP-02 ? Planner queue still calls a model score SUITABILITY

**Priority:** P1 ? **Basis:** SOURCE_CONFIRMED

The queue card reads compatibility_pct directly and labels it SUITABILITY. New shared detail sections call ranking values model scores, so the two views still disagree.

**Recommended change:** Use Model score only where a valid scored crop result exists. Show preliminary/unassessed explicitly and keep review decisions in a separate badge.

**Acceptance:** The same session has consistent score meaning in inbox, detail, map and export; a missing score remains unassessed.

**Source:** [lib/web/screens/web_planner_queue_screen.dart:497](../lib/web/screens/web_planner_queue_screen.dart).

### AP-03 ? Heatmap color semantics use local min/max for every displayed layer

**Priority:** P1 ? **Basis:** SOURCE_CONFIRMED

The review heatColor function scales each layer by the values in that record and maps higher relative values to green. Equal values use t=.75, also producing green. This displays relative magnitude, not a demonstrated favorable condition.

**Recommended change:** Give each non-soil layer its own units and numerical legend. Use a neutral sequential palette for measured magnitude and a separately documented assessment palette only when a valid grading rule exists. Preserve missing cells. NPK and soil pH remain outside this work.

**Acceptance:** A uniform-value grid cannot imply universally favorable conditions. Different parcels using a shared legend remain comparable.

**Source:** [lib/web/screens/web_planner_queue_screen.dart:659](../lib/web/screens/web_planner_queue_screen.dart).

### AP-04 ? Legacy fallback text infers limited vegetation/non-arable surface from any NDVI value

**Priority:** P1 ? **Basis:** SOURCE_CONFIRMED

When the non-crop fallback has any numeric NDVI and no explanation bullets, it inserts the same limited-vegetation/non-arable wording without inspecting the NDVI magnitude or why the result is incomplete.

**Recommended change:** Show the recorded value, its period and available coverage. Explain the actual reason a crop result is unavailable. Keep land-use or field confirmation separate.

**Acceptance:** A partial result with a positive numeric NDVI does not receive a conclusion triggered only by the presence of that number.

**Source:** [lib/web/screens/web_planner_queue_screen.dart:759](../lib/web/screens/web_planner_queue_screen.dart).

### AP-05 ? Rejection reason is required by the UI but not by the review API

**Priority:** P1 ? **Basis:** SOURCE_CONFIRMED

The dialog requires a nonempty rejection note. VerifySessionBody accepts optional notes, and the endpoint/database decision path does not enforce the same note requirement. The existing pending-only database update is a useful safety guard.

**Recommended change:** Enforce decision reason and note constraints server-side, matching the UI maximum. Return an explicit conflict for an already-decided case and preserve the first decision.

**Acceptance:** A direct authenticated API rejection with a blank note is refused. Two reviewers cannot overwrite one another; the second sees the current decision.

**Source:** [lib/web/screens/web_planner_queue_screen.dart:667](../lib/web/screens/web_planner_queue_screen.dart), [backend/fastapi_app.py:1841](../backend/fastapi_app.py), [backend/database.py:1398](../backend/database.py).

### AP-06 ? No explicit information-request and revision-linked resubmission flow

**Priority:** P1 ? **Basis:** WORKFLOW_GAP_CONFIRMED

The inspected review endpoint offers verified/rejected. Reposting an already rejected session returns its existing decision rather than reopening it. Retaining decisions is correct, but there is no explicit needs-information case lifecycle in these endpoints.

**Recommended change:** Add Request information with required correction items, a farmer response and a linked new revision. Preserve the reviewed analysis snapshot and decision history.

**Acceptance:** A farmer can address a requested correction and submit a new linked revision without erasing the previous reviewer decision.

**Source:** [backend/fastapi_app.py:1841](../backend/fastapi_app.py), [backend/database.py:1135](../backend/database.py).

### AP-07 ? Review inbox pagination still downloads all pages first

**Priority:** P1 ? **Basis:** SOURCE_CONFIRMED

The server supports bounded queue pages and q search, but getPlannerQueue calls the shared _pagedList loop until has_more is false. The screen then searches and paginates the complete loaded list. Queue responses also include heavy snapshot/grid detail.

**Recommended change:** Reuse a bounded query controller for queue status/search/page. Request lightweight listing fields and load full snapshot/grid only through the existing detail endpoint.

**Acceptance:** Opening 500 controlled submissions fetches one listing page, searching reaches the server, and opening one case fetches its full detail.

**Source:** [lib/api_service.dart:1480](../lib/api_service.dart), [lib/api_service.dart:1167](../lib/api_service.dart), [lib/web/screens/web_planner_queue_screen.dart:171](../lib/web/screens/web_planner_queue_screen.dart).

### AP-08 ? Map and inbox share mutable queue/filter state without a query generation guard

**Priority:** P1 ? **Basis:** SOURCE_CONFIRMED

Opening Map Analysis requests status=all through loadPlannerQueue, which changes the same plannerQueueStatus and rows used by the inbox. Competing status/search requests are not guarded by a queue generation token.

**Recommended change:** Separate PlanningMapController and ReviewQueueController. Guard responses by owner, filter and request generation; visiting the map must not change inbox filters.

**Acceptance:** Pending -> map -> inbox preserves the selected inbox filter. Delayed older filter responses cannot replace the current view.

**Source:** [lib/web/screens/web_map_screen.dart:135](../lib/web/screens/web_map_screen.dart), [lib/main.dart:1786](../lib/main.dart).

### AP-09 ? Queue failure and search-no-match states remain ambiguous

**Priority:** P1 ? **Basis:** SOURCE_CONFIRMED

The empty branch checks the unfiltered queue rather than the searched result. Initial fetch failures can end at No submissions found after a transient snackbar; count failures are swallowed and zero/stale values have no clear state.

**Recommended change:** Persist resource errors, retain labeled stale data, offer retry, and separate loading/valid empty/no-match/error. Counters need independent loading/error states.

**Acceptance:** Searching a nonempty queue with no matching name shows No matching submissions. An HTTP failure never certifies an empty workload or a zero count.

**Source:** [lib/web/screens/web_planner_queue_screen.dart:206](../lib/web/screens/web_planner_queue_screen.dart), [lib/web/screens/web_planner_queue_screen.dart:171](../lib/web/screens/web_planner_queue_screen.dart), [lib/main.dart:1786](../lib/main.dart).

### AP-10 ? Review detail loading and URL reentry need a coherent route lifecycle

**Priority:** P1 ? **Basis:** SOURCE_AND_CONTROL_FLOW_REVIEW

Detail is awaited before opening the dialog, so a slow fetch has no immediate detail loading view. The linked-record guard retains _openedRecord and skips the same ID on reentry; route Back/Forward, retry and dialog close need explicit regression coverage. These browser scenarios were not reproduced in this review.

**Recommended change:** Use a full-page review route with a loading/error/retry state keyed to the case/revision ID. Preserve inbox filters and scroll on return. Keep a small confirmation dialog only for the final decision.

**Acceptance:** A direct link, refresh, failed-load retry and Back/Forward can reopen the same case reliably; repeated clicks cannot stack stale record dialogs.

**Source:** [lib/web/screens/web_planner_queue_screen.dart:11](../lib/web/screens/web_planner_queue_screen.dart), [lib/web/web_analyst_shell.dart:73](../lib/web/web_analyst_shell.dart).

### AP-11 ? Queue and detail retain rigid desktop layouts

**Priority:** P2 ? **Basis:** LAYOUT_RISK_FROM_SOURCE_NOT_BROWSER_REPRODUCED

Queue cards always use two columns; filter controls and KPI/header rows are ordinary Rows. The review dialog also contains fixed-height two-column sections. This is a source-observed overflow risk, not a newly reproduced device failure.

**Recommended change:** Use adaptive table/cards, wrapping filters, a collapsible map and a full-page detail layout at narrow/zoomed widths. Keep the decision action accessible while scrolling evidence.

**Acceptance:** Test 480x700, 1000x500 and 1280x900 plus 200% browser zoom on inbox and full review, with no unreachable actions.

**Source:** [lib/web/screens/web_planner_queue_screen.dart:219](../lib/web/screens/web_planner_queue_screen.dart).

### AP-12 ? Planning-map summary mixes record scope and fixed overlay readiness

**Priority:** P2 ? **Basis:** SOURCE_CONFIRMED

The map merges loaded owned history and submitted farmer analyses, includes a useful loaded-record badge, but its summary says Total Analyzed Lands/Across all saved analyses and Infrastructure Overlays Ready unconditionally. This is not a complete Panabo land inventory.

**Recommended change:** Label the dataset, filters, record count, distinct farm count and last refresh. Derive overlay availability from actual record/capability state and keep missing coverage visible.

**Acceptance:** An unavailable overlay is not labeled Ready. A displayed count is identified as records or distinct farms, with the exact authorized scope.

**Source:** [lib/web/screens/web_map_screen.dart:366](../lib/web/screens/web_map_screen.dart), [lib/web/screens/web_map_screen.dart:135](../lib/web/screens/web_map_screen.dart).

### AP-13 ? Existing snapshot/version data needs visible review context

**Priority:** P2 ? **Basis:** EXISTING_FOUNDATION_WITH_PRESENTATION_GAP

Sessions already store result snapshots, farm/boundary versions and review timestamps. The inspected review UI does not provide a clear version-comparison header/timeline. The farm boundary_version currently increments even for metadata edits, so a simple version mismatch must not automatically claim geometry changed.

**Recommended change:** Show the analyzed geometry/version/date, current geometry fingerprint where available, and decision timeline. Distinguish a geometry change from a rename or archive action.

**Acceptance:** A historical review remains tied to its original analysis; a farm rename does not falsely label the boundary as changed.

**Source:** [backend/database.py:1398](../backend/database.py), [backend/database.py:1769](../backend/database.py).

### AP-14 ? Inbox ordering and cards emphasize analysis date instead of waiting time

**Priority:** P2 ? **Basis:** SOURCE_CONFIRMED

The queue is ordered by analyzed_at descending and cards display the analysis date. submitted_at exists, but the default queue does not prioritize elapsed review waiting time.

**Recommended change:** Default Pending to oldest submitted first, offer explicit sort, and display submitted date plus waiting age. Add lightweight follow-up tasks or assignments only when operationally needed.

**Acceptance:** An older pending submission can be found first even when its underlying analysis is older than a newly submitted case.

**Source:** [backend/database.py:1345](../backend/database.py).

## Other web readiness observations

Identity and delivery remain a separate completion stream. Existing-account operation, signup/recovery email receipt, Google sign-in, SMS verification and background push must have their own evidence. Missing provider configuration should remain visible rather than being described as a general database outage.

The browser-storage session architecture and its residual script-access risk remain documented in the existing session decision. A future authentication redesign should have its own scope and browser tests; the recommended operator workflow does not require changing it immediately.

The review queue's project-wide planner access is an existing authorized design, not automatically an authorization defect. Add per-barangay assignments/authorization only if the operating policy actually requires them, with server-side enforcement.

## Decision

Proceed with an operator-workflow improvement release while NPK and soil pH remain on hold. First fix misleading evidence displays and API/UI decision consistency, then build a usable review-and-correction loop, then improve planning summaries and data loading. Use the linked acceptance scenarios to decide whether each increment is actually ready.

See [recommended analyst/planner approach](ANALYST_PLANNER_APPROACH.md), [structured findings](findings.json) and [existing web execution evidence](../defense-evidence/web-fix-execution/README.md).
