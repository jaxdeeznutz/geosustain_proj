# Close Phase 1 with an Android phone and Chrome

Android Studio/emulator installation is not required for this path if the Android SDK already used to build the APK is available. Use an authorized USB connection or Android 11+ Wireless debugging. Both are physical phones to the launcher; keep the selected ADB connection active during testing.

## Optional wireless connection

Phone and PC must be on the same Wi-Fi. On the phone open Developer options -> Wireless debugging -> Pair device with pairing code. In PowerShell use the existing SDK's ADB:

```powershell
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb pair "PHONE_IP:PAIRING_PORT"
```

Replace the uppercase placeholders with the pairing dialog's address/port, then enter its code in the terminal. Do not post the code in evidence/chat. Run `flutter devices`. If the phone is not listed after pairing, return to the main Wireless debugging screen and use its connection address/port:

```powershell
& $adb connect "PHONE_IP:CONNECTION_PORT"
flutter devices
```

The pairing port and connection port can differ. Once Flutter lists the phone as connected, use the same `-Phone -BuildApk` command below; it establishes the backend's reverse port mapping through the selected ADB transport. If USB and wireless copies both appear, use `-DeviceId` with the intended ID from `flutter devices`.

Reference: [Android Developers ADB wireless setup](https://developer.android.com/tools/adb#connect-to-a-device-over-wi-fi). Actual pairing, reverse-port operation and manual UI results on the owner's phone are not claimed by these instructions.

This is the same isolated workflow lab described in EMULATOR_GUIDE.md: temporary local accounts, a verified disposable database schema and synthetic environmental readings. It does not use production farm records or send email/push. Actual phone execution and manual results remain pending until performed.

## Start the local backend

In a VS Code PowerShell terminal:

```powershell
cd C:\Users\jasph\Downloads\GeoSustain-mobile-update
.\.tools\python\python.exe .\backend\tests\phase01_manual_host.py
```

Leave it running after `PHASE 1 LOCAL WORKFLOW TEST` appears. If it reports an error, stop and share it rather than changing database targets.

## Build and install the phone test APK

Connect one Android phone by USB, unlock it, enable USB debugging and accept the authorization prompt. In a second PowerShell terminal in the project folder:

```powershell
.\deployment\run-phase-01-farmer.ps1 -Phone -BuildApk
```

The script selects the authorized phone, forwards port 18001 through ADB, builds the debug APK, verifies the isolated `.phase01qa` package before installation, and installs/opens it. The normal app is not replaced. Keep USB or Wireless debugging connected for the entire local test. With multiple phones/transports pass `-DeviceId` using the desired ID from `flutter devices`.

The generated APK is:

```text
C:\Users\jasph\Downloads\GeoSustain-mobile-update\build\phase-01\geosustain-phase01-debug.apk
```

This path is populated only after the build succeeds. The script does not claim that the APK already exists. This debug test APK uses the USB-forwarded local backend; the existing release APK's public API address is a different test context.

## Run the analyst web app

In a third terminal in the project folder:

```powershell
flutter run -d chrome --no-pub --web-hostname=localhost --web-port=18002 --dart-define=API_BASE_URL=http://127.0.0.1:18001
```

Use the app and Chrome tab opened by these commands. Keep the local backend, Chrome session and USB connection available during the journey.

## Accounts and checks

- Phone farmer: `phase1-farmer@example.com`
- Chrome analyst: `phase1-analyst@example.com`
- Disposable local password for both: `Phase1Only!2026`

Perform checks A-F in EMULATOR_GUIDE.md, using the phone wherever it says emulator: analyze **Phase 1 Test Farm** into a draft; submit to Pending; review/add notes/verify as analyst; confirm the same status/notes as farmer; confirm preliminary point submission is unavailable; confirm a draft with an outdated farm boundary cannot be submitted. Analyst independent analysis should remain unavailable.

Report A-F passed only after actually completing all checks, or list the failed/not-run letters and the observed errors. The automated passes and local lab smoke test are not a manual phone result.

After testing, stop Chrome's Flutter session with `q`, stop the test backend with Ctrl+C, and disconnect USB. Its temporary records are removed on normal backend shutdown. No deployment, production account/farm change, release signing change or NPK dataset validation is performed by this guide.
