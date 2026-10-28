# Restored estimated NPK analysis

New analyses use the pre-CAGRO nutrient estimation path, based on the behavior
before commit `965e217` (baseline `f66ad85`). The original formulas, model binary,
crop ranking, climate inputs, land-cover checks and city boundary are retained.

Within the existing Panabo City boundary, a missing CAGRO locality match no longer
forces preliminary screening. Point and polygon analysis run the existing model
when its required environmental inputs are available. Missing required model
inputs and water/built-up restrictions still prevent a crop recommendation.

CAGRO reference is now temporarily disabled by default. New requests skip its
locality matching and catalogue reads, return `cagro_reference_enabled=false`,
and hide the reference/unavailable cards. The original observations and older
saved snapshots are preserved. Set backend `CAGRO_REFERENCE_ENABLED=1` and restart
only when the separate historical reference should be enabled again.

Incomplete or unavailable land-cover observations no longer stop the model.
They retain an unverified status, nullable/missing observations, and an explicit
warning alongside the result and in reports. A model estimate is not proof that
the parcel is agricultural. Positive mapped water/buildings/mixed-area exclusions
are retained, as are the city boundary and required model input checks.

- N: the existing SoilGrids/OpenLandMap adapter; its existing regional fallback
  is 80 and remains labelled `fallback_default`.
- P/K: the existing NDVI/pH/elevation heuristic, including configured fallback
  values of 47/50 when that heuristic cannot parse its inputs. These are not
  constant readings assigned to every parcel.
- Values use the legacy model scale. No laboratory unit, fertilizer rate or
  current field measurement is inferred.

New snapshots use `analysis_mode=legacy_model_estimates`. `analysis_coverage.supported`
still describes CAGRO matching; `can_analyze` describes city admission. A separate
`nutrient_display_basis=legacy_model_estimates` identifies completed inference
whose main farmer NPK cards must show recorded model inputs rather than CAGRO
observations. Historical CAGRO rows remain accessible separately, without changing
their values, selecting a representative row, or feeding them to the model.

Top-level `nitrogen`, `phosphorus` and `potassium` are computed only from saved
inference inputs. A point shows its actual input values; a polygon shows the
arithmetic mean across all recorded samples. The sample count/method is explicit,
and individual samples, quality and sources remain in the model snapshot. A
missing sample nutrient is unavailable, never an average over a subset. An
advisory without inference does not receive invented nutrient values.

Existing saved analyses are not upgraded or rewritten. A new analysis is required
to obtain the restored model behavior and display fields. No database migration
or retraining is needed. Restart/deploy the backend and rebuild the Flutter client
to make both API and UI changes available to users.

Validation includes offline tests using the real saved forest with controlled
provider observations for both point and polygon requests, separate historical
records, retained fallback labels, and unchanged old snapshots. Flutter checks:

```powershell
flutter analyze --no-pub
flutter test --no-pub test/legacy_npk_display_test.dart test/cagro_nutrient_reference_test.dart test/analysis_coverage_test.dart test/panabo_screening_test.dart
```
