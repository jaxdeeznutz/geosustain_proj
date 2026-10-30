# Phase 2 — seasonal assessment

State: **COMPLETE - OWNER ACCEPTED 2026-10-29**. Analyzer, all 226 Flutter tests, web build, 383 backend tests and isolated SQL/API checks passed. Owner screenshots and confirmations cover complete/partial/unavailable monthly states, historical preservation, unchanged model outputs, farmer/analyst parity and both exported reports. See MANUAL_JOURNEY.md and closure.json for scoped evidence and limitations. This phase has not been pushed or deployed.

Implemented: visible planting-month selection on farmer analysis entry points; additive `seasonal-context-v1` snapshots for modern and legacy paths; documented monthly units, periods, baseline years, valid counts and explicit provider/calendar unavailability; shared farmer/analyst/report snapshot text. Month changes do not affect forest scores, crop order, annual factor grades, NPK or CAGRO policy. See [the contract](../../../docs/SEASONAL_ASSESSMENT.md).

## Checks

| Check | Outcome |
| --- | --- |
| Full backend suite | 383 passed, four existing dependency/deprecation warnings; backend-tests.log |
| Monthly units, leap Februaries, missing/partial observations, cache and rank invariance | Included in backend suite; 10 new tests |
| Actual isolated SQL/API snapshot persistence | Passed: two months, farmer history/detail, analyst case, provider-failure state and historical snapshot immutability; sql-api-results.json |
| Phase 1 SQL/API protections after Phase 2 changes | Passed: concurrency, scope, roles, corrected revisions, stale geometry, historical preservation and farmer feedback; phase01-regression.log |
| Ruff F, PowerShell parser, Dart parse/format, standalone shared report-text smoke and whitespace | Passed; not a substitute for Flutter analysis or PDF visual verification |
| Bounded public provider probe | Unavailable state returned; provider-check.json. No live monthly values or real-provider success claimed |
| Flutter analyzer, full tests and web compilation | PASS: final owner rerun recorded 2026-10-29T06:28:40Z; analyzer, all 226 tests and web compilation exit 0. Includes the expansion-state regression. Earlier failed and successful attempts remain retained. |
| Owner emulator/browser/report journey on new source | PASS / OWNER ACCEPTED: detailed monthly states, February reopen, matching analyst snapshot and readable farmer/analyst reports; MANUAL_JOURNEY.md |

The SQL/API harness uses the verified disposable local PostgreSQL data directory and drops only its fresh random schema. Model values and monthly climate are controlled fixtures. Early harness-only errors (an incorrect singular route and missing response-envelope extraction) were corrected before the passing run; these were not product failures.

`backend/tests/phase02_manual_host.py` prepares clearly labelled monthly fixtures (February/August complete, May unavailable, November partial) on the same isolated lab. It does not use real NASA observations. The existing package-checked Phase 1 debug launcher can be reused to install the new client source for this local test.

Versioned JSON snapshots are additive and need no migration. Baseline source copies and hashes preserve the prior working tree; unrelated QA work is untouched. Phase 3 has not started.
