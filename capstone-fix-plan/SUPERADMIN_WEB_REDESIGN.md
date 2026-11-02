# Superadmin web redesign

Implemented from the five supplied references: Dashboard, User Management,
Farm & Analysis Monitoring, Crop & Season Settings, and Audit & System.
The existing analyst pages and mobile navigation retain their layouts.

## Presentation and behavior

- Forest sidebar with the accepted scenic illustration, white compact header,
  authenticated administrator identity, existing live weather, mint canvas and
  a new generated landscape banner. Native Flutter widgets render the controls,
  data tables, metrics and charts.
- Dashboard: two rows of four aligned metrics, recent administrative activity,
  system inventory and working navigation shortcuts. Activity and inventory panels
  share their top and bottom edges on wide screens.
- Users: system totals, server search, explicit loaded-page role/status/provider
  filters, account table, existing role/status changes and identity-verified
  recovery handoff. Recovery cancellation sends no request.
- Monitoring: system totals, server search, loaded-page filters, recorded analysis
  table, read-only record details, review-status donut and recorded crop frequency.
  Preliminary records suppress stale crop names. Review status never becomes an
  agronomic suitability grade.
- Crops: actual approved/active/inactive counts, existing controlled-record
  workflow beside a four-step guide, searchable and sortable list/grid, crop
  artwork, note editing and activation switches. New revisions still require
  separate review and activation. Saved analyses retain their versions.
- Audit: activity totals derived from the loaded page, action filtering, detailed
  change table, real log views, existing push-delivery log and access-management
  shortcut. Exports contain only displayed rows and selected public audit fields;
  private recovery tokens and credentials are never exported or rendered.
- User, monitoring and audit tables provide a client-generated PDF export of the
  displayed rows, with local Noto fonts and a page/search scope statement.
- Narrow screens use a drawer and stacked cards. Wide metric rows stretch to the
  same height; long tables scroll horizontally. Theme and text size remain native.

## Data boundaries

Backend routes, database, roles, authentication, authorization, model files, NPK
logic and analysis scoring are unchanged. The redesign uses existing admin APIs.
No invented backup dates, storage totals, growth percentages, sparklines or health
scores were copied from the mockups. Unsupported infrastructure metrics are
identified as not reported, with the existing Render/Supabase monitoring guidance.
The navigation contains the five supported admin workspaces. There is no new
account-creation endpoint or operational health/settings API behind mock controls.
The existing account role/status workflow remains the account-management path.

Search uses the existing server `q` query and pagination. Other filters clearly
describe their loaded-page scope, up to 50 records. Dashboard totals retain their
system-wide scope even when a table is filtered. Independent panel failures
retain successful data, name the failed panel and allow retry. Older overlapping
refresh responses cannot replace newer results.

## Artwork

Built-in imagegen tool, generation mode, opaque PNG:

`assets/images/web/admin_valley_banner.png`

Exact final prompt:

> Create a wide panoramic website masthead background illustration, landscape aspect ratio about 3:1. No text, no letters, no logo, no interface. Match a polished agricultural dashboard: lush emerald and lime terraced Philippine farm fields, layers of blue-green mountains and soft white clouds, warm morning sunshine toward the upper right, a tiny cream farm cottage with a red roof on the far right hillside, a few large banana leaves framing the far right edge. Painterly vector-like digital illustration, crisp elegant layered shapes with soft atmospheric gradients and fine natural field detail, inviting and professional. Composition: left third very quiet pale misty mint and cream sky so a dark title can overlay it, rich landscape across right two thirds, gentle pale mint mist near bottom edge to blend into a light page. Do not depict charts or people. High resolution PNG, opaque background.

The sidebar reuses `assets/images/web/analyst_sidebar_valley.png`. Crop icons
reuse the project's native `CropArtwork`; they do not introduce new crop facts.

## Verification

Owner verification completed at `2026-10-30T15:02:52Z`: backend integrity,
offline Pub, Flutter analysis, the complete test suite and the web build all
passed. Recorded results:
`defense-evidence/superadmin-web-redesign/attempts/20261030-145921-583/validation.json`.
Review of the generated PNGs confirmed matching card edges, but exposed Ahem
test-font blocks and default purple test controls. The preview harness now loads
readable fallback fonts and Material icons and uses the green application seed;
these test-only changes do not alter the running app. That preview correction
has not yet been rerun. To regenerate readable previews, run:

```powershell
flutter test --no-pub test/superadmin_visual_redesign_test.dart
```

The following describes the earlier agent-side checks and environment limits:

Backend integrity: the original baseline of 136 tracked backend files still
matches. Dart source formatting and `git diff --check` pass. The local agent's
standalone analyzer cannot resolve packages in the protected Pub cache (including
printing/shared_preferences/flutter_test); full Flutter verification is pending
in the owner's terminal. This document does not claim test or build success.

Run from the project root:

```powershell
.\deployment\verify-superadmin-redesign.ps1
```

The verifier checks backend hashes before and after offline Pub resolution,
analysis, the entire Flutter test suite and the web build. It records real exit
codes and logs in `defense-evidence/superadmin-web-redesign/attempts/`.
`test/superadmin_visual_redesign_test.dart` adds 32 tests covering all five pages
at 360, 480, 1440 and 1920 pixels; dark mode/enlarged text; card alignment;
search/filter scope; mutation contracts; guarded recovery cancellation;
preliminary claims; crop activation; audit details and drawer navigation.
Existing admin failure-isolation and controlled-record tests remain in the suite.
Five preview PNGs are generated by the tests in
`build/superadmin-redesign-previews/`; inspect them after the tests pass.

Restart only the Flutter web client after verification to include the new asset:

```powershell
flutter run -d chrome --no-pub --web-hostname=localhost --web-port=18002 --dart-define=API_BASE_URL=http://127.0.0.1:18001 --dart-define=WEB_BUILD_ID=superadmin-redesign-20261030
```

Leave the already running backend in place. Browser visual acceptance and live
admin actions remain a separate manual check. Scientific Phases 8–9 remain paused.
