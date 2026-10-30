# Phase 8 - NPK datasets and final scientific validation

Position: second-to-last phase, as requested. Dependencies: Phase 4 audit/tooling, the current analysis/reference contracts, and actual defensible data or an explicitly accepted limited-proxy study scope. Dataset availability is currently unresolved.

## Before the data arrive

Keep estimated N/P/K values displayed with source/quality labels and Not assessed grades. Keep CAGRO disabled. Prepare the acquisition checklist and ingestion contract without inventing dataset values. Continue earlier phases and Phase 9 preparation where independent.

## Dataset acquisition checklist

Obtain source/provider and licence, acquisition date, locality/farm association, coordinates or coverage geometry and resolution, sample date, soil depth, analytical/estimation method, unit definitions, nitrogen form, phosphorus/potassium extraction basis, uncertainty/quality, missing-value rules and suitable use limitations. Historical locality samples are not automatically current parcel observations. Record qualified agricultural review where required for interpretation.

## Implementation tasks when evidence is available

- Audit and ingest immutable source records with checksums and provenance. Validate units, methods, ranges and geometry; flag duplicates and missing information rather than guessing.
- Keep measured/local historical observations, remote modeled soil layers and estimated model input proxies as separate layers. Identify which can support display, reference grading or model inference; these are different decisions.
- Define spatial/temporal association and coverage honestly. A new reference overlay must not reintroduce the previous citywide CAGRO matching block for independent environmental analysis.
- Grade a nutrient only if its observation and crop requirement share a defensible unit/method/depth/period basis. Dataset availability alone is insufficient. Preserve Not assessed for incompatible or unsupported factors.
- If actual inference units/features change, resolve both nutrient and climate training contracts, update the approved dataset and run Phase 4's isolated comparisons. Do not feed new physical-unit values into an incompatible legacy model.
- Select/publish a production artifact only after its evaluation and compatibility checks pass. Preserve model/dataset/feature/configuration hashes, exact metrics, class support and limitations; update the manuscript's model table from real evidence.
- Rerun Phase 5 attribution validation against any changed artifact and Phase 7 checks affected by new display, criteria, model or reporting behavior. Test mixed coverage, missing values and old saved results.

## Acceptance

Record data ownership/access, source coverage, supported methods, any qualified review and every unsupported nutrient claim. Verify no fabricated conversions or field precision, no automatic CAGRO substitution, consistent saved/exported values and unchanged historical snapshots. Where a final model is replaced, include reproducibility, holdout leakage checks, class/feature compatibility and explanation reconstruction evidence.

If data still have not arrived, mark the dataset-dependent work `PENDING_EXTERNAL`. Do not stop unrelated preparation or declare scientific closure. Because the signed scope permits explicit proxies, a qualified/adviser-approved limited-proxy conclusion may be possible; document that actual decision and remaining limitations. Do not present such a decision as obtained when it has not been obtained, and do not invent a requirement that every nutrient must become assessed.

## Completion boundary

Close this phase only for an evidenced dataset/method/model outcome or an actually accepted limited scope with clearly recorded open data limitations. Final release/evaluation wording in Phase 9 must reflect that outcome. A future dataset requiring a material model change creates a new candidate and affected retest obligation.
