# Farmer crop-details rainfall comparison

The crop-details environmental card now shows `rainfall_annual_mean_5y_mm`
(preferred) or the backward-compatible `annual_rainfall_mm`, in **mm/year**.
The explicit five-year field is labelled **Annual Rainfall (5-year mean)**;
older annual fields without baseline metadata are labelled **Annual Rainfall**.
If the preferred field is explicitly null, stale aliases do not replace it.
Supplied field metadata must agree with mm/year and annual_mean_total.

The card reads the selected crop's saved `factors` entry with annual rainfall
unit/period and its `requirement.optimal` range supplied by backend
`crop_requirements.py`. It displays the backend screening score as Suitable,
Limited or Outside documented range only when the assessed value matches the
displayed annual value. This preserves backend absolute ranges, published class
boundaries and unassessed gaps without inventing frontend agronomic thresholds.
Missing annual values, criteria, scores or mismatched assessed values remain
unavailable/unassessed. No crop requirements are hardcoded into the UI.

Recent rain and `model_explanation.samples[].inputs.rainfall` are never used by
this card, converted to annual rainfall, or shown as a 30-day suitability card.
The Random Forest input, model artifact, rankings and backend remain unchanged.
Annual reference screening is separate from the model ranking; it is not a
guarantee of crop performance. Other environmental factor behavior is retained.

This supersedes the rainfall-card description in MODEL_INPUT_DISPLAY_2026-10-20.md
and the earlier climate-contract display note. Internal recent-rain metadata and
weather views retain their existing purpose.

Deploy/rebuild the Flutter client; no backend deployment, migration or retraining
is required. Existing analyses with saved annual values and criteria work without
rerunning. Analyses lacking that evidence require a new analysis for an assessed
annual rainfall card; missing evidence is never reconstructed from recent rain.

Verification:

```powershell
flutter test --no-pub test/environmental_factor_display_test.dart test/annual_rainfall_display_test.dart test/crop_details_sheet_test.dart test/mobile_results_test.dart
```
