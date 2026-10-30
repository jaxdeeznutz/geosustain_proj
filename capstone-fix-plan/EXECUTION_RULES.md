# Execution rules

## Preserve the accepted scope

1. Use the signed objectives, functional requirements and limitations as the baseline. Maintain a requirement-to-feature-to-test crosswalk; distinguish supplemental revised-outline requirements.
2. Keep changes focused. Retain the current design, authentication/verification behavior, farm storage, ownership safeguards, model scores and historical analyses unless a phase specifically requires a supported change.
3. The analyst's assessed workflow is farmer-submission review. The recently added independent analysis is a scope extension; gate it from the assessed workflow unless approved as an extension. Do not erase its existing records.
4. A formal farmer submission must refer to an owned, saved, valid farm polygon and the analyzed boundary version. A point inspection is not a formal parcel result. Historical records remain readable with their original scope and limitations.

## Defer nutrient-dependent work

5. Carry out substantive NPK integration in Phase 8. Preserve estimated values, provenance and Not assessed statuses in earlier phases. Do not re-enable CAGRO, require CAGRO matching, or substitute historical locality data for a field measurement.
6. Missing dataset access is a precise dependency, not a reason to halt seasonal, spatial, workflow, UI, tooling or documentation work that can proceed independently.
7. Never remove a training-data guard just to get a model build. Resolve actual climate periods, nutrient units, dataset provenance and leakage before publishing replacement artifacts.

## Make results reproducible and honest

8. Store sources, represented dates/periods, units, spatial resolution, processing methods, quality, selected month, model/configuration versions and analysis scope with new snapshots. Do not recompute historical decisions from today's rules.
9. Keep four concepts distinct: model ranking, local model attribution, documented environmental comparisons, and application heuristic checks. A green factor is not proof of crop success or dataset completeness.
10. No-data, provider failure, unknown land cover and incompatible units/periods need explicit states. A warning must not become a verified scientific claim. Preserve known water/built-up blocking behavior unless separately justified.
11. Prepare migrations and rollback for schema changes; use controlled data for database/security checks. Preserve existing QA IDs and failed-test history.

## Verify the actual change

12. Use focused, meaningful tests for changed behavior. Run relevant backend/Flutter checks, then required broader gates before freezing a candidate. Do not add tests solely to mirror a trivial implementation.
13. Distinguish code completion, local test results, successful compilation, deployment, installed device behavior, provider receipt and human acceptance. A historical PASS belongs to its original candidate and test scope.
14. Do not treat an SDK/provider/device limitation as a passed check. Record the exact pending condition and continue independent work.
15. Every execution record should identify the source revision plus uncommitted changes, client/backend versions, test or command, actual result, fixture/provider basis, and remaining limits. Omit secrets, codes and identifying farm payloads.
16. The plan itself grants no new external-message, production-data modification or publication permission. Use authorization already supplied in the session for the specific action; ask only for a genuinely missing decision or access.
17. Give concise progress updates. Do not repeatedly request approval for routine reversible work already within the agreed phase.

## Phase closure

The owner explicitly requires the issues assigned to each phase to be solved and verified before advancing. Do not skip a failed check, carry an unresolved issue forward as if complete, or begin the next phase while this phase's required acceptance is pending. Separate later-phase scope from the current phase's gates.

Update the tracker and record evidence after each phase. `COMPLETE` means all of its stated gates pass; a missing scientific, provider, device or human gate remains visible. Carry forward affected retests after model, nutrient, schema or export changes. Do not change the evaluation candidate silently.
