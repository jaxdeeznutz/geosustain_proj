# Analyst web workflow

The analyst portal follows the accepted capstone review workflow: review farmer-submitted assessments through the Review Inbox and submitted-case map.

## Review a submission

Open a submitted case, inspect its saved farm boundary, observations, dates, sources, coverage and limitations, complete the checklist, add notes and record Verified, Rejected or Request information. Farmers can see the status and notes. A corrected revision must be a new eligible analysis of the same current saved farm; earlier revisions and decisions remain in history. Analysts cannot decide their own prior submissions.

Verification records review of saved evidence. It does not guarantee crop success, verify field conditions or fill missing observations.

## Navigation and historical records

The sidebar exposes Overview, Planning Map, Analysis Workspace, My Analyses, Reports, Recommendation Patterns, Review Inbox, Settings and Activity. Planning Map shows submitted project cases; Analysis Workspace runs independent analyst assessments. My Analyses and account summary charts describe the signed-in analyst's own records. Review Inbox retains farmer-submitted evidence and review decisions.

The owner requested restoration of the independent tools during Phase 7. Their protected `/api/web/analysis` route accepts analyst role aliases and saves only to the authenticated analyst. It cannot attach farmer parcel IDs or boundary versions. The farmer analysis endpoint and formal farmer-submission requirements retain their original role restrictions. See [restoration evidence](../defense-evidence/capstone-fix-execution/phase-07/WEB_DESIGN_RESTORATION.md) for the design changes, source image, regression checks and pending browser acceptance.

Historical submissions without a saved-farm link retain their original evidence and decisions with a limitation notice. No current farm or environmental metadata is invented. When a linked correction is impossible, submit a new formal saved-farm analysis instead of altering the historical case.

## Formal farmer submission

See [Formal analysis workflow](FORMAL_ANALYSIS_WORKFLOW.md). The server validates owned active farm association, analyzed polygon and boundary version for initial and linked corrected submissions. New point/unsaved-polygon inspections are labelled preliminary and remain outside formal review. Duplicate requests preserve decisions and do not add duplicate events.

The Phase 7 restoration updates the web presentation and independent assessment entry point. Authentication/verification, NPK estimates, crop-ranking formulas and saved review evidence remain unchanged. No database migration is required.

## Checks

Run `./deployment/verify-phase-07.ps1` for Flutter analysis, complete widget/unit tests and a web build of this candidate. Backend regression and isolated SQL/API evidence are recorded separately. Phase completion requires its remaining client and manual checks; a local source or SQL pass is not deployed/device acceptance.
