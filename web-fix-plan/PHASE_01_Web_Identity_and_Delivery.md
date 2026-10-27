# Phase 01: Complete web authentication and delivery setup

[Plan index](README.md) · [Execution rules](EXECUTION_RULES.md) · [Issue crosswalk](ISSUE_CROSSWALK.md)

**Status:** PARTIAL — see current execution below.

**Goal:** Make required email, Google, profile phone and web push capabilities usable with clear configuration and real receipt evidence.

**Primary skill:** [geosustain-web-identity](skills/geosustain-web-identity/SKILL.md). Read this skill before executing the phase.

**Dependencies:** [Phase 00](PHASE_00_Web_Baseline_and_Hosting.md)

Dependencies establish baseline/final acceptance order. Provider setup in Phase 01 does not block independent source fixes in Phases 02–05; its live gates remain open until completed.

**Issues owned:** WEB-01: Required email service is not configured on Render, WEB-10: Google sign-in and web background push are not configured, WEB-11: Desktop settings do not expose the implemented identity controls

## Relevant implementation

- [lib/web/auth/web_auth_login.dart](../lib/web/auth/web_auth_login.dart)
- [lib/web/screens/web_trends_weather_soil_settings_screen.dart](../lib/web/screens/web_trends_weather_soil_settings_screen.dart)
- [lib/screens/identity_settings.dart](../lib/screens/identity_settings.dart)
- [lib/firebase_runtime.dart](../lib/firebase_runtime.dart)
- [lib/federated_identity.dart](../lib/federated_identity.dart)
- [lib/push_notifications.dart](../lib/push_notifications.dart)
- [web/firebase-config.js](../web/firebase-config.js)
- [web/firebase-messaging-sw.js](../web/firebase-messaging-sw.js)
- [backend/mail_delivery.py](../backend/mail_delivery.py)
- [backend/email_verification.py](../backend/email_verification.py)
- [backend/password_reset.py](../backend/password_reset.py)
- [backend/federated_identity.py](../backend/federated_identity.py)
- [deployment/IDENTITY_AND_DELIVERY_SETUP.md](../deployment/IDENTITY_AND_DELIVERY_SETUP.md)

## External inputs and limitations

No owned Firebase project was supplied. A real sender/domain, private provider configuration and authorized test recipients are also needed. Work on UI and controlled tests can continue while these remain pending.

## Work and acceptance

### W01-01: Resolve the required email readiness failure

Use the existing mail transport integration with an owned sender and supported delivery configuration on Render. Keep secrets on the host and preserve required email verification. Do not disable a required flag to obtain a green readiness result.

**Acceptance:** Live /ready reports required email configuration ready; configuration presence is recorded separately from message receipt.

**Evidence:** sanitized configuration-presence/readiness results.

**Initial status:** NOT_STARTED.

### W01-02: Accept real signup and recovery journeys

With authorized disposable accounts, verify actual email receipt, valid/wrong/expired code, resend/guess limits, one-use behavior, duplicate email and readable field errors. Test recovery separately and confirm older sessions are invalidated while existing accounts still sign in.

**Acceptance:** Both delivered signup verification and recovery complete with bounded invalid attempts and no account enumeration or automatic privilege grant.

**Evidence:** redacted receipt metadata, case results and session revocation checks.

**Initial status:** NOT_STARTED.

### W01-03: Configure owned Google and web push identities

Create or select the owner-controlled project through available authorized access, configure actual Vercel domain/OAuth web client and public Flutter identifiers, and align service-worker config/VAPID with backend project credentials. Keep service-account keys out of web assets. State any SMS billing/quota or provider dependency as an owner input rather than promising a free service.

**Acceptance:** All client/server public project identifiers match, required backend checks are honest, and unconfigured features have clear UI explanations.

**Evidence:** public configuration identity manifest without private values.

**Initial status:** NOT_STARTED.

### W01-04: Expose complete desktop identity settings

