# Executed validation

27 October 2026. Application source candidate: `5ba2aca7146184337e1724e6c32c0e31d6fa2de0`. Later documentation commits do not change the application candidate. Logs retain warnings and the Windows shell's stderr wrappers where present; the final tool exit and test summary determine each result.

| Scope | Actual result | Artifact |
| --- | --- | --- |
| Backend regression suite | 289 passed, 4 deprecation warnings | `backend-tests.txt` |
| Real PostgreSQL/FastAPI workflow | PASS; own disposable schema removed; 500 extra synthetic cases | `sql-workflow.txt` |
| Broad Flutter regression at 069ef34 | 194 passed | `flutter-tests.txt` |
| Focused Flutter checks at final 5ba2aca | 20 passed, including the final history metadata fix | `final-focused-tests.txt` |
| Final Flutter static analysis | No issues found | `flutter-analysis.txt` |
| New backend/helper Ruff F checks | All checks passed | `ruff.txt` |
| Deployment helper tests | 3 passed | `deployment-tests.txt` |
| Final production web build | Successful release build; HTTPS Render API origin | `production-compilation.txt`, `production-build-info.json` |
| Final local web build | Successful profile build, used for actual localhost browser checks | Local compiled artifact on D:; `BROWSER_CHECKS.md` |
| Case and planning PDFs | Actual exporter; all 4 case pages and 1 planning page rendered and inspected | `synthetic-*.pdf`, page PNGs |
| Native browser observations | Local direct route, saved case, Back/Forward/reload, separate map/inbox filtering | `BROWSER_CHECKS.md` and browser text artifacts |
| Scientific/data hold | Existing science definitions and held Git blobs unchanged | `SOURCE_SCOPE.json` |

The 20 focused tests overlap the broad suite and are not an additional independent 20-test count. The broad suite predates the final small navigation change; final focused checks and real browser observations cover that change. No test is evidence of live email/SMS/OAuth/push receipt, inference accuracy or owner/adviser acceptance.

The local production manifest records build `5ba2aca71461-df58784d8c19`, source fingerprint `df58784d8c19d8069dc90cfe5b2788787bac9eaac3bf579300802770eb665fb6` and compiled JavaScript SHA-256 `42788060656ac29e6e2298ca36c728b15f8a0959e2d939a6d8791f7c1ef5fbf5`. A hosted build may have different artifact hashes; its identity must be checked separately in `RELEASE.json`.

Remaining acceptance: hosted authenticated analyst/farmer journeys; full browser and screen-reader matrix; browser zoom and physical print/download behavior; configured provider receipt; independent review; deferred physical mobile retest. NPK, soil pH, additional datasets and retraining remain on hold.
