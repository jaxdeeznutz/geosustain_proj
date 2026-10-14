# Model-ranked crop recommendations

New analyses rank the enabled, supported crop catalog using the existing trained
Random Forest's raw `predict_proba` outputs. Each crop's score is the arithmetic
mean across parcel samples, multiplied by 100. Return and display the top five in
descending score order. Filtering the catalog does not renormalize probabilities.
Reference-condition comparisons remain available as supporting information but
do not affect ranking. Missing model inputs cause an explicit failure rather than
a silent rule-based fallback.

The previous reference index assigned 100 to the strongest assessed class even
with incomplete environmental coverage. New scores are labeled **Model score**,
not measured land suitability or harvest probability. There is no artificial cap:
a genuine model output can still be 100. The existing model is uncalibrated,
includes synthetic GIS training features, and uses estimated phosphorus and
potassium inputs; Panabo field validation has not been established.

Saved historical analyses retain their original calculations and are labeled as
reference indices. Run a new farm analysis after deploying both backend and
frontend to obtain model-ranked results. No historical records are rewritten.

Validation: 81 backend tests and 82 Flutter tests passed, including real saved-model
inference with mocked environmental providers, parcel aggregation, raw probability
preservation, top-five ordering, and mobile rendering at 360 and 402 pixels.
