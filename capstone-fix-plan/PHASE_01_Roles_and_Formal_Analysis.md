# Phase 1 - Roles and formal analysis workflow

Dependency: Phase 0. Nutrient datasets are not needed.

## Problem and intended behavior

Align the application with the signed scope: farmers analyze saved farm polygons and submit results; analysts review farmer submissions; Super Administrators manage authorized records. Retained point analysis is preliminary inspection. Preserve current authentication and the visual design.

## Implementation tasks

- Keep the Verification Queue, submitted case map, review evidence, notes and Verified/Rejected decisions central to the analyst workspace. Gate independent analyst analysis from the capstone workflow unless an approved extension is recorded; preserve its existing records.
- Enforce formal submission eligibility server-side, including farmer ownership, saved non-archived farm association, valid analyzed polygon and boundary-version consistency. Client button restrictions are supplementary.
- A boundary change must require a new formal analysis rather than silently replacing submitted evidence. Reject unauthorized farm IDs, stale versions, changed client geometry and cross-user requests.
- Mark point and other unsupported-for-formal-use inspections explicitly. Do not permit submission as a formal farm result or label the result as verified land. Historical incomplete records remain viewable with limitations.
- Preserve draft/pending/verified/rejected behavior and idempotency. Define treatment of historical pending cases without silently deleting or rewriting them. Keep the existing prohibition on self-review.

## Likely files

`backend/fastapi_app.py`, `backend/database.py`, analysis/scope tests, analyst web routes and screens, farmer analysis/submission controls, `docs/ANALYST_WORKFLOW.md`.

## Acceptance

- An owned saved-polygon analysis can be drafted and submitted once; retries do not duplicate or erase decisions.
- A farmer sees the authorized analyst's notes and status. Another farmer cannot read or submit the record.
- Point-only, unowned, archived or stale-boundary formal submissions are rejected with useful messages.
- Analyst and Super Administrator permissions remain distinct; unauthorized direct API actions fail.
- Saved historical results reopen without invented farm, scope or boundary metadata.

Record API negatives, focused client checks and a controlled farmer-to-analyst journey. Complete when both server enforcement and user-facing scope agree. This phase does not require retraining, NPK matching or UI replacement.
