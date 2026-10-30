# Formal farmer analysis and preliminary inspection

Formal review uses an analysis of an owned, active, saved farm polygon. The API
uses the server's farm geometry and records its boundary version. Updated clients
send the expected version; stale versions or a different accompanying polygon
are rejected before inference. Older clients cannot replace the server geometry.

A point or unsaved polygon can still produce useful estimated observations and
model outputs. New results save `analysis_scope`, `formal_submission_eligible`
and `analysis_scope_notice`. These inspections are labelled preliminary and
cannot be submitted as formal farm results. They remain available in history;
their model probabilities and estimated NPK values are not changed by this rule.

At initial submission, the server locks the owned draft, checks the farmer role,
locks the farm against concurrent edits and validates ownership, active status,
the analyzed boundary/version and any saved snapshot geometry. Only then does it
create the Pending submission and review activity. A boundary edit requires a
new analysis of the current saved farm. The linked-correction path enforces the
same checks and excludes stale/archived candidates from its choices.

Retries of already submitted/decided records preserve their existing status,
notes and events. Initial and corrected submission races cannot overwrite a
decision or associate one revision with two cases. Existing submitted snapshots
are not upgraded to today's metadata, deleted, or silently regraded.

Historical cases without a farm link remain readable. Their original decisions
and notes are retained. If a correction cannot be associated with a saved farm,
the farmer must create/open a saved farm, analyze it and submit a new formal case;
the interface does not offer an impossible linked correction.

The analyst portal reviews farmer submissions using the Review Inbox and case
map. Independent analysis controls are removed from the assessed analyst flow;
old analysis URLs show a review-only notice, and the analysis API rejects new
inference by analyst/admin roles. Their existing account-owned records and
reports remain readable. Analysts still cannot review their own prior submissions.

This change does not re-enable CAGRO, change NPK formulas/grades, retrain the crop
model, add seasonal weighting, or modify email/password/Google verification.
It changes analysis/submission authorization and preserves existing login flows.

## Verification

Backend regressions: `python -m pytest backend/tests -q -p no:cacheprovider`.
Controlled SQL/API acceptance uses `backend/tests/phase01_submission_integration.py`
on the already verified disposable PostgreSQL instance, never a production target.
Its inference/provider work is a fixture; it is not field/scientific validation.

Run `./deployment/verify-phase-01.ps1` from a shell with normal Flutter SDK access
for analyzer, complete Flutter tests and web compilation. The script records
actual results under `defense-evidence/capstone-fix-execution/phase-01/` and stops
on a failure. Source/SQL passes do not replace these client checks or later
installed-device and deployed-role acceptance.
