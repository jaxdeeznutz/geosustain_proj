---
name: geosustain-web-identity
description: "Complete GeoSustain desktop email, Google, phone proof and web push integration with real owned provider acceptance."
---

# Complete web authentication and delivery setup

Use [Phase 01](../../PHASE_01_Web_Identity_and_Delivery.md) for work items and acceptance. Read [web execution rules](../../EXECUTION_RULES.md) and the relevant review findings before changes.

These instructions refine decisions for this web phase; they do not supply provider credentials, scientific validation or new external authorization.

- Existing password accounts must remain usable. Backend verification and safe explicit linking determine identity; email-only matching must not take over an account or grant a planner/admin role.
- Required production email verification is already enabled by the reviewed behavior. Do not reuse stale instructions that call the current production flow disabled by default.
- Mount the existing shared identity component in desktop settings rather than implementing a second incompatible phone/linking protocol.
- Google/SMS need Firebase Auth configuration; background web push additionally needs aligned worker/VAPID/backend credentials. Never ship a service-account key to the browser.
- Provider acceptance, human receipt and authorized target opening are distinct evidence. Keep live tests on owned disposable identities and explicitly authorized recipients; absent credentials or receipts leave a provider gate pending.

Record actual outcomes in the project tracker and `defense-evidence/web-fix-execution/phase-01/`. If a prerequisite is absent, state the missing input and continue independent authorized work rather than converting the case to PASS.
