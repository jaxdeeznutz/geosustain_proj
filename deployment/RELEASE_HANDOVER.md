# Release and local QA handover

Current execution evidence: [readiness execution](../defense-evidence/readiness-execution/README.md). This source has not been deployed to Render or Vercel. A signed build is a candidate, not a completed live release.

## Signing and configuration

Release builds require `android/key.properties`; there is no debug-signing fallback. The initial private key is stored under the current Windows user's `.geosustain-signing` directory. `release-password.txt` and the keystore are owner-only ACL files. Keep an encrypted backup with the project owner; losing the release key prevents updates to apps installed under that key. Do not commit any of these files or send their contents in chat. Any existing store signing identity must be reconciled before publishing this newly signed candidate.

The release application ID remains `com.example.geosustain_clean_arranged`, version `1.0.1+2`. Manual local QA uses `.phoneqa`; automated tests use `.automatedqa`. They have separate data. Never uninstall the manual app to resolve a signing mismatch.

Build release using only public config and the intended HTTPS API:

```powershell
flutter pub get
flutter build apk --release --dart-define=API_BASE_URL=https://geosustain.onrender.com
```

Add the public Firebase defines described in [provider setup](IDENTITY_AND_DELIVERY_SETUP.md) once the owned project exists. Never include `QA_*` private fixture defines in a release. Release code rejects a non-HTTPS API URL. The main Android manifest blocks cleartext; only the debug overlay permits local HTTP.

## Deploy the matching candidate

1. Review the full dirty/untracked tree, include required source/data/assets/web files, exclude local tools, credentials and fixture artifacts, and create deliberate commits. Record source, model, APK/web and backend revision hashes. Do not push historical evidence containing personal information.
2. Select actual staging/live database and hosts. Back up the database privately before migration; preserve the strong existing `SECRET_KEY`. Run `backend/migrate_defense.py` with the explicit intended target. Startup migrations are additive/idempotent, but a backup remains necessary.
3. Configure HTTPS origins, GEE/weather credentials, `ANALYSIS_JOBS_ENABLED=1`, real email/Auth/FCM and their required flags. Use [provider setup](IDENTITY_AND_DELIVERY_SETUP.md). Do not turn required flags off to obtain a green readiness response.
4. Deploy the matching backend/web. `/health` is process liveness; `/ready` checks schema/model and required provider configuration. Configuration checks do not contact all providers or prove delivery. Test the real services separately.
5. Smoke farmer signup/login, saved farm/offline queue, preliminary analysis and factor provenance, save/report, submit, authorized planner review, farmer activity/push and logout/session invalidation. Bootstrap the real Super Admin privately; disposable QA accounts are not the production owner.
6. Only publish/install a live release after its dependent scientific/provider/device gates are honestly accepted. Preliminary city screening remains available where compatible CAGRO NPK is unavailable; complete NPK grades must remain unavailable.

## Rollback and operations

Record the previous backend/web revision, old APK signer/version, schema backup time and write reconciliation window. Rehearse application rollback in owned staging with new writes and queued work, then forward recovery. Restoring a disposable schema alone does not establish full application rollback. Do not downgrade/delete manual or production data to make a test pass.

The prepared `.github/workflows/render-health-check.yml` requests public health about every ten minutes after publication on the default branch. It is not active merely because the file exists. Scheduled runs can be delayed. Free Render instances can still sleep/restart; the client must retain drafts and offer retry. A paid always-on service is an owner hosting choice, not an application-code guarantee.

The Windows health task depends on this PC/network. Add real owner-controlled monitoring, alert receipt and escalation contacts before declaring operations accepted. No recipient or legal/privacy contact is invented by this handover.
