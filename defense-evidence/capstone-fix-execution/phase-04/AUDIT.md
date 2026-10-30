# Phase 4 audit: current model, datasets and Table 13

Scope: the exact model shipped in this checkout, available repository data/code, and manuscript claims. The live deployment's identity was not established: a bounded read-only health request failed with ConnectionError and the browser fetch was unavailable. Local bytes must not be presented as proof of the remote runtime. No model retraining, publication, data replacement or recommendation change was performed.

## Artifact and environment

The local model is a 500-tree RandomForestClassifier, maximum depth 14, minimum leaf 6, minimum split 12, balanced-subsample weights, seed 42. Exact SHA-256:

`6dee915ad58e55e376bcfb5a74ecee9db086491cf5fe29a1b3149f5b45be9278`

Its ten features are ordered N, P, K, temperature, humidity, ph, rainfall, ndvi, elevation, slope. Metadata says `legacy_unverified`: training timestamp, script identity, dataset identity and evaluation are not recovered. Installed runtime versions were Python 3.11.9, scikit-learn 1.8.0, NumPy 2.4.6, SciPy 1.17.1, pandas 3.0.6, joblib 1.6.0 and threadpoolctl 3.7.0. These are measured local runtime versions, not recovered historical training versions.

Three different class sets must remain distinct:

- The artifact has 17 classes: abaca, banana, blackgram, cacao, cassava, coconut, durian, maize, mango, mungbean, papaya, pigeonpeas, pomelo, rice, rubber, sweet potato, watermelon.
- The current training-approved set has 13 classes and excludes blackgram, mango, mungbean and pigeonpeas.
- The current ranking catalog contains Banana, Coconut, Rice, Durian, Mango, Rubber and Cacao. Mango is therefore displayed despite being outside the training-approved set. The current metadata's generic statement that ranking filters approved crops must not be mistaken for enforcement of that 13-class training set.

Phase 4 records this discrepancy and preserves the accepted runtime behavior. Catalog/scientific reconciliation is an explicit later gate, not a silent Mango removal or class remapping.

## Data and leakage audit

| Available file | Rows | Classes | Full duplicate rows beyond first | Provenance status |
| --- | --- | --- | --- | --- |
| Crop_recommendation.csv | 2,200 | 22, 100 each | 0 | Training code describes a public Kaggle crop dataset; exact upstream lineage, climate periods, physical nutrient units/methods and independent farm IDs are not supplied in the CSV. |
| Crop_recommendation_with_gis.csv | 4,420 | 17, 260 each | 994 | Already augmented/balanced data; no row-level original-record IDs, generation records or independently validated Panabo outcome lineage. |

The original CSV hash is `54a5a6e5408668e668667efc50de2fc867c1b875e0431b4f54dd331b0a109a4e`. The augmented CSV hash is `1a6dcf3b22c20ff51c0ef7eee310df3ad5d359263d78d1a93e2dbaa7245ec03a`.

Only 1,480 augmented rows exactly match all seven base numeric fields, representing 985 distinct base numeric rows. This is a numeric-match diagnostic, not recovered generation lineage; floating-point serialization and undocumented transformations mean unmatched rows cannot simply be declared synthetic or independent field records.

A **hypothetical** current-CSV 80/20 stratified row split with seed 42 puts 227 distinct exact feature vectors on both sides, with 271 of 884 holdout rows duplicating a training feature vector. This demonstrates a leakage risk in row splitting this file. It is not the recovered original Table 13 split, and no new accuracy was measured on that legacy split.

The existing training source generates synthetic local crop profiles and label-conditioned GIS proxies, balances classes by replacement sampling **before** splitting, then performs a stratified row split. Repeated source observations can cross partitions. Label-conditioned GIS and generated local profiles may make synthetic class discrimination look stronger without establishing independent field performance. The current 13-label source is also not a proven explanation of the 17-label artifact/CSV.

## Table 13 trace

