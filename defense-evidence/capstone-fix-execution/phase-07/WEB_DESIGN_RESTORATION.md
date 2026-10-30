# Owner-requested analyst design restoration - 2026-10-30

The owner supplied six visual references and the original landscape at
`C:/Users/jasph/Downloads/bg/Eco Valley Panorama.png`. The unmodified original was
copied to `assets/images/web/eco_valley_panorama.png` and registered in pubspec.
No generated replacement or browser screenshot is used as the background.

## Cause of missing pages

`isPlanner` covers all three analyst role aliases. The previous sidebar omitted
Analysis Workspace and Recommendation Patterns for that role, renamed My Analyses
to Assessment Records, and redirected independent analysis to Review Inbox. The
underlying analysis, history, reports and trends widgets still existed.

The owner explicitly requested those tools and their design back. All original
route indices and URLs remain valid. The sidebar now exposes Overview, Planning
Map, Analysis Workspace, My Analyses, Reports, Recommendation Patterns, Review
Inbox, Settings and Activity. Reports and Patterns no longer both appear selected.

## Implementation

- Full landscape login, responsive left introduction and feature tiles, floating
  rounded sign-in card, normal credentials/recovery, password visibility, existing
  Google availability and administrator-assigned analyst access rules.
- Forest-green sidebar with landscape footer; light scenic workspace background;
  account/activity/theme controls and an owned-analysis search in the header.
  Search applies the existing history API's real query.
- Existing real dashboard, submitted-case Planning Map, owned analyses, reports and
  recommendation-pattern charts remain wired to their original data. Example
  counts, trends, fake map layers and sample weather from the visual references
  were not inserted into application results.
- Start New Analysis opens the independent analyst workspace. Farmer submission
  review retains its own Inbox and workbench, separate from owned assessments.
- A protected `/api/web/analysis` endpoint restores independent analyst analysis.
  Existing request locking, quota, persistence, saved evidence, status tracking and
  background-job pipeline are reused. Analyst requests cannot attach `farm_id` or
  `boundary_version`. Saving/read-back use the authenticated actor. The farmer
  analysis route remains farmer-only. Formal submission rules, cross-owner
  isolation and self-review prohibitions remain in force.
- Independent client retries use a separate pending-request namespace. Crop model,
  inputs, ranking rules, nutrient data and local attribution calculations are
  unchanged by this restoration.

## Validation and pending acceptance

`analyst-restoration-backend.log`: 45 focused checks passed, including 14 new
independent-role, foreign-parcel, worker, queue and saved-owner checks plus existing
formal-submission regressions. `backend-tests.log`: all 489 backend tests passed.

Changed Dart files are syntax formatted. Agent analysis cannot resolve restricted
Pub cache HTTP, map, shared-preferences and test packages; retain the actual logs as
limited-environment attempts. The owner must run `deployment/verify-phase-07.ps1`
for the package-aware analyzer, tests and web build. Updated tests cover restored
navigation, existing own-submission decision restrictions, responsive login
callbacks, route selection and interrupted analyst retry identity. Login widget
renders are written to `build/phase-07/web-design-qa` for visual inspection.

After checks pass, restart the local backend and rebuild/restart the web client so
the new endpoint, asset manifest and navigation load together. The Phase 6 manual
host owns a disposable schema and removes it on Ctrl+C; preserve any needed local
screenshots/exports before restarting it. Phase 6 closure evidence is unchanged.
No deployment or scientific validation is implied.
