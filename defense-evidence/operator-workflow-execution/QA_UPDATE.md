# Workflow QA extension

These checks supplement the original 191-row QA register; they do not replace or silently promote its rows. Original totals remain 69 PASS, 83 PARTIAL, 3 FAIL, 17 NEEDS-MANUAL and 19 N/A.

| Check | Local outcome | Evidence / remaining scope |
| --- | --- | --- |
| OPS-01 Role and owner restrictions | PASS | Real authenticated SQL/API tests deny foreign owner and farmer reviewer access |
| OPS-02 Required decision explanation/checklist | PASS | Rejection without explanation and acceptance without strict checklist rejected by API |
| OPS-03 Information request and linked correction | PASS for API; UI acceptance separate | New same-farm analysis resubmits into the same case; old revision retained |
| OPS-04 Concurrent/stale reviewer conflict | PASS | Second stale decision gets 409; client keeps notes and requires reload |
| OPS-05 Recorded versus current geometry | PASS | Rename alone preserves coordinate match; edited coordinates do not |
| OPS-06 Bounded filtering and distinct-farm statistics | PASS | 500 additional synthetic cases; 20-row inbox; no snapshots/emails in list; repeated cases counted as one farm |
| OPS-07 Missing/zero and equal measured values | PASS | Zero retained; missing unknown; equal measurements use neutral blue |
| OPS-08 Narrow filter layout | PASS for widget targets | 390/768-pixel layouts have no overflow; actual browser zoom separate |
| OPS-09 Browser route/back/forward/reload | PASS locally | Direct inbox, stable case, Back, Forward and refresh observed in Brave on application commit 5ba2aca; hosted and other-browser acceptance separate |
| OPS-10 Case/planning exports | PASS for generated PDFs | Actual Dart exports rendered and inspected; physical print/download UI separate |
| OPS-11 Follow-up ownership and reminder deduplication | PASS | Assigned actor only can complete; repeated activity refresh creates one due event |
| OPS-12 Held soil/data contract | PASS for unchanged source | `SOURCE_SCOPE.json`; existing scientific definitions and data blobs unchanged |
| OPS-13 Live provider receipt / adviser sign-off | PENDING_EXTERNAL | No Firebase project/sender/provider/scientific approval supplied; not inferred from software tests |
| OPS-14 Deferred physical mobile retest | NEEDS_MANUAL | Shared activity/status components changed; web checks do not establish mobile acceptance |

See `BROWSER_CHECKS.md` and `RELEASE.json` for browser and publication milestones.