The unchanged 144-page `GEOSUSTAIN_MANUSCRIPT.pdf` has SHA-256 `289e068e9fb3edb1a1ba95bfa7b5836c57a0fc4686cb8bec9a22f70e5de2d504`. PDF page 91 was extracted and visually checked. Page 92 states that these results supported the Random Forest production selection.

**Reported manuscript percentages only - not newly reproduced results:**

| Model | Accuracy | Macro precision | Macro recall | Macro F1 | Weighted F1 | Evidence link |
| --- | --- | --- | --- | --- | --- | --- |
| Decision Tree | 79.86% | 80.56% | 79.86% | 79.80% | 79.80% | Table 13, PDF p91; original experiment unresolved |
| SVM | 84.39% | 84.62% | 84.39% | 84.32% | 84.32% | Table 13, PDF p91; original experiment unresolved |
| Random Forest | 87.78% | 88.15% | 87.78% | 87.57% | 87.57% | Table 13, PDF p91; original experiment unresolved |

`backend/model_comparison_report.json` is absent; no tracked history for that path was found. The searched project/review files supply no original split IDs, per-class predictions, confusion matrices, evaluation environment or artifact binding for these percentages. Other comparison JSONs found in a separate QA checkout are temporary model-serialization test fixtures, not original Table 13 evidence. The current comparison helper records macro metrics but omits weighted F1, so it cannot be treated as the recovered table record. The source dataset/split, historical environment, timestamp and exact saved estimator remain unresolved.

Do not recreate those percentages from memory, infer missing weighted metrics from macro metrics, claim the new controlled run reproduces Table 13, or substitute controlled-fixture results into the manuscript. The PDF was read-only and remains unchanged.

## Scientific contracts and later gates

| ID | Unresolved item | Required resolution / phase |
| --- | --- | --- |
| P4-CLIMATE | Base CSV rainfall/temperature/humidity periods unknown; local rainfall rolling 30 days, local temperature/humidity periods unknown | Document compatible observations and periods against inference's rolling-30-day rain, annual-mean temperature and current humidity; Phase 8. Do not relabel or rescale old rows to force a match. |
| P4-NPK | N/P/K physical units, extraction/measurement methods and inference compatibility unverified | Acquire and review appropriate scientific records and methods; Phase 8. Preserve estimated runtime NPK until an approved change. |
| P4-LINEAGE | No verified independent Panabo crop outcome/farm/time lineage in available CSVs | Establish observation IDs, repeated-unit grouping, duplicates and justified spatial/temporal holdouts; Phases 8/9. Grouping software cannot invent independence. |
| P4-TABLE13 | Original experiment-to-manuscript-to-artifact linkage missing | Recover the original records or update final manuscript claims using newly approved scientific experiments; Phases 8/9. |
| P4-CATALOG | 17 learned classes, 13 training-approved classes and 7 runtime catalog crops differ | Reconcile accepted crop scope and production compatibility before final training/publication; catalog controls in Phase 6 and scientific selection in Phase 8. Preserve current behavior in this phase. |
| P4-LIVE | Live server model identity not reached by bounded read-only probe | Verify actual backend model/hash/version parity when reachable, through integration/release checks in Phases 7/9. |
| P4-SELECTION | No new scientifically accepted model selection | Run the isolated runner on reviewed compatible independent data, assess all three models and resolve any non-RF loader/explanation compatibility before replacement; Phase 8. |

## Locally completed tooling

The [evaluation runner contract](../../../docs/MODEL_EVALUATION_TOOLING.md) describes shared grouped splits, duplicate-connected groups, training-only preprocessing, common features, five comparison metrics, class support, confusion matrices, timing, approximate cluster intervals and nonpublishing outputs. Controlled data prove software behavior only. Final verification logs and closure distinguish this completed audit/tooling scope from the unresolved scientific gates above.

Machine-readable source facts: `audit/model-data-audit.json`. The original health attempt, manuscript page image/text and initial controlled run/replay are retained. Final verifier attempts create their own fresh audit and research results; no prior results are overwritten.
