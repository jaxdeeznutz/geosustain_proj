# Recommended analyst and planner approach

Date: 2026-10-27. This is a proposed product/workflow design, not a claim these new features are implemented. NPK and soil pH changes and new dataset integration remain on hold.

## Core recommendation

Keep the existing Agricultural Planning Analyst account. Give it two explicit responsibilities: prepare an analysis and review a farmer submission. Use one shared evidence record and two clear workspaces, with a planning overview around them. This fits the existing role/API structure and supports an understandable defense demonstration.

### Proposed navigation

| Main destination | Purpose | Existing functionality to reuse |
| --- | --- | --- |
| Overview | Review workload, recent decisions, follow-ups and resource state | Dashboard, planner counts, activity |
| Analysis Workspace | Select a farm/area, run analysis, explain and save a result | Analyze Area, history, shared result evidence |
| Review Inbox | Receive, search, prioritize and review farmer submissions | Verification Queue and detail API |
| Planning Map | Inspect authorized submitted parcels and patterns with explicit filters | Map Analysis and map/detail components |
| Reports | Analysis reports, decision records and scoped planning summaries | Existing report/export pipeline |
| Activity | Analysis completion, submissions, decisions, information requests and follow-up events | Existing activity and notification path |
| Settings | Account, identity, delivery and display preferences | Existing settings |

Keep My analyses/history available inside the Analysis Workspace. Recommendation Patterns can sit under Overview or the Planning Map with a clear description of the records counted. Existing browser links should redirect to their new destination rather than silently breaking.

## 1. Analysis Workspace

### A. Identify what is being analyzed

Show farm reference, submitter/owner reference where authorized, selection type, mapped area for a polygon, recorded boundary/version and intended planting month. Farm review should start from the submitted parcel geometry. Point screening remains an explicitly named exploratory workflow; a point result should not imply a whole farm was assessed.

Give the map and input controls a clear sequence: choose area -> check selection -> run -> inspect results -> save/export. Show the selected geometry before submitting the job. Reuse existing geometry validation rather than maintaining separate desktop and mobile rules.

### B. Make analysis progress and recovery understandable

Display actual server job stages/request IDs where supported. During a synchronous request, show the real pending state and retry guidance. Background continuation should be offered only when the worker/job configuration actually supports it. Retrying should reuse the request identity where appropriate and avoid creating duplicate sessions.

Retain useful selection and prior results after a network problem, with a visible stale/result timestamp. Verify recovery after browser refresh rather than assuming an in-memory result will survive it.

### C. Organize the result around an understandable summary

Use these sections:

1. Summary: farm/geometry, result type, candidate crops if available, major constraints, missing evidence and practical next action.
2. Recorded conditions: environmental measurements, units, observation period and the applicable assessment rule where one exists. Held NPK/soil-pH logic is unchanged.
3. Map and coverage: recorded boundary, available layers and missing/partial coverage with a numeric legend.
4. Evidence and dates: source, measurement period, model/rule version and warnings.
5. Analysis history: prior versions, run date and the relationship to the current farm geometry.

A model score, factor assessment and source-availability flag should have different names. Show Suitable / Suitable with limitations / Not suitable / Not assessed for a non-soil factor only when its documented rule supports that label. A missing assessment is not a zero or an unsuitable grade. Do not average model scores and rule grades into a new overall percentage without an explicit validated definition.

### D. Use a consistent analysis record

The stored snapshot should identify farm and geometry, analysis ID, source periods, model/rule versions, quality flags, optional ranking output and run timestamp. The same values should appear in workspace, history, review and exported analysis report. Existing snapshot fields are a useful starting point.

When an operator writes advisory notes or chooses an alternative recommendation, record it as a human note/decision with a reason and author. Preserve the original computed result for traceability.

## 2. Review Inbox and workbench

### A. Make the inbox an operational list

Default to pending cases ordered by oldest submitted time. Offer search, status, place/validated barangay, submitted-date range, result completeness and explicit sort. Use a desktop table with a compact-card layout at narrow widths.

