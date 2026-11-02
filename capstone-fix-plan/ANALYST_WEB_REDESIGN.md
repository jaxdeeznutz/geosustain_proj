# Analyst web redesign

Owner request, 2026-10-30: closely reproduce the supplied Overview, Planning Map,
My Analyses and Recommendation Patterns designs. Backend changes are excluded.
Remaining scientific Phases 8-9 stay paused.

## Implemented presentation

- Full-height forest sidebar, compact account/navigation controls and a header
  beginning to the right of the sidebar. The menu collapses on desktop and uses
  the existing drawer on narrow screens. Existing route indices and role checks
  are retained.
- A landscape masthead, mint canvas, white rounded panels, compact typography
  and consistent spacing across the analyst pages. The existing login is retained.
- Overview: four metrics, four-step introduction, two-column quick actions,
  weather, recent analyses/reports and a recorded-area chart. Submitted review
  workload remains separately identified below the account dashboard.
- Planning Map: filtered-page metrics, existing case/date/location/bounds filters,
  interactive case map, zoom/recenter buttons, layer visibility controls and map
  information. Only available case markers, saved boundaries and the street
  basemap are toggleable. Case-specific terrain, NDVI and soil evidence remain
  in each case's saved evidence.
- My Analyses: current-page metrics, account search, explicit current-page
  date/status/place/type filters, date sorting, list/grid views, pagination,
  monthly counts, status distribution and analysis type counts. Existing saved
  assessment details open from the table/cards. Farmer cases stay in the inbox.
- Recommendation Patterns: existing account summary data, crop frequency bars,
  score distribution, recorded-month trend and insight cards. Zero scores remain
  included. Fewer than two dated months produces an insufficient-data message.

Counts, areas, crop names and charts come from existing responses and saved
records. Sample mockup values and percentage increases are not substituted into
the application. Where aggregates are unavailable, loaded-page scope is stated.
Explainable AI, crop ranking, nutrient values, crop criteria and exports retain
their existing logic.

## Artwork

The existing `assets/images/web/eco_valley_panorama.png` is reused for the masthead.
The new project asset is
`assets/images/web/analyst_sidebar_valley.png` (1024 × 1536, opaque PNG).
It was generated with the built-in imagegen tool and copied into the project;
the generated image contains scenery only. Text, controls and charts are Flutter
widgets and painters.

Final generation prompt:

> Use case: stylized-concept. Asset type: illustrated footer background for
> GeoSustain agricultural analyst web sidebar. Create a polished landscape painting
> in a tall portrait 2:3 canvas. The upper half is an uninterrupted deep forest teal
> (#003d32) that subtly transitions into distant emerald mountains in the lower half.
> Lower third: lush terraced green farms, one tiny cream farmhouse, angular layers
> of hills, tropical banana leaves in the bottom corners. Match the supplied web
> design reference's sidebar illustration: crisp softly shaded shapes, rich emerald
> and jade greens, muted blue green distant hills, subtle warm lime farm accents.
> Composition: all scenic detail concentrated in the bottom 45%, top 55% quiet flat
> dark teal for navigation overlaid in code. No text, no logos, no UI, no frames,
> no people. Opaque PNG background.

## Verification

`deployment/verify-analyst-redesign.ps1` runs offline dependency resolution,
Flutter analysis, all Flutter tests and a web build. It also verifies the 136
tracked backend file checksums captured before frontend edits. It records each
attempt separately under `defense-evidence/analyst-web-redesign/attempts/`.
It neither starts nor modifies the backend.

`test/analyst_visual_redesign_test.dart` adds responsive/full-page/dark-mode checks
at 360, 480, 1440 and 1920 px, read-only navigation checks, history filtering/view
tests, zero-score distribution checks and map layer visibility tests. It writes
preview PNGs under `build/analyst-redesign-previews/`. These use synthetic UI
records and a test font fallback; offline map tiles are test pixels, not imagery.

Agent checks: Dart syntax formatting passed for changed Dart files; targeted
analysis of the layout/dashboard/history/patterns widgets passed. Full Flutter
execution and map/package type checks cannot run inside the agent because the
machine denies access to the Pub cache. The owner terminal verifier is required
before reporting all Flutter checks passed. Browser comparison with the supplied
references remains a separate visual review.

For the existing development session, restart only the Flutter web client after
verification. Leave the working backend running. A new client start is preferable
to browser refresh alone because it rebuilds the asset manifest for the new PNG.

## Card alignment and map imagery follow-up

Owner browser review identified uneven card heights and missing satellite
controls. Desktop KPI rows and paired chart panels now measure their contents
and share the largest height. The dashboard introduction matches the height of
the quick-action/weather stack, recent panels share edges, and the planning map
aligns with its layer/information stack. Narrow layouts remain stacked. Form
labels stay above the planning filters and date guidance fits the fields.

`WebAlignedCards` and `WebStretchCards` support children containing layout
builders, charts and interactive controls without intrinsic-size queries or fixed
card heights. Regression checks compare actual card edges at 1280, 1440 and
1920 px with both populated and empty records, including interactive relayout.

The shared `ContextMap` provides visible Map/Satellite controls on planning,
analysis, saved evidence, raster, boundary and coverage maps. The GPS capture
map already offers both. Small noninteractive thumbnails remain satellite
previews. Switching context imagery retains the camera, saved geometry, raster
cells and sample values; it performs no analysis or backend mutation. New context
maps default to satellite unless low-bandwidth mode is enabled. Existing
analysis-map preferences are retained. The imagery source is the same Esri World
Imagery tile service already used by the app; street context uses OpenStreetMap.

The earlier owner verifier passed before this follow-up. These new changes require
another run of `deployment/verify-analyst-redesign.ps1`; do not treat that earlier
result as validation of the new alignment and basemap code.

## Review Inbox, Activity and Reports layouts

The next owner references specify layout only; the existing forest sidebar,
palette, background and card styling remain in place.

- Review Inbox uses a submitted-cases filter panel, with dates and refresh in a
  second row, followed by a separate results/empty-state panel and bounded paging.
  Existing filters, case links and error/applied-filter messages are retained.
- Activity uses one web card with the event-type selector, unread/read controls,
  refresh, a bordered results area, a centered empty state and pagination. It
  reuses the existing notification loading, authorization and mark-read handlers.
  The mobile notifications layout remains the default outside the analyst page.
- Reports uses heading and workflow links, a search/date/type filter row, an
  illustrated empty state, a generate-report entry point and the existing PDF
  download handler. Date and type filters explicitly apply to the loaded page.
  Review-case and planning exports remain separate actions and are not invented
  as persisted assessment report types.

The responsive preview tests now include these three routes at 360, 480, 1440 and
1920 px. Additional checks cover review filters, activity filtering and explicit
mark-read behavior, report filters/search, and the empty-report workflow link.
All backend source checksums still match the original design baseline. A new
owner-terminal verifier run is needed for this revision.

The 20261030-132257-251 owner run passed analysis and 306 tests, with two
failures. The card renderer now applies a shared minimum height instead of a
tight height so descendant content changes can trigger a fresh measurement.
Its regression test changes state inside a card, checks growth and collapse,
and retains the aligned-edge and button-hit checks. The basemap regression now
sets and restores low-bandwidth preferences explicitly and tests both defaults;
the application's low-bandwidth behavior is unchanged. These fixes require a
new test run before reporting client validation complete.
