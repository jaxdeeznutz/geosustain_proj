# Phase 4 model audit and isolated evaluation tooling

This tooling prepares reproducible comparisons of Decision Tree, SVM and Random Forest. It does not publish a model, alter the current recommendation behavior, reproduce manuscript Table 13, or establish agricultural accuracy from controlled fixtures. See the [audit](../defense-evidence/capstone-fix-execution/phase-04/AUDIT.md).

## Run the local verification

From the project root in the owner's PowerShell terminal:

```powershell
.\deployment\verify-phase-04.ps1
```

The equivalent Python entry point is:

```powershell
.\.tools\python\python.exe backend\tests\verify_phase04_tooling.py
```

The project test Python includes the required dependencies. No package install or emulator is required. The verifier runs static checks, the backend suite, a fresh artifact/data audit, a controlled comparison and a separate deterministic replay. It also executes the existing training CLI and requires its unresolved-climate refusal. It writes dated logs/results and verifies that model, feature sidecar, metadata, production CSVs and training sources are unchanged. The PowerShell wrapper was syntax checked; the agent terminal's script policy required using its Python entry point for execution.

## Two explicit input scopes

`controlled_fixture` requires `synthetic_controlled` data and `fixture_*` targets. Arbitrary synthetic numeric feature values and repeated synthetic units test the software. They are not crop observations, crop ecology ranges or replacement training records. `controlled_fixture.py` creates 360 observations in 90 declared units; one intentional duplicate links two units, leaving 89 connected independent groups.

`scientific_evaluation` requires `documented_independent_records`, source evidence, reviewed measurement compatibility and complete unit/method/period/source metadata for every feature. It calls the shared climate-period validator with the supplied documented sources. Known input units are explicit: rainfall mm over rolling 30 days, temperature C with annual-mean support, humidity % with current support, pH in water as pH, NDVI index, elevation m and slope %. Nutrient units/methods must be established by scientific source review; this tool invents no conversion. Unknown, unverified or synthetic measurement definitions are rejected in scientific mode. A declared review is a traceable input, not a software certification of its truth.

The existing `train_model.py` guard and `TRAINING_SOURCES` remain unchanged. Their unknown climate periods still block production training. Passing a controlled runner test does not satisfy that guard. Final independent scientific evaluation and production compatibility remain Phase 8 gates.

## Input contract

The JSON contract binds the exact CSV SHA-256 and supplies:

- Schema version, purpose, data basis and source statement.
- The exact ordered common features: N, P, K, temperature, humidity, ph, rainfall, ndvi, elevation, slope.
- Label column, unique observation ID column, independent-unit grouping column and its meaning.
- A unit, method, represented period and source for each feature.
- For scientific data, a compatibility review reference/reviewer/date plus compatible climate-source periods.

Observation IDs must be unique. Repeated farm/observation units must share a group. Numeric features must be present and finite; there is no silent filling, conversion or label reconstruction. All three estimators receive the same feature columns. Inputs are bounded to 20-100,000 records and 2-100 classes.

## Partitions and leakage control

Before fitting anything, connected components join records that share an independent-unit ID **or exactly identical feature vectors**. Connections are transitive, so changing an observation's nominal group does not let its duplicate cross a partition. Distinct feature vectors from one repeated unit also stay together. This does not discover all unknown dependencies; source grouping remains a scientific responsibility.

The fixed first fold of a seeded five-fold stratified grouped splitter defines the held-out set. It is not selected for the best score. Four-fold stratified grouped CV uses only the remaining training groups. Every training/validation/holdout partition must retain every class, otherwise evaluation refuses rather than silently falling back to row splitting. Actual counts and all membership are saved; approximately 20% is a design target, not a forced row count.

No synthetic GIS augmentation or resampling is performed. Class weighting is derived within each fit. SVM uses a `StandardScaler` inside its pipeline, fitted separately on each training fold and on the final outer training partition. Trees use the same unscaled features. No feature selection, tuning, preprocessing or balancing observes held-out data. Tests compare every saved scaler mean and sample count with the corresponding training rows.

This design follows the installed scikit-learn 1.8 [grouped stratification contract](https://scikit-learn.org/1.8/modules/generated/sklearn.model_selection.StratifiedGroupKFold.html) and its [training-only preprocessing guidance](https://scikit-learn.org/1.8/common_pitfalls.html). Repeatedly changing settings after looking at holdout results would invalidate independence even if the code still keeps groups separate. Temporal or geographic transfer requires a separately justified time/region holdout; ordinary grouped stratification does not establish it.

## Models and recorded evidence

The default frozen settings follow the documented comparison settings: seed 42; Decision Tree depth 14, minimum leaf 6 and split 12; SVM RBF C=10 and gamma=scale with standardization; Random Forest 500 trees, depth 14, minimum leaf 6 and split 12, sqrt feature sampling and balanced-subsample class weights. Computation uses one thread for stable replay. Configuration bounds and exact effective parameters are recorded; this is a predeclared comparison, not a hyperparameter search.

Every model records held-out accuracy, macro precision, macro recall, macro F1, weighted F1, per-class support/results, fixed-label confusion matrix, predictions keyed by observation hash and fit/prediction timing. CV retains fold metrics, prediction fingerprints, sample/group counts and descriptive mean/standard deviation. Dataset, contract, runner, split, environment and deterministic-result hashes make provenance explicit. Timings are measured wall-clock on the recorded machine and are excluded from exact replay equality; they are not universal performance claims.

The default 1,000-replicate bootstrap samples whole held-out connected groups with replacement and recalculates record-level metrics from fixed predictions. Approximate 95% percentile intervals are conditional on this fitted model and partition. They do not include retraining uncertainty or establish field validity, transferability, statistical superiority between models, or crop success. All class labels remain fixed; an absent replicate class contributes zero to macro metrics. Few independent groups can make intervals unstable. CV fold standard deviations are descriptive, not confidence intervals from independent folds. Row-level metrics are not automatically per-farm metrics.

Selection uses highest **training-only CV macro F1**, then CV accuracy; exact ties prefer Decision Tree, then SVM, then Random Forest. Holdout metrics are never used by the selection function. The controlled run's preferred model is only a tooling outcome. Any scientific choice still requires Phase 8 data acceptance. A non-RF choice also requires resolving the production loader/explanation compatibility, since current production code is RF-specific.

## Outputs and replay

New output directories must be children of `research/model-evaluation/` or `defense-evidence/capstone-fix-execution/phase-04/runs/`. Existing run directories and production paths are refused. The runner writes only JSON/CSV/Markdown evidence; it never writes pickle/model assets or calls the production publication function. Model/data bytes are checked before and after CLI execution.

Each run contains `results.json`, `splits.json`, `contract.json`, `comparison.csv`, `comparison.md` and a file-hash manifest. The comparison tables have an explicit scope banner, all five manuscript metrics and uncertainty summaries. They are formatted for review; controlled percentages must not be copied into the manuscript as agricultural results. Raw farm IDs and feature payloads are not exported in results; dataset-bound observation hashes and connected-group hashes allow replay from the original input.

To run an independent replay, provide the same dataset, contract, configuration and environment with `--reproduce path/to/original/results.json` and a **new** output directory. A mismatch in deterministic evidence fails before success output is written. Historical runs remain intact. The Phase 4 verifier does this automatically.
