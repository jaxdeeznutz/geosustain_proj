# Climate variable contract — climate-periods-v1

## Audit and before/after flow

Before: the production pipeline retrieved a CHIRPS/Open-Meteo 30-day rain total,
ERA5-Land five-year mean temperature, CHIRPS five-year mean annual rain and current
humidity. Random Forest used recent rain, mean temperature and current humidity;
reference screening used annual rain and mean temperature. Annual humidity was
unavailable. This separation was mostly correct, but inference lacked unit/period
validation, polygon means ignored periods/windows, and the parcel humidity alias
retained the first sample. Generic temperature labels hid its aggregation period.
The legacy API path also produced a 70/30 blend of a selected-month historical
temperature and a rolling temperature mean, without a common period.

After: the same production model values are retained when their operational
unit/period contract matches. Mismatched or unavailable inputs stop inference;
polygon measurements with different units, periods or baseline windows are not
averaged. Humidity aliases now reflect the parcel mean. Reference screening still
uses `crop_requirements.FACTORS` unit/period checks, never annualized recent rain
or current humidity as annual humidity. The cross-period legacy temperature blend
is no longer generated. No physical conversion, threshold, crop or model changed.

## Production contract table

| Explicit API field | Existing alias / measurement key | Source | Unit | Period | ML | Reference screening |
| --- | --- | --- | --- | --- | --- | --- |
| `rainfall_30d_mm` | `rainfall_mm` / `rainfall_recent` | CHIRPS daily; Open-Meteo backup | mm | Rolling 30 completed days | `rainfall` | Excluded |
| `rainfall_annual_mean_5y_mm` | `annual_rainfall_mm` / `rainfall` | CHIRPS daily | mm/year | Mean of five complete calendar-year totals | Excluded | Annual rainfall |
| `temperature_mean_5y_c` | `temperature_c` / `temperature` | ERA5-Land daily 2m air temperature | C | Daily mean across five complete calendar years (`annual_mean`) | `temperature` | Climate temperature |
| `humidity_current_pct` | `live_humidity` / `humidity_current` | OpenWeather current; Open-Meteo backup | % | Current relative humidity | `humidity` | Excluded |
| No current provider | measurement key `humidity` | Unavailable | % | Annual mean required | Excluded | Unassessed |

These are provider/modelled environmental estimates, not parcel laboratory or
station measurements. The five-year baseline is **not a 30-year climate normal**.
`start`/`end_exclusive` identify its actual window. Legacy provider tuples do not
carry recent-rain dates or humidity observation timestamps, so those metadata
dates remain null rather than being reconstructed from request time.

## Other climate fields (separate contexts)

| Context/fields | Source, unit and period | Use and limitation |
| --- | --- | --- |
| Weather endpoint `temperature_current_c` (`temperature_c` alias), `humidity_current_pct` (`live_humidity` alias) | Open-Meteo; C / %; current | Weather display only; not substituted into analysis climate averages |
| Weather `rainfall_30d_mm`; aliases `rainfall_mm`, `rainfall_monthly_mm`, `monthly_rainfall_mm` | Open-Meteo daily precipitation, mm, 30 completed local dates | Display only; aliases do not mean calendar-month totals |
| Weather `rainfall_today_mm`, `today_rainfall_mm`, `daily_rainfall_mm` | Open-Meteo daily sum, mm, today's local date | Display; includes forecast, not a completed observed day |
| Weather `current_precipitation_mm` | Open-Meteo current precipitation; provider current interval | Display; not annual or 30-day rain |
| Weather `rain_next_3h_mm`, `rain_next_6h_mm`, probability fields, `max_temp_next_6h_c` | Open-Meteo hourly forecasts; mm / % / C; named upcoming window | Forecast display only |
| Legacy `rainfallDatasets.get_temperature`, `temperature_c`, `surface_temp_c` | ERA5-Land 2m air temperature, C; `_date_window(12)` is actually **360 days** | Older engine input/display; surface alias is historical, not land-surface temperature. Source text corrected; not used by new pipeline |
| Legacy engine `get_rainfall`, monthly/30-day aliases; `live_humidity` | Same recent rainfall/current humidity providers | Older engine inference; fallback constants remain legacy-only behavior, excluded from new production climate path |
| `historical_climate_baseline.mean_temperature_c`, `.mean_humidity_pct` | NASA POWER T2M/RH2M; C/%; selected month across 2005–2024 | Legacy seasonal evidence only; not new-pipeline inputs or annual criteria |
| `historical_climate_baseline.mean_rainfall_mm` | NASA POWER PRECTOTCORR selected-month arithmetic mean; physical unit not established by stored repository metadata | Legacy misleading name retained; **do not interpret as a monthly or annual total**. Provider response units are not persisted; no conversion invented |
| `temperature_c_combined` | Former 70/30 mixture of different periods | No longer generated; old saved snapshots remain unchanged |
| `heatmap_grid[].rainfall`, rainfall distributions | Analysis recent rain in mm | Spatial display summaries; not annual screening or training data |

