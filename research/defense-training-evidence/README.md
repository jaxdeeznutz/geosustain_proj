# GeoSustain training evidence and model comparison

This folder brings the existing seven-crop training run, its input CSV, and a runnable Google Colab notebook into one place. The code cells in the notebook contain code only; the markdown cells explain each step.

## What each file is for

| File | Purpose |
| --- | --- |
| `GeoSustain_Colab_Training_Comparison.ipynb` | Self-contained Colab notebook to rerun preparation, training, comparison, and export. It is blank until you execute it. |
| `data/seven_crop_without_npk.csv` | Exact 1,820-row input CSV used by the recorded run. SHA-256: `bfd1f5b9c2a1b745b62f93f16e95464f3d2bb7e81f4bbaeb3621a986c134c3c1`. |
| `data/dataset_manifest.json` | Input provenance, seven feature names, seven crop labels, source hashes, and limitations. |
| `data/training_rows_deduplicated.csv` | The 1,394 unique rows after duplicate removal and before splitting. |
| `results/training_run.json` | Recorded environment, parameters, split, selection rule, and metrics from run `20261106T080700Z-3adeb48c`. |
| `results/comparison.csv` and `results/model_comparison.png` | Three-model comparison from that recorded run. |
| `results/cross_validation.csv` | Five training-only fold scores per model. |
| `results/split_manifest.csv` and `results/holdout_predictions.csv` | Row assignment and model predictions for the untouched holdout. |
| `results/*_classification_report.csv` | Per-crop precision, recall, F1, and support. |
| `results/artifact_hashes.json` | SHA-256 receipts from the recorded run for the copied results. |
| `verify_package.py` | Checks the dataset hash, row counts, notebook code, model comparison, and copied run artifact hashes using Python's standard library. |

The recorded run identifies its execution platform as Google Colab. That metadata and timestamp are reproducibility records; they are **not independent proof of who ran it or where**. For your own execution evidence, open the notebook in Colab, select **Runtime → Run all**, then save the executed notebook with its visible cell outputs and the generated ZIP to your Drive. Keep that executed copy and your Colab run history or screenshots. The supplied blank notebook must not be presented as an executed run.

## What happened in the recorded comparison

1. The CSV retained seven predictors: temperature, humidity, pH, rainfall, NDVI, elevation, and slope. N, P, and K were excluded. The source values were not relabeled, invented, or converted to annual units.
2. The script checked the CSV hash and expected columns, removed 426 exact duplicate predictor/label rows, and kept 1,394 unique rows.
3. A stratified split with seed 42 assigned 1,115 rows to training and 279 to holdout. Identical predictor rows were checked not to cross the split.
4. Decision Tree, SVM with scaling inside its pipeline, and Random Forest used the same five stratified folds on the training partition. Selection used **mean cross-validation macro F1 only**.
5. Each model was fitted on all training rows and evaluated once on the same holdout. Random Forest had the highest training-only CV macro F1.

| Model | Mean CV macro F1 | Holdout accuracy | Holdout macro F1 |
| --- | ---: | ---: | ---: |
| Decision Tree | 0.659 | 0.717 | 0.673 |
| SVM | 0.709 | 0.735 | 0.683 |
| Random Forest | **0.756** | **0.785** | **0.731** |

These values are rounded from `results/comparison.csv`. The current app release identifies the Random Forest artifact with SHA-256 `6cefb5545173c05521a5c1fe71e5cb654b2a17161a1e1399d88f93afa867c8cd` in `research/current-rf-training/current_model_reference.json`.

## What to say during the defense

“We compared Decision Tree, SVM, and Random Forest on the same seven-crop dataset. We removed exact duplicates before an 80/20 stratified split, tuned the selection to five-fold macro F1 on training data, and then checked all three models on the untouched holdout. Random Forest had the strongest CV macro F1, 0.756, and a holdout macro F1 of 0.731. These are results on legacy augmented rows, not field-validated accuracy. The current model does not use NPK.”

If asked why the results are limited: the original crop source covers banana, coconut, mango, and rice; cacao, durian, and rubber rely on generated profiles. The GIS predictors in this dataset were also generated from crop profiles, which can make the comparison optimistic. Independent farm IDs are unavailable, and the rainfall period and temperature aggregation in the labelled rows are unresolved. The app's live geospatial inputs therefore are **not established as equivalent** to this training set. This is an experimental prototype, not proof of agronomic accuracy.

If asked how to add soil NPK later: obtain crop-labelled, location-matched measurements with verified units and collection methods; then retrain and compare a **new** model version. Do not treat the current app's SoilGrids or estimated values as ground-truth training labels.

## Rerun in Colab

1. Open `GeoSustain_Colab_Training_Comparison.ipynb` in Google Colab.
2. Run all cells. The notebook contains the exact source CSV and trainer so it does not need a Drive mount or API keys. The separate CSV and manifest in `data/` let you inspect the input directly.
3. Inspect the generated comparison table, chart, class reports, and split files. Save the executed notebook and download the results ZIP from its last cell.
4. Compare the new output with `results/`. Different dependency versions may slightly change metrics; the notebook pins scikit-learn to 1.8.0 and uses seed 42.

The notebook does not deploy a new model. The existing recorded results and the currently installed artifact remain traceable through the release receipt in `research/model-releases/submission-v1-2026-11-08/`.
