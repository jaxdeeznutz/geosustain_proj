# GeoSustain: your three-model Colab training run

Open `GeoSustain_Seven_Crops_No_NPK.ipynb` in Google Colab, then choose **Runtime
→ Run all**. Use a CPU runtime; these scikit-learn models do not require a GPU.
The notebook contains the exact starter CSV and trainer, so there are no separate
dataset uploads or API keys. You can enter your name in the configuration cell.

The run trains **Decision Tree, SVM and Random Forest**, compares them on the
same split, and downloads a ZIP containing:

- All three fitted models, their exact feature order and hyperparameters.
- Training-only cross-validation scores and the fixed holdout comparison.
- Per-crop precision/recall/F1, confusion matrices and comparison charts.
- Split assignments, original input, deduplicated rows and holdout predictions.
- Dataset/source and training-script hashes, package versions and run timestamps.

Select the candidate using training-only CV macro F1. The held-out test results
are reported for all three; the test set is not used to choose the winner. SVM
scaling is inside its pipeline, including within CV. Exact duplicates are removed
before the shared split. No model is guaranteed to win or achieve a target score.

After your run finishes, save the executed notebook to your Google Drive and
download the `.ipynb` **with its outputs**, plus the result ZIP. Preserve the
actual notebook and tables; screenshots alone omit important details. The blank
starter notebook has no precomputed results or execution counts. Local QA runs
are identified as local and are not represented as your Colab execution.

## What is partially finalized

| Item | This experiment |
| --- | --- |
| Crop labels | Banana, Cacao, Coconut, Durian, Mango, Rice, Rubber |
| Predictors | temperature, humidity, pH, rainfall, NDVI, elevation, slope |
| NPK | Excluded entirely; no zero placeholders or fake PAGRO values |
| Models | Decision Tree, SVM, Random Forest |
| Evaluation | Common 80/20 stratified row split; five-fold CV on training rows |
| Output | Research candidates and reproducible training evidence |
| App integration | Separate work: deployed model still expects ten predictors |

The dataset is filtered from the project's **existing augmented CSV**. Original
Kaggle feature-row matches exist for banana, coconut, mango and rice. Durian,
cacao and rubber use the existing generated crop profiles. GIS values are also
legacy generated predictors, not measured farm GIS records. The manifest
records this provenance and the source hashes. No rows are synthesized by this
notebook. Removing NPK does not remove the generated GIS or crop-profile basis.

This is a valid record of training those algorithms on that dataset. Its scores
describe held-out **legacy rows**, not annual-input accuracy or Panabo farm
validation. Independent farm/source groups are absent; deduplication cannot
establish farm independence. Existing rainfall rows are not annualized, and
their uncertain aggregation periods are not relabelled to match the app's
five-year annual inputs. Keep that limitation with the reported results.

## Adding PAGRO NPK later

1. Keep this no-NPK run as a baseline.
2. Establish N/P/K units, soil depth, test method, dates, locations and matching
   crop-labelled observations. Locality nutrient tables alone do not provide
   supervised crop labels or automatically match these legacy rows.
3. Prepare a new versioned dataset. Do not paste unrelated soil measurements into
   existing training rows, and do not fill unmeasured records with invented NPK.
4. Retrain all three models and evaluate with consistent feature definitions,
   appropriate farm/source grouping and an independent holdout.
5. Update the application's input contract and explanation/serialization checks
   when integrating the reviewed candidate. Neither this notebook nor its ZIP
   changes the active backend model.

Compatible annual-labelled data and agricultural evaluation remain separate
requirements. References used by the app's environmental checks are not extra
labelled training observations.

## Files and local replay

The CSV and provenance manifest are also in `data/`. The notebook's source is
`train_without_npk.py`; its dependencies are in `requirements.txt`. To replay
locally from this directory:

```powershell
python -m pip install -r requirements.txt
python train_without_npk.py --dataset data/seven_crop_without_npk.csv --manifest data/dataset_manifest.json --output runs
```

Keep generated model binaries/result ZIPs as research evidence. Do not rename a
seven-input model to `backend/crop_model.pkl` or claim that it has been integrated.

Method references: [Colab FAQ](https://research.google.com/colaboratory/faq.html),
[scikit-learn leakage and pipelines](https://scikit-learn.org/1.8/common_pitfalls.html),
[cross-validation](https://scikit-learn.org/1.8/modules/cross_validation.html),
[model persistence](https://scikit-learn.org/1.8/model_persistence.html).