Suggested columns: case/submission ID, farm, submitter, location, submitted time, waiting age, result type/evidence completeness, review status and Open review. A model score can be optional detail; it should not drive the review decision automatically.

Use a lightweight server-paged response. Request the complete grid, explanations and source snapshot only when opening the detail. Keep all-record statistics in a separate aggregate endpoint.

### B. Open a full-page review

Use a URL-addressable workbench, for example a hash route identifying a case and analysis revision. Preserve the inbox's filters, page and scroll when returning.

Suggested layout:

- Header: case/farm reference, submitter, submission date, current review status and analysis revision.
- Main evidence area: summary, parcel map, observed conditions, coverage/limitations and analysis history.
- Review panel: checklist, notes, reason/correction items and the decision controls.
- Timeline: submission, information request, farmer response, new analysis revision and final decision.

A long evidence review should have its own loading/error/retry state immediately after navigation. Use a small confirmation dialog for the final action. At narrow widths the review panel moves below the evidence and the map can collapse.

### C. Add one useful decision path: Request information

Proposed flow:

    Farmer submits -> Review Inbox -> Evidence workbench
                                      |-> Review accepted
                                      |-> Request information -> Farmer responds/corrects
                                      |                         -> New linked revision -> Inbox
                                      |-> Rejected with reason

The minimum extension is an information-request state plus revision-linked resubmission and events. Persist an In review/assigned state later if several reviewers actually need case assignment.

| Action | Intended meaning | Required record |
| --- | --- | --- |
| Review accepted | Reviewer completed the defined review of the available submission | Analyst, timestamp, scope/checklist, analysis revision and relevant notes |
| Request information | A specific correctable gap prevents completion | Correction items, explanation and a response path |
| Rejected | Submission cannot proceed under the defined project review policy | Structured reason and mandatory explanatory note |

Show Reviewed ? preliminary when the reviewed analysis remains preliminary. Human review completion does not change a partial analysis into a complete scientific assessment. Avoid implying that an email/account check proves land ownership or that a reviewed result is a permit or laboratory certification.

A missing provider response is usually a technical retry/information issue; it should not automatically reject the farmer's land.

### D. Make the checklist honest

A small checklist can cover: submitted farm/reference identified, boundary readable and selection type clear, analysis snapshot/current geometry relationship checked, coverage and periods reviewed, available constraints explained, and follow-up actions recorded.

Record field visits, uploaded observations or additional confirmations only when they actually happened. A checked box should mean evidence was reviewed, not that an unperformed field investigation was completed.

### E. Enforce decisions on the server

Keep the existing pending-only update protection and transactional audit/notification path. Add matching note/reason validation, bounded note length, an explicit review revision token and a conflict response showing that the case changed.

For resubmission, keep old snapshots and decisions and link the next analysis/revision to the same case. Do not reset the old decision or replace its geometry. Keep notification events idempotent so retries do not generate duplicate action items.

Separate geometry changes from metadata changes. The current boundary_version increments for general parcel edits; compare an actual geometry fingerprint or a dedicated geometry version before saying a boundary changed.

## 3. Planning overview and map

### Operational dashboard

Lead with actionable review metrics: pending cases, oldest waiting submission, information requests awaiting response, reviewed this period and partial/unavailable-evidence cases. Clicking a metric should open the matching inbox filter.

Keep My analyses and their model statistics in a clearly named personal section. Label all counts with scope and time period. Resource failure should show unavailable/stale, not zero.

### Planning map

Give the map its own query/controller so it cannot change the inbox's filter. Filter by authorized dataset, review status, date, place and relevant result type. Show record count and distinct farm count separately.

Choose one map meaning at a time: review status, crop candidate, measured layer, model score or evidence availability. Each has a matching legend. Missing cells/coverage remain visible. A relative high value in a measured layer should not automatically be painted as a favorable assessment.

