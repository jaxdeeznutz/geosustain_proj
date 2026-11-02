# Farmer readability and legends — 2 November 2026

The owner reports that the Farmer → Analyst → Superadmin connection works.
That is an owner-reported journey pass; no new production/device artifact was
captured in this editing session. Firebase configuration remains separate.
Scientific Phases 8–9 remain paused.

## Farmer experience

- Results open with a short farm summary, up to three saved crop choices and the
  review action. Model scores remain labelled as scores, never harvest chances.
- Preliminary and blocked results do not promote old crop names or scores.
- Extra crop choices, the farm map and full analysis are available on tap.
  Detailed explanations, citations, measurements and limitations remain available.
- The short review card uses the same submission handler and eligibility rules.
  The expanded full analysis suppresses duplicate submission/export controls.
  Analyst feedback stays visible. PDF export still uses the existing full report.
- Crop detail sheets show short condition rows with labelled symbols. General
  application checks are distinguished from crop-specific requirements. Raw NPK
  inputs are left in the full explanation with their existing source/unit context.
- Review, condition and map legends use text plus distinct symbols alongside
  color. Review green means reviewed; condition green means a compatible saved
  range check. Neither establishes successful planting. Missing assessments mean
  no usable check, not poor land.
- Map legends retain the saved numeric ranges, units and actual colors. Gray
  means no usable reading. Heatmap levels do not become crop suitability grades.
  The interactive map has a Map guide button for pins, corners and active layer
  colors. Old layer colors are omitted when the current boundary no longer
  matches the saved analysis.

## Data and behavior boundaries

Backend files, API transport, stored results, crop ordering/scores, model,
reference criteria, seasonality, explanation arithmetic and PDF generators are
unchanged. The full analyst evidence interface keeps its existing presentation.
This change introduces native Flutter UI and no generated bitmap assets.

## Validation

The 136-file backend hash guard and source formatting pass. Limited standalone
Dart analysis is blocked by protected Pub-cache dependencies (notably Flutter Map
and LatLng); it is not a successful Flutter analysis run. Full client tests/build
and real-device visual acceptance are pending in the owner's terminal.

```powershell
.\deployment\verify-farmer-readability.ps1
```

The verifier records actual logs/exit codes under
`defense-evidence/farmer-readability/attempts/`, checks backend integrity before
and after analysis/tests/web build, and does not start or restart the backend.

`test/farmer_readability_test.dart` adds 13 checks covering phone widths and 2×
text, reduced default reading, access to full details, zero model scores,
preliminary/blocked suppression, the guarded submission, map legends/boundary
switches, dark mode and the unchanged analyst interface. The existing mobile
design journey now opens full details before testing the detailed interface.
No passing test/build result is claimed until the verifier completes.

Owner run `20261102-152223-510` passed backend integrity, offline Pub and Flutter
analysis. The suite finished with 353 passes and one failure: the existing
doubled-text model-explanation test looked for the old submission label. The
test now finds the `Send for review` button and verifies that it is enabled,
hit-testable and fully above the navigation bar. No runtime code or backend
change was needed for this correction. The corrected test and web build remain
pending until rerun.

After checks pass, hot-restart the farmer app. Review the summary, a crop sheet,
the farm map and its guide with an actual farmer; confirm that the labels and
symbols make sense without reading the full explanation.