Mount or adapt IdentityProfileSection in desktop settings: phone edit/verified state, OTP request/verify and explicit Google linking. Keep verification bound to the current owner and exact normalized number; show inline invalid/pending/unavailable feedback. Preserve admin-only role assignment.

**Acceptance:** A desktop operator can reach and complete the intended controls without switching to a farmer/mobile layout. Wrong/expired/replayed proof and changed-number invalidation behave correctly.

**Evidence:** desktop integration tests and redacted browser case evidence.

**Initial status:** NOT_STARTED.

### W01-05: Verify actual Google, SMS and background push

Use authorized test accounts/recipients only. Test Google login versus explicit linking, the current phone challenge and real SMS receipt, browser permission grant/deny, foreground/background web push, notification click and reauthentication. A mocked accepted delivery or visible inbox is not background receipt.

**Acceptance:** Real provider outcomes are recorded separately for acceptance, receipt and authorized target opening. Unsupported or unavailable states remain pending with reasons.

**Evidence:** provider/browser outcome matrix with no codes, tokens or private payloads.

**Initial status:** NOT_STARTED.

### W01-06: Handle sign-in and recovery errors consistently

Keep field errors and corrected input readable across desktop auth pages, add a labelled password-visibility control where missing, and preserve retry/draft behavior during a cold backend or expired session. Add no new login mechanism beyond the existing project requirements.

**Acceptance:** Invalid input, incorrect password, expired session, provider unavailable and network failure give distinct recoverable feedback without leaking account data.

**Evidence:** focused widget regressions plus live error-state observations.

**Initial status:** NOT_STARTED.

## Focused verification

- **WEB-01:** Live /ready returns 200 and real verification/recovery messages arrive; a configuration-only pass does not count as delivery proof.
- **WEB-10:** Google sign-in and explicit linking complete; browser subscription exists; a real authorized event produces a received background notification that opens the correct permitted record.
- **WEB-11:** On the desktop portal, edit a number, request/verify OTP, reject wrong/expired proof and explicitly link an owned Google account. Unconfigured services have a clear explanation.

## Exit and handover

Store actual execution under `defense-evidence/web-fix-execution/phase-01/`; start from [EVIDENCE_TEMPLATE.json](EVIDENCE_TEMPLATE.json). Link source/frontend/backend identity, expected versus actual results, test/provider/browser scope and remaining gates.

The phase is complete only when its full acceptance is supported. Source-only fixes can be handed on with pending live dependencies recorded; do not mark the whole phase complete from a build or plan file.

| Task | Current state | Evidence | Remaining gate |
| --- | --- | --- | --- |
| W01-01 | PENDING_EXTERNAL | Current execution below | Live /ready reports required email configuration ready; configuration presence is recorded separately from message receipt. |
| W01-02 | PENDING_EXTERNAL | Current execution below | Both delivered signup verification and recovery complete with bounded invalid attempts and no account enumeration or automatic privilege grant. |
| W01-03 | PENDING_EXTERNAL | Current execution below | All client/server public project identifiers match, required backend checks are honest, and unconfigured features have clear UI explanations. |
| W01-04 | VERIFIED_LOCAL | Current execution below | A desktop operator can reach and complete the intended controls without switching to a farmer/mobile layout. Wrong/expired/replayed proof and changed-number invalidation behave correctly. |
| W01-05 | PENDING_EXTERNAL | Current execution below | Real provider outcomes are recorded separately for acceptance, receipt and authorized target opening. Unsupported or unavailable states remain pending with reasons. |
| W01-06 | VERIFIED_LOCAL | Current execution below | Invalid input, incorrect password, expired session, provider unavailable and network failure give distinct recoverable feedback without leaking account data. |

## Current execution

Desktop identity/profile and push controls integrated, Google-unavailable guidance and password visibility added. Twelve focused identity/auth tests passed before the broader 184-test run. Public-only deployment configuration now aligns the client and FCM worker.

**Remaining:** Owned email sender and Firebase Auth/FCM project configuration; Real email/SMS/Google/background push receipt and target-opening cases

[Execution evidence](../defense-evidence/web-fix-execution/phase-01/README.md).
