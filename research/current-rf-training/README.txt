GEOSUSTAIN: RANDOM FOREST FOR SEVEN CROPS

Open GeoSustain_Random_Forest_Seven_Crops.ipynb in Google Colab.
The CSV, source code and provenance are embedded; no separate upload is needed.

CHAPTER 2
Keep RUN_TRAINING = False. Run all cells to inspect preparation and show N/A
for accuracy, precision, recall and F1. No classifier is fitted in this mode.
Save the notebook as evidence of preparation, not completed training.

ACTUAL TRAINING, WHEN READY
Set RUN_TRAINING = True and run all cells. This trains only Random Forest.
Save the executed notebook WITH outputs and the downloaded evidence ZIP.
The ZIP contains fresh metrics, confusion matrix, per-crop report, predictions,
split assignments, CV scores, settings, timestamps, hashes and fitted model.

There is one classifier with seven crop classes, not seven separate models:
Banana, Cacao, Coconut, Durian, Mango, Rice and Rubber.
Its seven inputs are temperature, humidity, pH, rainfall, NDVI, elevation, slope.
NPK is excluded. Banana variety predictions are not trained by these labels.

The dataset and Random Forest parameters match the current baseline reference.
A new run is separate from the existing installed artifact and does not publish
or replace the app model. Keep current_model_reference.json for that distinction.

Data includes existing generated crop profiles and GIS predictors. Evaluation
describes this dataset experiment, not verified field or annual-input accuracy.
The dataset manifest preserves the full provenance and limitations.

LOCAL TRAINING (this command performs an actual run)
python -m pip install -r requirements.txt
python train_random_forest.py
