# Google sign-in with one-time GeoSustain password setup

Owner selected this flow: create a password after the first
Google login, then permit Google or email/password login into the same account.
This explicitly adds authentication backend behavior; it is separate from the
earlier UI-only work whose backend hashes were held fixed.

## User flow

1. The existing Google/Firebase flow obtains a recent, verified Google identity.
2. A new Google account is created with the server-owned Farmer role and
   `password_setup_required=true`. No second account is created for the password.
3. A restricted, 15-minute setup session opens Create your GeoSustain password.
   The user confirms the password, or signs out. Back cannot bypass this step.
4. The server validates the existing password policy, locks the current account,
   writes a bcrypt hash, clears the flag, increments the password version and
   records an audit event in the same transaction. It preserves ID, email, role,
   Google subject and other records. Repeated/stale setup cannot overwrite it.
5. A new normal session replaces the setup session. The old version is rejected.
   Later Google and existing email/password login both resolve to this user ID.

This is a **GeoSustain password**, stored by the existing backend. It is not the
Google password and is not a new Firebase Email/Password credential. Firebase
continues providing Google proof; the backend continues owning roles and app
sessions. The general multiple-provider linking model is described in
[Firebase's account-linking documentation](https://firebase.google.com/docs/auth/flutter/account-linking).
No Firebase project, provider setting or external service was modified here.

## Enforcement and compatibility

- Pending accounts can only read their own basic profile, finish setup or sign
  out. All workspace, farm, review, administration and phone/linking routes remain
  blocked by the common server authentication dependency.
- Setup tokens carry a distinct signed scope and expire in 15 minutes. Tokens
  without that scope cannot be used to bypass a pending setup. Disabled accounts,
  wrong versions, unknown purposes and malformed payloads are rejected.
- User IDs, emails, roles and setup flags are forbidden in the setup request;
  the authenticated server-side identity determines the account.
- Restored sessions resume setup. Cached pending identities cannot enter the
  offline workspace, and the app state does not bootstrap workspace resources
  until setup is complete.
- Passwords never enter cached identity/preferences or audit details. Client
  account-switch checks reject a late response from another session. The form
  disables repeat submissions and uses the existing password policy and errors.
- Existing accounts default to no setup requirement. Linking Google to an
  existing password account still requires the original password and same email.
  Existing passwords are not guessed, overwritten or retroactively invalidated.
  Legacy Google-only accounts from before this change can use the existing email
  password-recovery flow to choose a password; their old hashes are not classified
  heuristically by this migration.
- Existing email and administrator recovery flows clear the setup flag when a
  real new password is saved. Google password setup itself sends no Brevo code:
  it starts from a verified Google proof. Existing Brevo email flows remain intact.
- If setup commits but the response is lost, signing in with Google again returns
  the same account with setup completed; it does not create a duplicate account.

## Migration and release scope

`init_db()` adds `users.password_setup_required BOOLEAN NOT NULL DEFAULT FALSE`
idempotently. Newly created Google accounts explicitly opt into the requirement.
No existing account or farm is deleted. Apply the matching backend migration and
client version together. Updating only the client does not enforce this feature.
The running backend/demo host was not restarted and no production migration or
deployment was performed by this task.

Changes are confined to six existing authentication/schema/test files in the
backend, the new backend test file, the API client, login/session/offline gates
and the password-setup screen. Models, scientific data, scoring, explanations,
farm ownership and review rules are unchanged. Scientific Phases 8–9 remain paused.

The pre-change backend hashes are preserved in
`defense-evidence/google-password-setup/backend-before.json`. Historical UI-only
verifiers intentionally compare against their pre-authentication baselines;
use this feature's verifier for the current candidate rather than rewriting
those old baselines:

```powershell
.\deployment\verify-google-password-setup.ps1
```

The script checks all non-authentication backend hashes before and after the full
backend suite, offline Pub resolution, Flutter analysis/tests and web build. It
records real exit codes and logs and performs no deployment or backend restart.

## Verification recorded in this editing session

- 72 targeted backend identity/password tests passed.
- Full backend suite: **517 passed**, five existing warnings, 39.85 seconds.
- New backend tests cover token scope/expiry, workspace denial, owner binding,
  password validation, role preservation, old-session rejection, both subsequent
  login methods, repeated setup, disabled accounts and transaction rollback.
- Dart formatting passes. Standalone analysis cannot resolve protected Pub-cache
  packages, so it is not credited as a Flutter analyzer pass.
- New Flutter tests cover responsive validation, confirmation mismatch, current
  account transport, no plaintext persistence, double-submit prevention, sign-out,
  session restoration, offline denial and late-response ownership. Full Flutter
  checks and physical Android/web acceptance remain pending in the owner's terminal.

Live acceptance after the owned Firebase configuration is ready: create a new
Google farmer, finish setup, create/save a farm, sign out, use email/password and
confirm the same farm, then sign out/use Google and confirm the same ID and farm.
Also test cancelled setup/reopening, duplicate email linking, password recovery,
and any assigned privileged role using the intended deployed releases. No live
Google, SMS, push or email receipt is claimed by the isolated tests.
