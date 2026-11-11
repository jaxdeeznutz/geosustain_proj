# GeoSustain model comparison evidence

**For the November 11 manuscript and the installed backend model, use `manuscript-matching-10-feature/`.** It contains the exact ten-input source CSV, original recorded results, a locally reproduced comparison, and a new self-contained Colab notebook. The installed backend model uses N, P, K, temperature, humidity, pH, rainfall, NDVI, elevation, and slope.

The older notebook at this folder's root, `GeoSustain_Colab_Training_Comparison.ipynb`, is a **separate seven-input experiment without NPK**. Its Random Forest holdout accuracy is 78.49%, whereas the manuscript's ten-input experiment reports 86.02%. Its results must not be described as the manuscript's model evaluation or the installed app model.

## Which evidence to show

| Purpose | Use |
| --- | --- |
| Explain the manuscript and installed prototype | `manuscript-matching-10-feature/README.md`, its Colab notebook, source CSV, and recorded report. |
| Discuss an alternative without NPK | The root seven-input notebook, `data/`, and `results/`. Label it as a separate research comparison. |

## Earlier seven-input experiment

The root `data/seven_crop_without_npk.csv` contains 1,820 seven-crop rows, with SHA-256 `bfd1f5b9c2a1b745b62f93f16e95464f3d2bb7e81f4bbaeb3621a986c134c3c1`. The earlier run removed 426 duplicates and evaluated 1,394 unique rows. Its five-fold training-only macro F1 and holdout results are in `results/comparison.csv`; `results/training_run.json`, `results/split_manifest.csv`, and `results/holdout_predictions.csv` record the split, predictions, and limitations. `verify_package.py` checks hashes, row counts, and the blank notebook structure.

| Model | Mean CV macro F1 | Holdout accuracy | Holdout macro F1 |
| --- | ---: | ---: | ---: |
| Decision Tree | 0.659 | 0.717 | 0.673 |
| SVM | 0.709 | 0.735 | 0.683 |
| Random Forest | 0.756 | 0.785 | 0.731 |

The recorded seven-input run identifies Google Colab as its execution platform. That metadata is not independent proof of who performed the run. Both supplied notebooks are **unexecuted**. To show your own Colab execution, run the **ten-input manuscript notebook** in Colab, save the executed notebook with its outputs to Drive, and keep the downloaded results ZIP.

Neither comparison establishes field-validated accuracy on independent Panabo farms. The legacy source includes augmented or generated values, and nutrient units and climate periods need independent verification.
