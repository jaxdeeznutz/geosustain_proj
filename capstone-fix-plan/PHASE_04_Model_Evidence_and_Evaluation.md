# Phase 4 - Model evidence and evaluation tooling

Dependency: Phase 0; use current workflow/measurement contracts from Phases 1-3. New NPK data are not required for the audit and tooling. Some final experiments may remain pending until Phase 8.

## Work that can be completed now

- Inventory the exact deployed model hash, classes, feature order, dependency versions and available training records. Trace manuscript Table 13 to its original experiment files; record missing evidence rather than recreating the reported percentages from memory.
- Document synthetic GIS/local crop rows, sampling/resampling order, nutrient units, climate periods, supported classes and leakage risks. Identify independent real records and define grouping where repeated farms/observations must stay in one partition.
- Prepare an isolated evaluation runner for Decision Tree, SVM and Random Forest using the same independent splits and common compatible feature definitions. Fit preprocessing and any augmentation/resampling inside training partitions/folds only. Document justified model-specific scaling.
- Capture dataset/split hashes, seeds, hyperparameters, class support, accuracy, macro precision/recall/F1, weighted F1, per-class results and confusion matrices. Include appropriately designed cross-validation and training/prediction timing; distinguish supplemental revised-outline expectations from the signed baseline.
- Save machine-readable results and manuscript-ready tables, including uncertainty and synthetic/field-validation limits. Prepare a selection decision rather than assume Random Forest wins every future experiment.
- Keep experiments separate from production outputs. Validate runner behavior with controlled data, without claiming those fixtures are agricultural validation.

## Deferred gates

Do not bypass `training/climate_training_contract.py`, relabel unknown source periods, invent nutrient conversions or overwrite the deployed model. Record exactly which evidence prevents a defensible final training run. Phase 8 resolves available scientific inputs and reruns the affected final experiment/selection process. If another algorithm wins, record and resolve the production compatibility decision before replacement; current code is RF-specific.

## Likely files

`backend/training/`, `backend/model_artifacts.py`, `backend/crop_model_metadata.json`, artifact/ranking tests and isolated research output. Preserve the existing model and old result versions.

## Acceptance

The audit links every claimed metric to evidence or marks it unresolved. The runner reproduces its own saved controlled run from recorded inputs, avoids train/test leakage, includes all required metrics and cannot silently publish artifacts. Mark tooling locally verified separately from scientific validation. This phase can advance without NPK data; final data-dependent model acceptance remains visible in Phase 8.
