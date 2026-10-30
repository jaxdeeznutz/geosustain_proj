# Phase 6 - Controlled Super Administrator records

Dependency: Phase 0 requirement inventory and the configuration/snapshot contracts defined by Phases 2-5. Nutrient dataset values are not needed to implement safe records management.

## Implementation tasks

- Reuse the existing shell and user/crop/audit pages. Add focused management of the accepted crop requirements, calendar records, environmental-source metadata, model-version records, supporting references and supported system settings.
- Identify which fields are genuinely editable, which need validation/review, and which represent an installed artifact. A database model record must not claim that an arbitrary file is deployed.
- Add migrations, ownership/role checks, typed validation, activation/version rules and audit events with actor/date/change history. Keep private credentials outside editable public metadata and reports.
- Store evidence URL/reference, crop/source scope, units, period, validity dates, method and scientific review status where relevant. Unknown crop criteria remain absent; do not populate invented thresholds.
- Wire each editable record to its intended analysis/report consumer; a settings screen that does not affect actual processing is not completion. Reject invalid ranges, incompatible units/periods and unsafe source identifiers.
- Preserve exact configuration/reference versions in new analysis snapshots. Editing a record must not retroactively change a submitted analysis or explanation.
- Keep model upload/activation constrained to validated, trusted artifacts and a documented release procedure. Do not deserialize untrusted uploads or weaken the existing RF artifact checks.

## Acceptance

Use controlled records to verify authorized create/update/activate behavior, validation and role negatives, audit history, consumer integration and old-snapshot preservation. Recheck calendar, spatial and explanation outputs affected by configuration changes. Keep migrations reversible and verify the relevant database rollback.

Complete when the actual accepted management capabilities work end to end. If a promised record is intentionally developer-maintained, record the scope decision rather than call a read-only screen full management. NPK data entry/activation stays deferred to Phase 8.
