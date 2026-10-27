# Phase 05: Protect account actions and the browser session

[Plan index](README.md) · [Execution rules](EXECUTION_RULES.md) · [Issue crosswalk](ISSUE_CROSSWALK.md)

**Status:** PARTIAL — see current execution below.

**Goal:** Prevent accidental destructive account actions and establish an explicit, tested web session design without breaking shared clients.

**Primary skill:** [geosustain-web-account-safety](skills/geosustain-web-account-safety/SKILL.md). Read this skill before executing the phase.

**Dependencies:** [Phase 00](PHASE_00_Web_Baseline_and_Hosting.md)

Dependencies establish baseline/final acceptance order. Provider setup in Phase 01 does not block independent source fixes in Phases 02–05; its live gates remain open until completed.

**Issues owned:** WEB-06: Web account deletion and deactivation execute directly, WEB-17: The web bearer token is stored in JavaScript-accessible preferences

## Relevant implementation

- [lib/web/screens/web_trends_weather_soil_settings_screen.dart](../lib/web/screens/web_trends_weather_soil_settings_screen.dart)
- [lib/session_token_store.dart](../lib/session_token_store.dart)
- [lib/api_service.dart](../lib/api_service.dart)
- [lib/screens/session_gate.dart](../lib/screens/session_gate.dart)
- [lib/main.dart](../lib/main.dart)
- [backend/fastapi_app.py](../backend/fastapi_app.py)
- [deployment/vercel.json](../deployment/vercel.json)

## External inputs and limitations

Destructive acceptance uses isolated disposable accounts/data. Cookie/session decisions require the actual Vercel/Render domain behavior and an explicit compatibility design; no production user is deleted for testing.

## Work and acceptance

### W05-01: Add deliberate account-action confirmation

Show clear consequences and cancellation before delete/deactivate, with appropriate recent authentication for the chosen design. Disable repeated actions while pending and catch server/network errors. Preserve the approved deletion rule for owned farms/coordinates/analyses/photos/reports and anonymized audits.

**Acceptance:** Cancel sends no request. Confirmation sends one request. Failure leaves a useful retry state and does not falsely claim deletion.

**Evidence:** controlled API/UI tests with disposable identity fixtures.

**Initial status:** NOT_STARTED.

### W05-02: Complete post-action logout and state cleanup

After confirmed server success, revoke/clear the correct session, remove owner-bound client caches/subscriptions as required and leave the protected portal. Avoid clearing user work before an unsuccessful server action. Test account switch and stale asynchronous results.

**Acceptance:** Deleted/deactivated accounts cannot remain in a usable protected shell; Back/reload cannot expose prior-owner data; failed actions do not lose unrelated valid data.

**Evidence:** session/lifecycle regression results and disposable browser case.

**Initial status:** NOT_STARTED.

### W05-03: Choose and document the web session boundary

Review the existing JavaScript-accessible bearer preference store, expiry and revocation against actual domains and script exposure. Compare a secure HttpOnly session design with a deliberately hardened bearer approach; document the selected tradeoff. A cookie migration needs intentional SameSite/CORS/CSRF and shared API compatibility, not a local storage rename.

**Acceptance:** A clear design decision identifies token/cookie lifetime, logout, recovery, account isolation and browser script assumptions. Android protected storage is not cited as web protection.

**Evidence:** WEB_SESSION_DECISION.md and compatibility/threat cases.

**Initial status:** NOT_STARTED.

### W05-04: Implement the selected session hardening and retest roles

Apply only the selected design, aligning frontend response policies and server checks. Retest expired/revoked sessions, logout, password reset/version changes, cross-account caches, role/owner denial and required CSRF/cookie behavior. Preserve mobile transport compatibility even though mobile testing is deferred; record any affected mobile cases for later.

**Acceptance:** The changed session design passes the relevant browser/API security cases and a normal authorized role journey without weakening backend role/owner checks.

**Evidence:** focused security regressions and live/staging role/session outcomes.

**Initial status:** NOT_STARTED.

## Focused verification

- **WEB-06:** Cancel sends no request; confirm sends one; failure retains a usable view; successful deletion/deactivation clears client state and leaves the protected portal. Use disposable staging accounts.
- **WEB-17:** A reviewed session design has tested logout, expiry, cross-account isolation and relevant script/cookie controls on the actual domains.

## Exit and handover

Store actual execution under `defense-evidence/web-fix-execution/phase-05/`; start from [EVIDENCE_TEMPLATE.json](EVIDENCE_TEMPLATE.json). Link source/frontend/backend identity, expected versus actual results, test/provider/browser scope and remaining gates.

The phase is complete only when its full acceptance is supported. Source-only fixes can be handed on with pending live dependencies recorded; do not mark the whole phase complete from a build or plan file.

| Task | Current state | Evidence | Remaining gate |
| --- | --- | --- | --- |
| W05-01 | VERIFIED_LOCAL | Current execution below | Cancel sends no request. Confirmation sends one request. Failure leaves a useful retry state and does not falsely claim deletion. |
| W05-02 | VERIFIED_LOCAL | Current execution below | Deleted/deactivated accounts cannot remain in a usable protected shell; Back/reload cannot expose prior-owner data; failed actions do not lose unrelated valid data. |
| W05-03 | COMPLETE | Current execution below | A clear design decision identifies token/cookie lifetime, logout, recovery, account isolation and browser script assumptions. Android protected storage is not cited as web protection. |
| W05-04 | VERIFIED_LOCAL | Current execution below | The changed session design passes the relevant browser/API security cases and a normal authorized role journey without weakening backend role/owner checks. |

## Current execution

Added confirmation/cancel, pending-action protection and reauthentication for desktop delete/deactivate; correct-owner password or recent linked Google proof is required by the server. Successful account closure leaves protected routes. Retained and documented hardened bearer session design rather than an untested cookie migration. Controlled UI cancellation and real isolated SQL disposable-account deletion/session rejection passed.

**Remaining:** Actual browser logout/expiry/account-switch and hosted policy acceptance; Documented browser JavaScript-accessible bearer residual risk remains

[Execution evidence](../defense-evidence/web-fix-execution/phase-05/README.md).