For larger controlled datasets, request records within the viewport with bounded fields, then add clustering if measurement shows it is needed. Avoid downloading complete analysis snapshots for every map marker.

A map of available/submitted records is not a complete city land inventory. Label it as Submitted farms/Recorded analyses in Panabo with the selected scope. Use validated location fields for barangay filters rather than treating a display geocoder string as an authoritative boundary.

### Aggregates and recommendation patterns

For planning summaries, use a documented latest-eligible-analysis rule per distinct farm. Keep case count, analysis-run count and farm count separate. Sum of parcel areas can include overlapping parcels; label that sum or compute an explicitly defined nonoverlapping geometry union when that is the required metric.

Crop recommendation frequency describes this system's recorded outputs. It does not establish actual planted area, yield, market demand or citywide crop suitability. Include date range, record count, preliminary/missing counts and review-status filters with every chart.

### Follow-ups and reports

Add lightweight follow-up items for boundary clarification, an actual planned field visit or another reviewer-requested action, with owner, due date and status. Keep completion events traceable.

Maintain separate outputs: analysis report tied to a snapshot, review-decision record tied to a reviewer/revision, and planning summary tied to a filter/date/aggregation definition. Reuse the current report pipeline and add missing context rather than generating unrelated figures.

## 4. Notifications that support this workflow

Use the existing activity/outbox path for submission received, information requested, farmer response/resubmission, analysis ready/partial/failed, review completed and follow-up due. Each notification should link to the exact authorized case/revision and explain the next action.

Weather advisories can remain a separate category. In-app presence and external push/email/SMS delivery are separate evidence; required external delivery still needs owned provider configuration and receipt tests.

## 5. Practical implementation order

| Increment | Deliverable | Acceptance evidence |
| --- | --- | --- |
| 1. Correct decision/evidence meaning | Consistent score wording, layer legends, conditional availability, server note rules and clear conflict behavior | One record agrees across inbox/detail/map/report; direct blank-reason rejection is refused; uniform heatmap data is explained correctly |
| 2. Complete the review loop | Full-page review, information request, response/new revision and visible decision timeline | Farmer submits -> reviewer requests correction -> farmer resubmits -> reviewer accepts; old snapshot and decision remain visible |
| 3. Make operator work reliable | Bounded inbox search/pages, independent map state, queue error/no-match/stale states, workload dashboard and waiting-age sort | One page fetched initially; delayed responses cannot change the active filter; no network error becomes a confirmed zero |
| 4. Verify planning and presentation | Scoped map/aggregates/reports, accessible layouts and the real role/browser journey | Repeated analysis of one farm does not become multiple farms; direct links/Back/refresh work; narrow/zoomed controls remain usable |

Introduce separate feature controllers incrementally around the existing APIs: AnalysisWorkspace, ReviewInbox, PlanningMap and Reports. The immediate benefit is independent query/loading/error state and fewer cross-screen side effects. Reuse the current combined role, permissions, snapshots and event infrastructure.

## Acceptance scenarios for the next operator release

1. Operator with no personal analyses still sees the real pending farmer workload.
2. Blank rejection notes fail through the API as well as the UI.
3. Two reviewers opening one pending case cannot overwrite the first completed decision.
4. Information request and resubmission preserve the prior revision and decision.
5. Switching inbox status while an older request is delayed keeps the latest chosen filter.
6. Visiting the planning map does not mutate inbox filters or pagination.
7. Empty, no-match, initial failure and stale refresh failure have distinct displays.
8. Direct links, same-case retry, browser refresh and Back/Forward reopen the correct review.
9. Geometry changes and farm renames are distinguished in review history.
10. Uniform/missing environmental grids and preliminary results retain accurate meanings.
11. Large controlled queue data triggers bounded requests and a single detail fetch per opened case.
12. Inbox, review decisions and reports remain usable at narrow widths, 200% zoom and with keyboard navigation.

These scenarios are proposed acceptance work. They have not been converted into new QA passes by this document. Held NPK/soil-pH acceptance remains separate.
