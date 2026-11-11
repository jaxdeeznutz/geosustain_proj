# Manuscript matching ten feature model comparison

Use this folder for the November 11 GeoSustain manuscript and the backend model installed in this repository. The earlier top-level `GeoSustain_Colab_Training_Comparison.ipynb` is a separate seven-feature experiment **without NPK** and has different scores. Do not present that earlier screenshot as the manuscript's model evaluation.

The repository also contains an older seven-input release receipt, but the checked-in `backend/crop_model.pkl`, its feature sidecar, and its metadata currently use ten inputs. `render.yaml` starts the service from `backend/`. The actual live service should still be checked independently before claiming which model a particular deployment has loaded.

## Files

| File | What it shows |
| --- | --- |
| `GeoSustain_Manuscript_Model_Comparison_10_Features.ipynb` | Self-contained Colab notebook that reruns the ten-input comparison. Its code cells have no comments. |
| `data/Crop_recommendation_with_gis.csv` | Exact 4,420-row legacy source CSV, SHA-256 `1a6dcf3b22c20ff51c0ef7eee310df3ad5d359263d78d1a93e2dbaa7245ec03a`. |
| `recorded/training_report.json` | Original recorded model comparison, split indices, parameters, class reports, and limitations. |
| `recorded/installed_model_metadata.json` | Backend model metadata showing the ten input names and the recorded Random Forest scores. |
| `replay_training.py` | Readable stand-alone code using the recorded split and settings. It saves only to this evidence folder. |
| `local_replay_results/` | A new **local** replay performed on November 12, with exactly matching rounded and unrounded holdout scores. It is not a Colab execution record. |
| `verify_package.py` | Checks source hash, feature order, metric agreement, and the unexecuted notebook contents. |

## How the recorded comparison works

The script keeps the seven approved crops from the raw CSV: banana, cacao, coconut, durian, mango, rice, and rubber. It removes 426 duplicate input-and-label rows before splitting, leaving 1,394 unique rows. With seed 42, a stratified 80/20 split uses 1,115 rows for training and 279 for holdout. Decision Tree, scaled SVM, and Random Forest are fitted to the same training rows and evaluated on the same holdout rows. This experiment **does not report cross-validation scores**.

The ten inputs are N, P, K, temperature, humidity, pH, rainfall, NDVI, elevation, and slope. The source includes augmented or generated values, and the nutrient units and climate periods are unresolved. The metrics are results on these legacy rows, not field-validated farm accuracy or harvest probabilities.

| Model | Holdout accuracy | Holdout macro F1 |
| --- | ---: | ---: |
| Decision Tree | 76.70% | 69.51% |
| SVM | 83.15% | 78.36% |
| Random Forest | **86.02%** | **80.00%** |

## Run it yourself in Colab

1. Open `GeoSustain_Manuscript_Model_Comparison_10_Features.ipynb` in Google Colab. It embeds the exact CSV, so no separate upload is needed.
2. Choose **Runtime > Run all**. Check the row counts and the three-model table and chart.
3. Save the **executed** notebook to Drive and keep its downloaded results ZIP. Those outputs document your own Colab run. The supplied notebook is blank until you execute it.
4. If Colab uses different scikit-learn, NumPy, or pandas versions, compare the printed versions with `recorded/training_report.json` (scikit-learn 1.8.0, NumPy 2.4.6, pandas 3.0.6). A changed environment may change results slightly.

For the defense: "We compared Decision Tree, SVM, and Random Forest on the same seven-crop legacy dataset with ten inputs, including N, P, and K. After removing exact duplicates, we trained on 1,115 rows and tested on the same 279-row holdout. Random Forest scored 86.02% accuracy and 80.00% macro F1, the highest of the three. These results do not establish performance on independent Panabo farms."
