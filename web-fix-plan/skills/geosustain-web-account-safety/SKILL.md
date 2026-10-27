---
name: geosustain-web-account-safety
description: "Protect GeoSustain desktop delete/deactivate actions and choose/test a compatible browser session security design."
---

# Protect account actions and the browser session

Use [Phase 05](../../PHASE_05_Account_Actions_and_Web_Session_Security.md) for work items and acceptance. Read [web execution rules](../../EXECUTION_RULES.md) and the relevant review findings before changes.

These instructions refine decisions for this web phase; they do not supply provider credentials, scientific validation or new external authorization.

- Use disposable isolated accounts for delete/deactivate evidence, preserving the accepted owned-data removal and anonymized audit policy. Do not exercise destructive production actions to fill a QA row.
- Cancellation must send no API request; only confirmed server success triggers final client cleanup. Failed operations must not discard valid account work or claim success.
- JavaScript-accessible web preferences are not Android protected storage. This is a session design risk, not an already demonstrated XSS exploit.
- Choose and record bearer hardening versus HttpOnly session behavior before implementation. Cookie designs require actual domain/SameSite/CORS/CSRF testing and must preserve the shared API/client contract.
- Changing the web session path can affect deferred mobile clients. Record affected checks for later; do not uninstall user apps or claim their compatibility from web tests.

Record actual outcomes in the project tracker and `defense-evidence/web-fix-execution/phase-05/`. If a prerequisite is absent, state the missing input and continue independent authorized work rather than converting the case to PASS.
