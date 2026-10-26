# Web release and rollback

Use the repository root as the Vercel project root. Root `vercel.json` runs
`bash deployment/vercel_build.sh` and publishes `build/web`; the bootstrap pins
Flutter 3.41.9 when no SDK is installed. For a local build:

```powershell
$env:FLUTTER_BIN='C:/flutter/bin/flutter.bat'
python deployment/build_web.py
```

`API_BASE_URL` defaults to the existing HTTPS Render service. Public Firebase
environment values listed in `deployment/build_web.py` are passed to Flutter and
used to generate the same public `firebase-config.js`. Supply all four required
app identifiers together. Never put server/service-account credentials in these
values. For public VAPID/OAuth identifiers see `IDENTITY_AND_DELIVERY_SETUP.md`.

The build writes `build-info.json` with commit, application source fingerprint,
SDK, API origin and compiled JS hash. The source fingerprint distinguishes local
uncommitted changes from the recorded parent commit. `WEB_BUILD_ID` is also
embedded in Flutter. The built output contains its own header-only `vercel.json`
for manual static deployment. Root and built-output deployment are alternatives;
do not deploy the source's `deployment` directory as if it were the application.

Confirm `/build-info.json`, HTML and JS response headers after publication. The
former Flutter cache worker is retired specifically; the FCM worker is preserved.
Test both a new browser and a returning browser with the old cache. Version
metadata is a diagnostic, not proof of successful authenticated journeys.

`/health` means the API process/model can respond. `/ready` additionally checks
schema and required provider configuration. Real message receipt and browser
journeys remain separate checks. The scheduled health request does not promise
continuous availability or check email receipt.

Before any live schema change record the private backup timestamp, prior backend
and frontend releases, configuration owner and write-reconciliation window. On
owned staging rehearse rolling application versions back and forward with new
writes and queued work. Do not erase live users or restore a production database
to create a test pass. Hosting/backup/monitoring owner access and actual receipt
remain pending until evidence is recorded.

Configuration references: [Vercel](https://vercel.com/docs/project-configuration)
and [Flutter web release](https://docs.flutter.dev/deployment/web).
