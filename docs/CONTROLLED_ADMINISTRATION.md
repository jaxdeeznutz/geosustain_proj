# Controlled administration

The existing Super Administrator portal retains users, analysis monitoring,
crop availability and audit pages. **Crop & Season Settings → Controlled
reference records** adds six record categories. No record is seeded as accepted
scientific evidence. Missing criteria stay absent until a reviewed record is
explicitly activated.

| Category | Editable data | Actual consumer |
| --- | --- | --- |
| Crop requirements | Approved crop, supported environmental factor, preferred/absolute bounds, fixed compatible unit and period | New analysis factor comparisons and their saved source/range evidence. Model probabilities, ranks and local attribution are unchanged. Nutrient criteria are unsupported. |
| Planting calendars | Approved crop and unique calendar months | New selected-month seasonal calendar evidence; historical climate and model scores stay separate. |
| Environmental sources | Evidence and methods for an installed allowlisted layer/source/unit/period | Saved raster source reference, layer detail text and reports. Source metadata cannot replace observations or direct a request to another provider. |
| Model version records | SHA-256 plus evidence/review/validity metadata | New analysis model reference, only when it matches the trusted model actually loaded by the process. |
| Supporting references | Public citation and approved crop or analysis scope | Saved analysis reference details and both reports. |
| Analysis settings | Maximum parcel samples: 1, 5 or 9 | Actual polygon sample selection before inference. New class scores may change because different samples were evaluated; every explanation uses those same actual samples. |

Each record also stores its title, Panabo City scope, public HTTPS evidence URL,
source section/reference, method/limitations, validity dates, review status and
review note. Credentials, arbitrary provider identifiers, model file uploads,
nutrient datasets and unsupported settings are rejected. A reference URL is
public metadata; the server does not fetch or execute it.

## Revisions, review and activation

Saving creates an immutable revision. It does not activate the revision or
replace the current active pointer. Changes use an expected revision number;
stale edits return HTTP 409. Activation/deactivation uses a separate generation
number and a database transaction lock. Concurrent changes have one winner;
stale activation returns 409. Only reviewed records inside their validity dates
can activate. Expired records are excluded from new analyses; earlier saved
snapshots remain readable.

The same Super Administrator may perform review and activation; no independent
scientific reviewer or external approval is implied by a UI status. The owner
must use the project review procedure before activating real agronomic records.
Local manual test records are explicitly synthetic workflow evidence.

To undo a configuration change, reactivate an earlier reviewed, currently valid
revision with the current generation. Deactivation restores the built-in default
for that specific slot. The administrator can inspect every revision and its
author/date; the audit page retains revision and before/after activation IDs.
Audit writes are atomic with mutations: audit failure rolls back the change.

The existing crop activation table stays in place. Disabling every crop now
preserves the empty filter, rather than enabling the whole catalog. New formal
model inference then reports no enabled model-supported crop. Reactivating one
crop affects only future results. Crop metadata edits have bounded typed fields
and before/after public values in the audit event. Legacy display metadata are
administrative inventory; scientific requirements and source citations use the
new versioned records. This phase does not turn legacy yield/growth text into
validated agronomic criteria.

## Saved analysis contract

An analysis reads active record pointers and immutable revision content in one
SQL statement, before sampling. It stores the exact public documents, record IDs,
revision/generation numbers, content checksums, capture time, default requirement
version, sample limit and enabled crop filter in `configuration_snapshot`.
Reviewed requirements alter reference factor evidence only. Calendar and source
metadata are saved separately from measurements and local model contributions.

The farmer and analyst use the saved reference details, selected-month calendar
and raster source metadata. Both report builders export the original reference
versions and citations. Reopening a historical or submitted analysis never
loads current records to replace its snapshot. Existing analyses without these
records remain unchanged.

## Model installation scope decision

**Installing or uploading a model remains developer-maintained.** This is an
explicit boundary, not a claim that a read-only identity is full deployment
management. Administrators can create/revise/activate model identity metadata;
activation only succeeds for the artifact already validated and loaded by the
existing trusted loader. Database text cannot cause pickle deserialization or
make an arbitrary file appear deployed. Installing a replacement requires the
documented trusted release procedure, artifact/feature/class/metadata checks,
retraining guard resolution, scientific review and affected integration tests.
Phase 8 owns nutrient and scientific changes; Phase 9 owns final release.

## Migration and rollback

`database.init_db()` idempotently creates `controlled_record_revisions` and
`controlled_record_activations` after users/audit tables exist. No existing
analysis JSON, model, crop dataset or legacy table is rewritten. Back up and use
the normal staged deployment procedure before any production migration.

The `controlled_records.rollback(cursor)` helper removes empty new tables in a
transaction. If revisions exist, it refuses destructive rollback. Roll back the
application candidate while retaining those evidence tables and the existing
analysis JSON. A used configuration can be rolled back through an earlier
reviewed activation pointer; do not delete its history. The disposable SQL/API
verification checks empty-table rollback, idempotent remigration, used-table
refusal, concurrent activation, stale writes and audit-failure rollback.

## Local verification

- `deployment/verify-phase-06.ps1`: dependencies, analyzer, full Flutter tests,
  real report builders and web build; no deployment is performed.
- `.tools/python/python.exe backend/tests/phase06_administration_integration.py`:
  real SQL/API in the verified temporary PostgreSQL schema, actual unchanged
  forest, synthetic observations and controlled reference fixtures.
- `.tools/python/python.exe backend/tests/phase06_manual_host.py`: local manual
  lab with a disposable Super Administrator, farmer and analyst. External
  backend HTTP, email and push are disabled. Ctrl+C removes only its lab schema.

General wording/layout refinements requested during Phase 5 remain deferred to
Phase 7; this phase adds only the administration controls and their necessary
saved evidence views.
