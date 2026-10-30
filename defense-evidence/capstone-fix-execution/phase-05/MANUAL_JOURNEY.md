# Phase 5 manual journey - pending

Automated backend checks are recorded separately. No installed-device, browser
or report-preview human acceptance is recorded yet.

After `deployment/verify-phase-05.ps1` passes:

1. Stop the previous local lab backend with Ctrl+C. From the project root run
   `.tools/python/python.exe backend/tests/phase05_manual_host.py`. Keep it open.
2. Rebuild/run the isolated farmer APK with
   `deployment/run-phase-01-farmer.ps1 -BuildApk`. Use the disposable farmer
   account printed by the lab host. Open **Phase 5 Explainable AI Test Farm**
   and run a new analysis.
3. On Overview, verify **Explainable AI** is visible. Check baseline, model
   score, signed percentage-point factors and the nine recorded samples.
   Switch crop selection and alternative comparison. Open the detailed view;
   check all factors, original inputs, model/context/checksum and limitations.
4. Open a crop's details and check that the explanation names that crop and its
   saved class score. Reopen from History and confirm the same explanation.
   Older analyses without local snapshots must show unavailable rather than
   new invented factors.
5. Submit this analysis. Start the web client on localhost:18002 using backend
   127.0.0.1:18001 and the disposable analyst account printed by the host. Open
   the submitted case and compare crop, score, baseline and signed factors.
6. Open both app exports. Inspect the Explainable AI section, feature table,
   class mapping, baseline/net/score and limitations. Verify that the selected
   saved analysis and crop values match the screens. Save PDF copies for
   inspection if the system print preview is too small.

All observations in this lab are synthetic workflow fixtures. Attribution uses
the actual unchanged legacy forest; this journey does not validate agricultural
inputs, provider observations or crop success. Stop the host with Ctrl+C when
finished to clean its temporary schema.

Phase 5 remains open until automated client checks, rendered report inspection
and this farmer/analyst journey are accepted. Phase 6 has not started.
