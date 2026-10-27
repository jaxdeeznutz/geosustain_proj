# Analyst website and farmer app separation

The owner completed farmer signup in a phone browser and reported that verification returned to the analyst login. The website exposed a Create Farmer Account action although its intended audience is analysts and administrators. The assistant had incorrectly directed the owner to that web signup action during email acceptance.

## Current repair

- Remove farmer signup from the web login and explain administrator-assigned analyst access and farmer mobile-app access.
- Guard the farmer registration page on web so stale navigation cannot reopen its form.
- Deny farmer browser workspaces (including restored sessions), retaining the existing mobile-app guidance and explicit sign-out action. Existing server operator authorization remains unchanged.
- Use the client platform rather than viewport size to choose the login and workspace. Native farmer signup/verification returns to farmer sign-in even on a wide device.
- Start workspace loads, weather refresh and push restoration only after role/platform acceptance. Hide the farmer offline shortcut on web.
- Match the existing server analyst role allowlist exactly; keep administrator access for account administration.
- Existing accounts and data are preserved. This is a frontend routing change; no account is promoted and no password, dataset, NPK or soil pH is changed.

## Actual validation

- Focused auth/session/mobile-shell VM run: 20 passed.
- Final workspace/scoped-analysis/web-remediation/operator-workflow VM run: 37 passed, including the 7 workspace tests repeated from the focused run (50 distinct checks across both runs).
- Dart analysis of lib and changed tests: no issues found.
- Headless Chrome web-test attempts did not progress beyond loading and were canceled; no browser-test pass is claimed. Initial testing also hit a full C: drive. Task temporary files and the generated Flutter build cache were moved to D: without deleting source or APK files.
- Release compilation and hosted asset identity are recorded separately after publication.

## Email acceptance scope

The corrected Brevo API key produced a verification challenge after provider acceptance and the owner confirmed email receipt. The owner also reported completing another signup using a different email in the phone browser. That report does not establish subsequent farmer sign-in, password recovery, expired/replayed-code handling, or session revocation. Those acceptance gates stay pending. Codes, credentials and recipient addresses are omitted.
