GeoSustain: seven crops, Decision Tree / SVM / Random Forest, NPK excluded.
Run: 20261106T080700Z-3adeb48c
Execution platform reported by runner: google_colab
Selected by training-only CV macro F1: random_forest
Keep the executed notebook with its outputs as the record of your own Colab run.
Timestamps and this JSON are reproducibility records, not independent proof of execution location.
Do not copy these seven-input models into the current ten-input app.

- Research comparison on existing augmented data; not independent farm accuracy.
- Original Kaggle rows cover banana, coconut, mango and rice only. Cacao, durian and rubber use existing generated profiles.
- GIS predictors in this legacy dataset were generated using crop profiles; their label dependence can inflate evaluation.
- Rainfall periods and temperature aggregation in the labelled rows are unresolved. No annual conversion or relabelling is performed.
- Exact duplicates are removed before splitting; independent farm/source groups are unknown, so a row split cannot establish farm generalization.
- N, P and K are excluded. Received PAGRO measurements require compatible methods/units and matched crop-labelled records before retraining.
- This seven-input candidate cannot replace the current ten-input application model without integration and input-contract review.
