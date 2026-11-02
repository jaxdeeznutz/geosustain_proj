# Google sign-in release candidate

This candidate includes the accepted analyst/superadmin designs, farmer
readability and legends, Google password setup, and the owner's public Firebase
app configuration. Non-authentication backend code and scientific assets are
unchanged from the recorded baseline. Phases 8-9 remain paused.

Validation before the candidate commit:

- Owner verifier `verify-google-password-setup.ps1`: all six checks passed.
  Local receipt: `defense-evidence/google-password-setup/attempts/20261102-163452-228/validation.json`.
- Fresh backend and Web-build helper test run: 524 passed, 5 warnings.
- Public Android config matches `google-services (3).json`, including the
  normal package and this computer's debug SHA-1.
- The Web build automatically includes the checked-in public Firebase config
  unless complete host environment identifiers override it. No application
  Dart source changed after the owner's Flutter checks.

## Publish the prepared commit

The agent could not connect to GitHub from the terminal; the browser-control
runtime was also unavailable. No cloud deployment is claimed. From the project
root, publish the prepared branch in the owner's terminal:

```powershell
git push origin defense/implementation-2026-10-23
git rev-parse HEAD
```

The prepared commit excludes generated report PDFs, local tools, private keys,
environment files, screenshots, test databases and unreviewed QA artifacts.
Public Firebase identifiers are deliberately included; service-account and
Brevo secrets remain on the host.

## Render backend

Record the previous live revision and private database backup before the
additive migration. Preserve the current database and `SECRET_KEY`. The new
`password_setup_required` column defaults to false for existing accounts;
startup adds it idempotently.

Confirm `FIREBASE_AUTH_PROJECT_ID=geosustain-4c722` is saved. Confirm Render's
linked repository and branch. If this is the linked branch, deploy the latest
commit. Otherwise deploy the explicit published commit using **Manual Deploy
> Deploy a specific commit**. That Render option disables auto-deploys; record
the setting and choose the intended linked branch before re-enabling them.
Do not force-push or reset a branch to deploy this candidate.

Wait for the service to be Live at the intended revision, then check `/health`
and `/ready`. These checks do not prove Google or email delivery.

## Client

Deploy the same commit on the Web host using the root `vercel.json`. A branch
preview alone does not update production. Confirm the Web Firebase authorized
domains include the actual host and `localhost` for local testing. Verify
`/build-info.json` matches the intended release. The hosted build can now read
`deployment/firebase-web.public.json` without adding all its public values to
host environment settings.

Android debug testing uses `deployment/firebase-android.public.json` as detailed
in `FIREBASE_RECONNECT.md`. An installed older APK does not gain the new config
automatically. Release APK signing requires its own matching fingerprint and
an intentional versioned build; no release APK is built or published here.

Finally test new Google farmer > create password > save a farm > sign out >
email/password login > confirm the same account/farm > sign out > Google login.
Existing account linking and privileged role checks remain mandatory. Live
Google/provider acceptance is pending until performed against matching releases.

Render reference: https://render.com/docs/deploys#deploying-a-specific-commit
