# Phase 6 manual journey - pending

The backend/SQL checks use synthetic data and the actual unchanged forest. Human
acceptance remains separate. Keep UI/copy refinements deferred to Phase 7.

After `deployment/verify-phase-06.ps1` passes, stop the Phase 5 lab with Ctrl+C
and start `.tools/python/python.exe backend/tests/phase06_manual_host.py`.
Keep that terminal open. Run the web client on localhost:18002 against backend
127.0.0.1:18001 and rebuild the isolated Android test copy. Log in again after
changing lab hosts because each lab uses a different temporary signing key.

1. Log into the web portal as `phase6-admin@example.com` with the disposable
   `Phase1Only!2026` password. Open **Crop & Season Settings** and find
   **Controlled reference records**.
2. Create a **Planting calendars** record for Rice. Use months `2, 8`, title
   `Phase 6 workflow calendar`, evidence URL `https://example.org/phase6-test`,
   reference `Synthetic workflow fixture only`, method `Software test only;
   not planting advice`, validity from today through `2030-12-31`, status
   **Reviewed**, and review note `Reviewed only for this local software test`.
   The example URL is public placeholder metadata and is never fetched; do not
   use this as a real scientific record.
3. Confirm the new revision is inactive. Open its details, then explicitly
   activate it. Confirm its reviewed status and validity are visible.
4. On Android, use the existing local farmer account and **Phase 5 Explainable
   AI Test Farm**. Select February and run a new analysis. Check seasonal
   calendar evidence says Rice's selected month is listed. Expand **Saved
   reference versions** and confirm the calendar revision and fixture source.
   Explainable AI must still match the actual saved model score.
5. Back in admin, create revision 2 with months `8` and activate it. Reopen the
   earlier farmer analysis from History: it must retain revision 1 and February
   listed. A new February analysis must use revision 2 and say not listed.
6. Inspect **Audit & System** for the revision and activation events. Open a
   change to check actor/date and old/new record pointers.
7. Open both farmer and submitted analyst report exports. Confirm **Saved
   reference versions** contains the same revision/citation as the selected
   saved analysis, alongside its unchanged explanation evidence.

The other categories, role negatives, range/unit/source/model validation,
concurrent changes, actual sampling controls, migration rollback and audit
failure are covered by the separate automated SQL/API and client checks.
No production, provider or agronomic approval is claimed. Stop the lab with
Ctrl+C when finished to remove its temporary schema.
