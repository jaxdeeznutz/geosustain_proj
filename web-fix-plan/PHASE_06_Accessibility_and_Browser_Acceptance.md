# Phase 06: Validate keyboard, accessibility and browser behavior

[Plan index](README.md) · [Execution rules](EXECUTION_RULES.md) · [Issue crosswalk](ISSUE_CROSSWALK.md)

**Status:** PARTIAL — see current execution below.

**Goal:** Turn source reflow/focus risks into actual tested browser behavior on the corrected candidate.

**Primary skill:** [geosustain-web-accessibility](skills/geosustain-web-accessibility/SKILL.md). Read this skill before executing the phase.

**Dependencies:** [Phase 02](PHASE_02_Analysis_Grades_Charts_and_Statistics.md); [Phase 03](PHASE_03_Responsive_Shell_Theme_and_Navigation.md); [Phase 04](PHASE_04_Data_States_Refresh_and_Pagination.md); [Phase 05](PHASE_05_Account_Actions_and_Web_Session_Security.md)

Dependencies establish baseline/final acceptance order. Provider setup in Phase 01 does not block independent source fixes in Phases 02–05; its live gates remain open until completed.

**Issues owned:** WEB-18: A full accessible desktop journey is still unproven

## Relevant implementation

- [lib/web/widgets/web_common.dart](../lib/web/widgets/web_common.dart)
- [lib/web/screens/web_analyze_screen.dart](../lib/web/screens/web_analyze_screen.dart)
- [lib/web/web_analyst_shell.dart](../lib/web/web_analyst_shell.dart)
- [lib/web/web_admin_shell.dart](../lib/web/web_admin_shell.dart)
- [lib/web/auth/web_auth_login.dart](../lib/web/auth/web_auth_login.dart)
- [web/index.html](../web/index.html)

## External inputs and limitations

A controllable actual browser or the user's manual participation is required. If no browser surface is exposed, keep dependent cases pending and give concise user steps; do not call widget tests browser passes.

## Work and acceptance

### W06-01: Define the supported browser and viewport matrix

Record browser/OS versions, viewport dimensions, actual browser zoom and relevant assistive technology. Cover the user's desktop browser and agreed Chrome/Edge/Firefox plus any required Safari target. Preserve previously required but deferred platforms as deferred rather than inventing passes.

**Acceptance:** The matrix lists actual targets and explicitly pending/unavailable targets, with no assumption that simulated width proves a real engine/device pass.

**Evidence:** BROWSER_MATRIX.csv with candidate identities.

**Initial status:** NOT_STARTED.

### W06-02: Complete keyboard and dialog navigation

Run Tab/Shift+Tab/Enter/Space/Escape through auth, navigation, selection, analysis, review, settings and report actions. Give map controls meaningful names/tooltips, visible focus and usable non-pointer alternatives; ensure dialogs announce errors/status and return focus after close.

**Acceptance:** Required journeys complete without pointer-only traps or unnamed essential controls. Focus remains visible and lands sensibly after navigation and dialogs.

**Evidence:** keyboard case steps, semantic observations and human outcomes.

**Initial status:** NOT_STARTED.

### W06-03: Check zoom, contrast, text reflow and status meaning

Use actual 200/400% browser zoom and narrow/short windows on agreed targets. Measure text/surface pairs for applicable 4.5:1 normal-text and other agreed contrast criteria, including theme/focus/errors/disabled states. Keep maps' two-dimensional nature distinct from clipped ordinary controls and test non-color grade labels.

**Acceptance:** No authorized access loss or clipped primary action; text and statuses remain understandable in both themes and the agreed reflow cases.

**Evidence:** contrast measurements, viewport/zoom screenshots and issue retests.

**Initial status:** NOT_STARTED.

### W06-04: Verify maps, downloads, history and permission recovery

Test point/polygon editing, incomplete/invalid boundaries, map tile failure, geolocation grant/deny, browser Back/Forward, direct URLs, PDF download/print, popup restrictions and cache upgrades. Test the chosen theme and restored session in private/restricted storage modes where supported.

**Acceptance:** Each required browser operation works or explains a real permission/storage limitation with recovery; failures are recorded on the exact target rather than generalized away.

**Evidence:** browser feature matrix and redacted screenshots.

**Initial status:** NOT_STARTED.

## Focused verification

- **WEB-18:** The supported browsers complete login, map selection, analysis, review and PDF without an invisible focus/trap or clipped action at the agreed zoom levels; record browser versions and human outcomes.
- Use the installed computer-use skill only when an actual supported browser surface is available; otherwise record manual user steps/outcomes explicitly.

## Exit and handover

Store actual execution under `defense-evidence/web-fix-execution/phase-06/`; start from [EVIDENCE_TEMPLATE.json](EVIDENCE_TEMPLATE.json). Link source/frontend/backend identity, expected versus actual results, test/provider/browser scope and remaining gates.

The phase is complete only when its full acceptance is supported. Source-only fixes can be handed on with pending live dependencies recorded; do not mark the whole phase complete from a build or plan file.

| Task | Current state | Evidence | Remaining gate |
| --- | --- | --- | --- |
| W06-01 | REQUIRES_MANUAL | Current execution below | The matrix lists actual targets and explicitly pending/unavailable targets, with no assumption that simulated width proves a real engine/device pass. |
| W06-02 | CODE_COMPLETE | Current execution below | Required journeys complete without pointer-only traps or unnamed essential controls. Focus remains visible and lands sensibly after navigation and dialogs. |
| W06-03 | REQUIRES_MANUAL | Current execution below | No authorized access loss or clipped primary action; text and statuses remain understandable in both themes and the agreed reflow cases. |
| W06-04 | REQUIRES_MANUAL | Current execution below | Each required browser operation works or explains a real permission/storage limitation with recovery; failures are recorded on the exact target rather than generalized away. |

## Current execution

Improved named/focusable 48px map controls, responsive panels and non-color status language; web entrypoint now keeps semantics enabled. Local Brave debug build visibly rendered sign-in and displayed both blank-field errors. Automated viewport/theme/contrast checks passed. This is not full screen-reader or engine-matrix acceptance.

**Remaining:** Full human keyboard/screen-reader, actual zoom, authenticated map/report and permission matrix; Other required browser engines/platforms and exact final release acceptance

[Execution evidence](../defense-evidence/web-fix-execution/phase-06/README.md).
