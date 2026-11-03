# Review Inbox case layout and fixed evidence maps

Owner references: existing deployed case screenshot and the two supplied
Review Inbox design mockups. This change preserves the accepted analyst shell
and reuses its existing landscape/brand artwork. Cards, tabs, status strips and
timeline are native Flutter controls; no new raster image is needed.

## Implemented layout

- Case heading/status and responsive metadata strip using the current case.
- Boundary & Measurements, Farm Details, Seasonal Context and Attachments tabs.
- Desktop evidence map with location, saved season and farm identity side cards;
  narrow screens stack those cards. Full coverage/provenance remains available
  in Farm Details. Changed current geometry is warned about before the map.
- Existing result Overview/comparison/recommendation/factor/Map tabs remain
  available without a duplicate identity header in the review layout.
- Analyst Review status/feedback, actual analysis and case report exports,
  two-column checklist/notes, recorded revision/event timeline and follow-ups.
- Existing same-owner denial, four-check verification requirement, confirmation,
  stale-version errors, reason/note validation, follow-up ownership and endpoints
  remain unchanged. Case and analysis versions/statuses remain distinct.

Attachments are not included in the existing case response. The tab states
that attachment records are unavailable; it does not invent a count, files or
an upload/download endpoint. Missing/legacy evidence remains labelled.

## Fixed review camera

Both sampled-point and saved-raster maps fit the recorded polygon and disable
gesture pan, zoom and rotation. Map/Satellite switching changes only the
navigation background. Coordinate/layer changes rebuild the matching saved
camera. The result's Map tab, no-raster boundary preview and historical revision
maps also receive the review lock. Normal farmer/workspace/planning maps keep
their existing interactions. Missing polygons do not create fictional geometry.

The imagery, saved samples, original source palettes/ranges/no-data values and
scientific limitations are preserved. No backend, ranking, nutrient or model
change is made.

## Verification

```powershell
.\deployment\verify-review-case-redesign.ps1
```

The verifier checks every tracked backend file against the pre-edit hash
manifest, then runs offline pub resolution, full Flutter analysis/tests and a
Web build with the saved public Firebase config. Tests cover desktop/narrow
and enlarged-text layout, self-review denial, read-only tab changes and both
legacy/raster camera locks; existing operator workflow tests cover mutation
confirmation and stale-case notes. Synthetic preview PNGs are written to
`build/review-case-previews` by the new widget tests.

Agent-side Dart parsing/formatting and backend integrity checks are available.
The protected Pub cache prevents a full agent-side Flutter check; partial
standalone analyzer output is not a Flutter pass. Owner verifier, generated PNG
inspection and live browser acceptance remain pending until actually run.
No commit, deployment or backend restart is performed for this UI update.

### Owner run: 20261102-233205-223

The owner run passed pub resolution and Flutter analysis, then reported 373
passing tests and four failures. All four failures were the same global text
finder at the four viewport sizes: both the sidebar and the detailed coverage
card legitimately contain `Analyzed Farm Location`. The layout test now scopes
that heading and the saved latitude/longitude assertions to the existing
`review-location-card` key. It retains exact single-match checks and all layout,
export, follow-up and camera assertions. The corrected run and preview inspection
are still pending; this correction is not a claimed Flutter test pass.

After the separately authorized provider recovery changes, use the combined
verifier, which also runs the review tests and preserves the original backend
baseline with an explicit provider change allowlist:

```powershell
.\deployment\verify-provider-recovery.ps1
```
