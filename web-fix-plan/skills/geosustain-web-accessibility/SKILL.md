---
name: geosustain-web-accessibility
description: "Execute actual GeoSustain desktop keyboard, contrast, zoom/reflow, map and download acceptance on recorded browser targets."
---

# Validate keyboard, accessibility and browser behavior

Use [Phase 06](../../PHASE_06_Accessibility_and_Browser_Acceptance.md) for work items and acceptance. Read [web execution rules](../../EXECUTION_RULES.md) and the relevant review findings before changes.

These instructions refine decisions for this web phase; they do not supply provider credentials, scientific validation or new external authorization.

- Use the supported computer-use/browser interface when available; read its installed skill at that time. If no controllable browser exists, guide concise user steps and mark the result user-confirmed or pending.
- Tab/Enter/Escape operation, visible focus, dialog focus return and meaningful map labels need human/browser evidence. Semantics or a compiled web build alone is not screen-reader acceptance.
- Actual browser zoom can change the portal's effective viewport and previously triggered role denial. Test short windows as well as narrow widths, retaining exact target dimensions/zoom.
- Distinguish map two-dimensional interaction from ordinary text/control reflow. Provide workable coordinates/selection alternatives instead of silently exempting the entire workflow.
- Retain agreed unavailable browser/platform targets as pending. Simulated viewports or WebKit automation are not automatically a real Safari/device result.

Record actual outcomes in the project tracker and `defense-evidence/web-fix-execution/phase-06/`. If a prerequisite is absent, state the missing input and continue independent authorized work rather than converting the case to PASS.
