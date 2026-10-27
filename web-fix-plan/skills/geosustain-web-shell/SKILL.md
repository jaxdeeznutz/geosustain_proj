---
name: geosustain-web-shell
description: "Repair GeoSustain operator viewport access, desktop theme pairing, activity/help controls and browser navigation state."
---

# Repair the responsive web shell and navigation

Use [Phase 03](../../PHASE_03_Responsive_Shell_Theme_and_Navigation.md) for work items and acceptance. Read [web execution rules](../../EXECUTION_RULES.md) and the relevant review findings before changes.

These instructions refine decisions for this web phase; they do not supply provider credentials, scientific validation or new external authorization.

- Viewport width/height is a layout input, not a role authorization rule. Preserve backend/unknown-role denial while letting authorized operators use narrow or zoomed windows.
- The existing state contains selected geometry and long-running analysis; moving between a drawer/sidebar or URL routes must not duplicate analysis or resurrect a different owner's result.
- A menu/bell must be actionable and keyboard named or presented without a control affordance. Route activity to the existing permission-aware event model; do not invent weather push.
- Pair hard-coded surfaces and inherited text consistently across auth/logout and portal dialogs. Avoid unrelated mobile redesign while fixing shared components.
- Use actual browser Back/reload and deep-link permission checks to accept routes; integer page-state widget tests alone cannot prove browser history behavior.

Record actual outcomes in the project tracker and `defense-evidence/web-fix-execution/phase-03/`. If a prerequisite is absent, state the missing input and continue independent authorized work rather than converting the case to PASS.
