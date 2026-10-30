# Phase 4 - model evidence and evaluation tooling

State: **COMPLETE - LOCAL AUDIT AND TOOLING VERIFIED**, 29 October 2026. [Closure record](closure.json). Phase 5 is NOT STARTED. This completes the Phase 4 scope allowed before new NPK data; final scientific/model acceptance remains explicitly in Phase 8.

## Reviewable results

- [Artifact/data/Table 13 audit](AUDIT.md): exact local artifact identity, three class-set contracts, dataset identities/duplicates, reported metric trace and scientific/live dependencies.
- [Runner contract and commands](../../../docs/MODEL_EVALUATION_TOOLING.md): grouped independent partitions, training-only preprocessing, metrics, uncertainty, replay and nonpublishing outputs.
- [Verified controlled comparison table](runs/verify-20261029-130617-365079/evaluation/comparison.md): all five metrics and uncertainty. **Synthetic software fixture only; never substitute these numbers for manuscript Table 13 or agricultural accuracy.**
- [Machine-readable run](runs/verify-20261029-130617-365079/evaluation/results.json), [split membership](runs/verify-20261029-130617-365079/evaluation/splits.json), and [independent replay](runs/verify-20261029-130617-365079/replay/results.json).
- [Final verifier record](tooling-validation.json): seven checks passed, including **421 backend tests** (16 new evaluation tests), static checks, audit, comparison, replay and actual legacy training refusal. Four existing warnings are retained in the log.

## Provenance and integrity

`baseline-source-hashes.json` identifies the entry artifact, CSVs and protected sources. The final verification confirmed all these bytes are unchanged, along with all frozen Phase 3 candidate sources. Production model SHA-256 remains `6dee915ad58e55e376bcfb5a74ecee9db086491cf5fe29a1b3149f5b45be9278`. No model/data replacement, deployment or remote mutation occurred.

`audit/` retains the read-only manuscript page image/text and initial bounded health probe result. The original manuscript hash matches the Phase 0 document identity. The health probe could not reach the server; deployed runtime identity remains unverified. Final verifier attempts each have a fresh audit and logs. Initial controlled runs/replays and the initial 15-test run are retained alongside the final 16-test/421-backend-test candidate.

The PowerShell wrapper was syntax checked; agent execution policy blocked invoking it directly. Its exact Python verification entry point completed successfully. The owner terminal may use `.\deployment\verify-phase-04.ps1`; the equivalent command is `.\.tools\python\python.exe backend\tests\verify_phase04_tooling.py`. No emulator/client rebuild is needed for this isolated backend tooling phase.

## Scientific gates remain visible

The manuscript Table 13 values are claims located in the supplied PDF, with original experiment linkage unresolved. Existing climate periods, nutrient methods/units, row-level independent outcome lineage and class/catalog compatibility need scientific review. The original training guard remains in force. The audit's gate register assigns the remaining data/selection work to Phase 8, final manuscript reconciliation to Phase 9 and actual runtime parity to integration/release checks. This closure does not close those later gates.

No user acceptance of newly trained production behavior is implied: this phase changed no production behavior and published no model. Its acceptance is the locally verified audit/tooling contract specified in the plan.
