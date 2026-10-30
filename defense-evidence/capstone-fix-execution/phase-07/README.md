# Phase 7 - local candidate accepted

Closed locally on 2026-10-30. This is stabilization of the demonstrated local
browser/emulator candidate, not a production release or scientific signoff.

## Candidate and results

- Source manifest: `implementation-source-hashes.json`; source commit
  `2eb82c725a2c50b64e3febfe610fe4958c11b75a` with recorded working-tree changes.
- Owner client attempt `20261030-075915-144`: offline dependencies, analyzer,
  all 266 Flutter tests and web build passed; tested source hashes match.
- All 489 backend regressions passed. Five additional real disposable SQL/API,
  queue/retry and backup/restore checks passed in `runtime-sql-restore.json`.
- Owner accepted the landscape login, restored analyst tools, farmer submission,
  analyst evidence/decision, farmer Approved return/notes, both saved reports,
  admin audit/draft record and the requested emulator/browser checks.
- `manual-acceptance.json` distinguishes screenshots from owner-reported results.
  The supplied owner screenshots are retained with hashes under `owner-screenshots`.
- Both test-generated PDFs were checked against all saved crop scores and model
  context, rendered, and visually inspected. Owner confirmed actual app PDFs were
  saved and their requested sections were present; those owner files were not
  collected for independent hashes.

The same random-forest artifact remains installed. The restored analyst analysis
endpoint changes role/workflow entry, not inference calculations. The concise
explanation and reference panels preserve the separation between model ranking
and cited growing-condition comparisons.

## Recovery and restore scope

The isolated test verifies owner isolation, immutable explanation parity,
idempotent analysis replay, recovery from persisted running-job state, explicit
retry after an injected provider failure and real `pg_dump`/`pg_restore` parity.
The existing owner-operated lab is untouched. The new schema and restore database
are removed after the check; the synthetic dump is retained in ignored `.tools`.

The nine-sample synthetic polygon request took about 3.24 seconds; queued recovery
took about 3.42 seconds and dump/restore about 1.40 seconds in this run. These are
bounded fixture observations, not production performance estimates. No worker
process was killed, live provider queried or production database accessed.

## Scope retained beyond local closure

`QA_SUBCHECK_MATRIX.csv` maps 20 scoped checks to original IDs. It does not promote
any whole row in the original 191-case checklist. `RELEASE_GATES.json` retains
intended-host, provider, physical-device and release-infrastructure gates. In
particular, earlier OFF05/outdoor GPS/native-picker limits and live Google/SMS/push
requirements are not silently closed. The genuine signup-email receipt from
2026-10-27 is credited for its original scope, without claiming a new delivery.

Phase 8 retains nutrient/source/method/criteria and final scientific validation.
Any material model/data/report change requires affected Phase 5/7 retests. Phase 9
must retain real evaluation, matching deployment, release backup and final signoff.
