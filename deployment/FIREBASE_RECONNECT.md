# Reconnect the existing Firebase project

The owner supplied the public Web configuration for `geosustain-4c722` from
Firebase Console. The console screenshots show Google enabled and both Android
and Web app registrations. This is configuration evidence, not a successful
live sign-in test.

`firebase-web.public.json` contains only public client identifiers, transcribed
from the supplied Web configuration. It contains no service-account credential.
The app already reads these names through `FirebaseRuntime`; no npm install or
replacement Firebase project is needed. Storage and Analytics identifiers are
not needed for the current authentication integration.

## Local Web preview

In the terminal used to start the backend, set this before starting it with
the usual command:

```powershell
$env:FIREBASE_AUTH_PROJECT_ID = 'geosustain-4c722'
```

A running process will not pick up a new terminal environment automatically.
The disposable manual test host resets its synthetic records on restart; do
not restart it solely to apply configuration without accounting for that reset.
That lab also disables external backend HTTP and delivery: use an isolated
backend with real Firebase proof verification, or the updated hosted backend,
for live Google acceptance. A mocked lab proof is not live acceptance.

From the repository root, start the Flutter client with the saved public config:

```powershell
flutter run -d chrome --no-pub --web-hostname=localhost --web-port=18002 --dart-define-from-file=deployment/firebase-web.public.json --dart-define=API_BASE_URL=http://127.0.0.1:18001 --dart-define=WEB_BUILD_ID=firebase-reconnect-20261103
```

In Firebase Authentication Settings, check Authorized domains and add
`localhost` if absent. Add the actual production Web hostname for deployment.

## Hosted build

`deployment/build_web.py` now uses `firebase-web.public.json` automatically when
the Web host supplies no core Firebase environment configuration. A complete
set of host environment values overrides the file; partial core overrides fail
instead of silently mixing projects. Optional OAuth/VAPID host values are
preserved. Set backend
`FIREBASE_AUTH_PROJECT_ID=geosustain-4c722` on the matching backend deployment.
This configures the next Web build, not an already deployed client or Render's
backend environment.

Deploy matching backend/client versions for the Google password setup flow.
Passwords created by that flow belong to GeoSustain's backend. It does not
create a Firebase Email/Password credential. Brevo email flows remain separate.

## Android public configuration saved

The owner downloaded `C:\Users\jasph\Downloads\google-services.json`. Its two
client entries include the current `com.example.geosustain_clean_arranged`
package and the older `com.example.geosustain` package. Only the current
package's identifiers were extracted to `firebase-android.public.json`.
Its Web OAuth client ID comes from the type-3 OAuth entry in the downloaded
file. The Android API key differs from the Web key supplied in the screenshot;
the two platform configuration files intentionally preserve their own keys.

`FirebaseRuntime` already initializes Firebase with explicit options and
`FirebaseIdentity` passes the Web OAuth client ID as `serverClientId`.
The downloaded file is used as the configuration source; no Gradle plugin or
native resource registration is required for this explicit Google login path.
See the [plugin integration documentation](https://pub.dev/packages/google_sign_in_android).
This does not certify background FCM delivery.

### Add the debug signing fingerprints

The initial downloads contained no Android type-1 OAuth entries. The later
owner download `C:\Users\jasph\Downloads\google-services (3).json` now includes
an Android OAuth client for `com.example.geosustain_clean_arranged`, with SHA-1
`5d13c293b7830253a8c38c00685fb8bbcec6fb49`. This exactly matches the debug
certificate read from `C:\Users\jasph\.android\debug.keystore`.

The saved Android project ID, app ID, API key and Web OAuth client ID all match
this latest download; the Flutter public configuration needs no value changes.
The downloaded OAuth entry confirms SHA-1 registration, not live sign-in or
the console's SHA-256 row. The local certificate values are:

```text
SHA-1:   5D:13:C2:93:B7:83:02:53:A8:C3:8C:00:68:5F:B8:BB:CE:C6:FB:49
SHA-256: 08:7E:E6:E8:49:BF:B1:AE:D8:A9:B1:F0:10:DD:3E:34:4D:71:C7:08:1B:B5:D2:BC:7A:98:E9:A2:B9:FD:68:08
```

These are public certificate fingerprints, not the signing private key. Use
them for debug builds signed with this computer's debug key only. Release
signing, Play App Signing and separate QA package IDs need their own matching
registration. Do not use the phase-01 runner: it adds `.phase01qa`, which this
downloaded Firebase configuration does not register.

For any other signing key or package, register its corresponding fingerprints
and check a fresh download. The local Flutter files do not update Firebase's
remote signing registration automatically.

### Run the configured Android client

Once the matching hosted backend version is deployed and its Firebase project
environment is configured, choose an Android device from `flutter devices`:

```powershell
flutter run -d <android-device-id> --no-pub --dart-define-from-file=deployment/firebase-android.public.json --dart-define=API_BASE_URL=https://geosustain.onrender.com
```

Replace `<android-device-id>` with its actual ID. Use the normal package,
without a QA application ID suffix. A Google Play capable emulator or physical
device is required. This command has not been run by the agent. No app was
installed, backend restarted, cloud setting changed or release deployed.

The normal package's debug SHA-1 registration is confirmed by the latest
download. Matching backend/client deployment, backend project configuration,
live Google acceptance, release signing registration and FCM/SMS configuration
remain separate pending steps.

Official references: [Flutter Google authentication](https://firebase.google.com/docs/auth/flutter/federated-auth),
[Firebase Web Google authentication](https://firebase.google.com/docs/auth/web/google-signin).
