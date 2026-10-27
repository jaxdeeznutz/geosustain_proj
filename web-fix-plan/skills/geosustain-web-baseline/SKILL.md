---
name: geosustain-web-baseline
description: "Identify GeoSustain web deployments and apply frontend hosting/cache policies when fixing WEB-02 and WEB-03."
---

# Verify the deployed web baseline and hosting

Use [Phase 00](../../PHASE_00_Web_Baseline_and_Hosting.md) for work items and acceptance. Read [web execution rules](../../EXECUTION_RULES.md) and the relevant review findings before changes.

These instructions refine decisions for this web phase; they do not supply provider credentials, scientific validation or new external authorization.

- Treat the current source, previously built web directory and hosted Vercel bundle as different identities until provenance matches. A hash difference is a prompt to inspect build metadata, not proof of a stale release.
- deployment/vercel.json is ineffective unless the real Vercel root/output configuration consumes it; test public response headers, not just file existence.
- Keep /health, /ready, actual browser flows and provider delivery separate. The recorded readiness failure concerns email configuration while database/model passed.
- Use owned access already authorized by the user; request only missing external access/settings. This planning skill adds no permission to change unrelated services or accept provider terms.

Record actual outcomes in the project tracker and `defense-evidence/web-fix-execution/phase-00/`. If a prerequisite is absent, state the missing input and continue independent authorized work rather than converting the case to PASS.
