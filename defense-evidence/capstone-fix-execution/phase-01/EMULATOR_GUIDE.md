# Close Phase 1 using the Android emulator and Chrome

Use the local workflow lab prepared for this phase. It uses a verified disposable PostgreSQL instance, a temporary schema, temporary accounts and synthetic environmental readings. The existing model and current workflow run against these test readings. This is workflow acceptance, not real soil/environmental validation. No production records are used, no email/push is sent, and no deployment is performed.

## Start the three terminals

Start an Android emulator from Android Studio Device Manager. Open three PowerShell terminals in VS Code, all in:

```powershell
cd C:\Users\jasph\Downloads\GeoSustain-mobile-update
```

Terminal 1, local test backend:

```powershell
.\.tools\python\python.exe .\backend\tests\phase01_manual_host.py
```

Leave it open. Wait for `PHASE 1 LOCAL WORKFLOW TEST - NOT PRODUCTION`. If it reports a database or startup error, stop and share that error; do not substitute a production database or edit backend/.env.

Terminal 2, farmer app on the emulator:

```powershell
.\deployment\run-phase-01-farmer.ps1
```

The script selects the running Android emulator and builds a debug test copy using `.phase01qa` as its package suffix. It does not replace the normally installed application. Its launcher label is still GeoSustain; use the copy automatically opened by `flutter run`. For multiple emulators use `-DeviceId emulator-5554`, replacing that ID with the intended emulator from `flutter devices`.

The test copy uses the emulator host alias `10.0.2.2:18001`. The launcher temporarily sets the Windows-safe `GEOSUSTAIN_PHASE01_QA` marker for the debug-only package suffix; normal release configuration is unchanged. Do not uninstall an existing application to resolve a signing error.

Terminal 3, analyst web app:

```powershell
flutter run -d chrome --no-pub --web-hostname=localhost --web-port=18002 --dart-define=API_BASE_URL=http://127.0.0.1:18001
```

Use the Chrome tab opened by this command, not the deployed website. Keep all three terminals running throughout the test.

## Disposable accounts

| Surface | Email | Password |
| --- | --- | --- |
| Emulator farmer | `phase1-farmer@example.com` | `Phase1Only!2026` |
| Chrome analyst | `phase1-analyst@example.com` | `Phase1Only!2026` |

These are deliberately public test credentials for temporary local records, never real account credentials. They are created verified, so no registration/email-code step is required. Test tokens use a fresh local signing key and cannot authenticate to production. Accounts and records disappear when Terminal 1 exits normally.

## Perform the manual checks

**A. Farmer draft.** In the emulator, sign in as the test farmer. Open My Farms, open **Phase 1 Test Farm**, choose a planting month and tap **Analyze This Farm**. Wait for the result. Expect a saved-boundary result with Draft status and the explicit synthetic-test notice. Estimated readings and missing-data limitations are allowed; the test does not require a particular recommended crop.

**B. Submit.** Tap **Submit for Analyst Review**. Expect Pending. Refresh/reopen and confirm it remains one submitted case rather than duplicating.

**C. Analyst review.** In Chrome, sign in as the test analyst. Open Review Inbox, select that case, inspect its saved boundary/evidence, add `Phase 1 manual test - reviewed saved evidence`, complete the checklist and verify it. Expect a saved decision. Check the case map opens submitted cases and no independent Analyze Area / Select an area control is offered. A direct `/operator/analyze` route should show a review-only notice.

**D. Farmer result.** Return to the emulator, refresh/reopen the submitted analysis. Expect Verified/Approved and exactly the note entered in C. The saved analysis boundary and values should remain the submitted snapshot.

**E. Preliminary inspection.** Use the farmer's map/analysis tool to analyze a point within Panabo, near the seeded farm. Expect the preliminary inspection notice and no formal submit action. This point must not appear as a newly submitted analyst case.

**F. Stale boundary.** Produce another analysis of the saved test farm and leave it as Draft. Record its analysis ID. Edit/save the farm boundary, then reopen that older draft and attempt submission. Expect a message requiring analysis of the current saved boundary; it must not become Pending. Do not use the already verified record for this check. A new analysis of the updated farm should be eligible again.

Record an actual result for each letter. If anything fails, share its letter, the action, expected versus actual behavior and any error text. Do not mark the whole sequence passed if a step was skipped.

## Finish

Report `A-F passed` only after actually completing all six checks, or list the failed/not-run letters. These outcomes populate MANUAL_JOURNEY.md; the setup smoke test is not your manual result.

Use `q` in the Flutter terminals to stop the clients, then Ctrl+C in Terminal 1 to stop the backend and remove only its temporary schema. The fixture host refuses unexpected database targets. The production database, deployed site, real APK and original accounts are not changed by this lab.

Implementation files: `backend/tests/phase01_manual_host.py` and `deployment/run-phase-01-farmer.ps1`. Helper smoke checks cover CORS, disposable login, real-model fixture inference, submission, decision and owner-visible notes. Android/Chrome startup and the six manual UI steps still require actual execution on the owner's machine.