## Training and retraining status

`Crop_recommendation.csv` has plain numeric climate columns without period
metadata. `training/train_model.py` appends `LOCAL_CROP_PROFILES`, whose rainfall
comment says recent 30-day rainfall; temperature/humidity periods are unspecified.
Neither matching magnitudes nor CSV column names prove semantic equivalence.
The saved feature list contains names, and the loader's SHA-256 identifies model
bytes, not training periods. The augmented CSV does not repair this provenance.

**Training/inference semantic equivalence remains unverified. Retraining was not
performed.** There is insufficient evidence to determine or repair every row's
period without inventing data. Existing production Random Forest behavior is
retained explicitly as legacy behavior, not certified as compatible. A guard in
`training/climate_training_contract.py` stops this unresolved training script
before data augmentation/artifact replacement. To unblock retraining, obtain
documented, consistently period-labelled climate/crop data, revise the actual
training sources and provider contract together, and validate the resulting
Random Forest before replacing artifacts. Do not merely change guard labels.
The current guard alone is not scientific validation or a complete training
provenance system. No CAGRO substitution is involved.

## New schema and compatibility

- `climate_contract_version`: version of operational inference/API semantics.
- Explicit scalar fields above supplement existing aliases, which retain their
  meanings. Saved analyses are never rewritten or assigned new periods.
- `climate_field_metadata`: keyed by explicit scalar name; `unit`, `period`,
  `source`, `quality`, `start`, `end_exclusive`, `model_feature`, `screening_factor`,
  `baseline_years` (5 for annual baseline fields, otherwise null), and `status`
  (`available` or `unavailable_or_incompatible`). Weather endpoint metadata
  includes its current/recent units, periods, source, quality and rain dates.
- `climate_training_compatibility=unverified` and `climate_model_warning` disclose
  the unresolved training issue; they do not alter Random Forest class scores.
- `model_explanation.samples[].model_climate_inputs`: exact accepted measurement
  objects keyed by model feature, plus `api_field` and
  `training_compatibility=unverified`. Model hash and feature names are unchanged.
- New crop-detail displays label five-year air temperature/current humidity and
  exclude annual ranges from current humidity/recent-rain model displays. Older
  results retain generic temperature labels where period provenance is absent.

## Verification and rollout

From repository root:

```powershell
.\.tools\python\python.exe -m pytest backend/tests -q -p no:cacheprovider
flutter test test/environmental_factor_display_test.dart
```

Deploy backend and rebuild the Flutter client for new display labels. No database
migration or automatic retraining is required. Existing saved analyses remain
readable; rerun to obtain new metadata or corrected parcel humidity summaries.
Rerunning does not resolve unknown training periods. Seasonal NASA rainfall units
and legacy aliases remain documented limitations, not validated conversions.
