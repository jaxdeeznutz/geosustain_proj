# Validation scope

## Database and API

`backend/tests/operator_workflow_integration.py` creates an isolated schema only after checking the marked local PostgreSQL target. It runs the idempotent migration twice, creates synthetic owner/foreign-owner/reviewer accounts, and exercises real authenticated API requests and commits. The schema is removed afterward.

Covered: role denial, owner-only farmer response, mandatory rejection explanation, strict acceptance checklist, request-information -> corrected same-farm analysis -> linked resubmission -> accept, stale second reviewer conflict, preservation of the old revision, rename versus changed geometry, assigned task ownership, due reminder deduplication, bounded projection of 500 additional cases, search no-match, workload filters, map ordering, finite bounds and one distinct farm instead of 501 repeated farms. Existing sessions are migrated without changing their result snapshots.

The regular backend suite and Ruff F checks are logged separately. Deprecation warnings are retained in the test log; they are not test failures.

## Client and PDF

Automated tests cover independent query/filter generations, discarded stale responses, neutral equal-valued measurement scales, missing versus zero, immediate review loading, cancellation without a write, notes retained on a conflict, server-page limits, 390/768-pixel inbox reflow and direct/hash URL decoding. Existing shared application regressions are also run.

Case and planning PDF fixtures use the actual Dart exporter, embedded Unicode fonts, long explanations and multiple pages. Every rendered page must be inspected. Exports show unavailable values instead of invented zeros. A case report references its saved evidence and timeline; it does not substitute for the separate full analysis report.

## Browser and delivery

Actual navigation, reload, focus, zoom, map operation and print-dialog behavior require separate observations in `BROWSER_CHECKS.md`. Widget tests do not establish those outcomes. Public release fingerprint/health/readiness checks are separate from authenticated journeys.

No local fixture establishes live email/SMS/OAuth/push receipt, inference accuracy, scientific validation, complete mobile compatibility, staging rollback or human sign-off. Those remain explicit external/manual gates.
