# Phase 03: Repair the responsive web shell and navigation

[Plan index](README.md) · [Execution rules](EXECUTION_RULES.md) · [Issue crosswalk](ISSUE_CROSSWALK.md)

**Status:** PARTIAL — see current execution below.

**Goal:** Keep authorized operators working across window sizes and provide consistent theme, usable navigation, activity and help.

**Primary skill:** [geosustain-web-shell](skills/geosustain-web-shell/SKILL.md). Read this skill before executing the phase.

**Dependencies:** [Phase 00](PHASE_00_Web_Baseline_and_Hosting.md)

Dependencies establish baseline/final acceptance order. Provider setup in Phase 01 does not block independent source fixes in Phases 02–05; its live gates remain open until completed.

**Issues owned:** WEB-05: Operator access changes when the browser becomes narrow or short, WEB-12: Desktop surfaces bypass the shared theme, WEB-13: The shared desktop header contains inactive menu and bell icons, WEB-14: How It Works is an enabled button with an empty callback, WEB-15: Portal pages are index state rather than browser routes

## Relevant implementation

- [lib/main.dart](../lib/main.dart)
- [lib/web/web_analyst_shell.dart](../lib/web/web_analyst_shell.dart)
- [lib/web/web_admin_shell.dart](../lib/web/web_admin_shell.dart)
- [lib/web/widgets/web_common.dart](../lib/web/widgets/web_common.dart)
- [lib/web/auth/web_auth_login.dart](../lib/web/auth/web_auth_login.dart)
- [lib/web/screens/web_dashboard_screen.dart](../lib/web/screens/web_dashboard_screen.dart)
- [lib/web/screens/web_analyze_screen.dart](../lib/web/screens/web_analyze_screen.dart)
- [lib/web/screens/web_trends_weather_soil_settings_screen.dart](../lib/web/screens/web_trends_weather_soil_settings_screen.dart)
- [web/index.html](../web/index.html)
- [deployment/vercel.json](../deployment/vercel.json)

## External inputs and limitations

Exact browser/OS and supported zoom evidence requires a real compiled browser. New routes must match the deployed Vercel SPA setup.

## Work and acceptance

### W03-01: Separate role permission from viewport layout

Remove analyst/admin access denial caused solely by width/height. Keep backend authorization and unknown-role denial intact. Add a responsive drawer/rail/sidebar transition and reflow dashboard, analysis toolbars, settings and admin tables while preserving selected record, form input and analysis state.

**Acceptance:** Resizing or zoom does not change the authorized role or discard work. Narrow/short windows remain operable without ordinary controls being clipped.

**Evidence:** responsive widget checks and real resize/zoom observations.

**Initial status:** NOT_STARTED.

### W03-02: Make theme colors coherent across desktop screens

Replace incompatible hard-coded surfaces/text with paired theme values, or explicitly apply a consistent supported portal theme. Cover auth/logout/register, dashboard, map overlays, results, history, planner/admin dialogs and settings. Preserve the requested GeoSustain branding; do not redesign unrelated mobile screens.

**Acceptance:** The supported light/dark choices persist and text/selection/focus/errors remain readable on actual painted surfaces.

**Evidence:** paired screenshots and measured contrast samples.

**Initial status:** NOT_STARTED.

### W03-03: Wire menu, activity and useful help

Make the menu icon open/collapse real navigation; connect the bell to a unified permission-aware activity destination with unread/read state. Implement How It Works as a short selection→analysis→save/report→review guide that explains partial results. Weather advisories remain clearly separated from review/activity events.

**Acceptance:** Pointer and keyboard activate each offered control and return to preserved work; no enabled no-op remains in the reviewed shell.

**Evidence:** navigation/action inventory and interaction case results.

**Initial status:** NOT_STARTED.

### W03-04: Add browser routes with safe return state

Define stable role-aware routes for dashboard, analysis, history, reports, queue, settings and appropriate record detail. Decide which harmless filters/selection belong in URLs versus local state. Configure SPA fallback only as necessary and fetch authorized details after login; do not trust record IDs or notification payloads as permission.

**Acceptance:** Direct links, reload and Back/Forward work for permitted targets. Unauthorized or missing IDs have a useful safe destination and do not expose cached foreign records.

**Evidence:** route matrix, browser history observations and negative ID checks.

**Initial status:** NOT_STARTED.

### W03-05: Preserve auth and pending-work transitions

Verify layout changes, tab changes, login/logout and route transitions do not resurrect old users, old results or abandoned polygons. Keep in-flight work truthful and provide a recoverable pending/error state rather than silently hiding it.

**Acceptance:** Account switching and viewport/route changes retain only the correct owner's intended state; returning to an analysis does not duplicate submission.

**Evidence:** state-transition regressions and matching browser cases.

**Initial status:** NOT_STARTED.

## Focused verification

- **WEB-05:** The same operator remains on a usable screen at desktop, narrow and short sizes and at agreed 200/400% zoom. No role changes or lost work occur solely from resizing.
- **WEB-12:** Measure actual painted text/surface contrast and inspect all required states in light and dark; keyboard focus remains visible in both.
- **WEB-13:** Keyboard and pointer can open/close navigation and activity, mark permitted events read and return to the prior work without losing state.
- **WEB-14:** The button opens usable help and returns to the same screen; every promised step corresponds to an implemented action.
- **WEB-15:** Direct authorized URLs, refresh, Back/Forward, copied links and unauthorized IDs all have documented correct outcomes.

## Exit and handover

Store actual execution under `defense-evidence/web-fix-execution/phase-03/`; start from [EVIDENCE_TEMPLATE.json](EVIDENCE_TEMPLATE.json). Link source/frontend/backend identity, expected versus actual results, test/provider/browser scope and remaining gates.

The phase is complete only when its full acceptance is supported. Source-only fixes can be handed on with pending live dependencies recorded; do not mark the whole phase complete from a build or plan file.

| Task | Current state | Evidence | Remaining gate |
| --- | --- | --- | --- |
| W03-01 | CODE_COMPLETE | Current execution below | Resizing or zoom does not change the authorized role or discard work. Narrow/short windows remain operable without ordinary controls being clipped. |
| W03-02 | CODE_COMPLETE | Current execution below | The supported light/dark choices persist and text/selection/focus/errors remain readable on actual painted surfaces. |
| W03-03 | CODE_COMPLETE | Current execution below | Pointer and keyboard activate each offered control and return to preserved work; no enabled no-op remains in the reviewed shell. |
| W03-04 | CODE_COMPLETE | Current execution below | Direct links, reload and Back/Forward work for permitted targets. Unauthorized or missing IDs have a useful safe destination and do not expose cached foreign records. |
| W03-05 | CODE_COMPLETE | Current execution below | Account switching and viewport/route changes retain only the correct owner's intended state; returning to an analysis does not duplicate submission. |

## Current execution

Web role routing no longer denies access solely on window size; adaptive portal frame/drawer, theme pairing, help/activity destinations and role-aware hash routes implemented. Focused widget checks passed at 1000x500, 480x700 and 1280x900 including dark-mode transition. Theme interpolation and sidebar overflow found by tests were fixed.

**Remaining:** Actual authenticated browser Back/Forward/deep-link and cache journeys; Full dark/light screen and zoom matrix on final deployed bundle

[Execution evidence](../defense-evidence/web-fix-execution/phase-03/README.md).
