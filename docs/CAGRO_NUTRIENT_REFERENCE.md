# CAGRO nutrient reference assessment

Current behavior for new analyses is documented in [LEGACY_NPK_RESTORE.md](LEGACY_NPK_RESTORE.md):
main NPK cards show recorded model estimates; historical CAGRO observations remain
separate. The CAGRO-first display below remains applicable to older saved snapshots.

## Evidence audit and limits

The existing crop reference schema contains temperature, annual rainfall, pH,
elevation, slope and humidity criteria, but no compatible N/P/K soil criteria.
Repository CAGRO data preserves N as reported % or an OM-derived estimate,
and reported P/K in ppm. Analytical/extraction methods, sample depth and original
sample GPS are not documented. A unit match alone cannot establish equivalence.

The existing extracted research material was reviewed:

- `docs/research/banana.pdf.txt`: Banana Production Guide, fertilizer/nutrient
  removal discussion (around lines 430–439). Nutrient removal in kg/ha and oxide
  forms is not a soil concentration suitability range; none is adopted.
- `docs/research/cacao.pdf.txt`: Philippine Cacao Industry Roadmap 2021–2025,
  site-selection discussion (around lines 4289–4295), refers to organic matter
  and environmental criteria, not a compatible N/P/K concentration criterion.
- `docs/research/rubber.pdf.txt`: BSWM Davao del Sur rubber suitability material;
  the stored extraction supplies no defensible CAGRO-compatible N/P/K criterion.
- Existing `crop_requirements.py`, CAGRO documentation and nutrient-contract audit
  provide no defensible conversion or compatible crop-specific nutrient range.

This is an audit of repository evidence, not a claim that no such agricultural
references exist elsewhere. No external threshold, fertilizer rate, synthetic
training profile or example number in the task was adopted as a production rule.

| Current approved reference crop | N | P | K |
| --- | --- | --- | --- |
| Banana | Not assessed | Not assessed | Not assessed |
| Coconut | Not assessed | Not assessed | Not assessed |
| Rice | Not assessed | Not assessed | Not assessed |
| Durian | Not assessed | Not assessed | Not assessed |
| Mango | Not assessed | Not assessed | Not assessed |
| Rubber | Not assessed | Not assessed | Not assessed |
| Cacao | Not assessed | Not assessed | Not assessed |

No crop list was changed. `NUTRIENT_REQUIREMENTS` contains empty mappings for
these same crops. Future criteria require a reviewed source (title, URL or
citation, section/table/page if known), unit, nutrient definition, analytical
method, limitations, optimal interval and optional absolute interval. Observation
and criterion must match unit, definition and method exactly; unknown metadata
fails closed. Outside an optimal interval without a documented accepted interval
remains Not assessed. Tests use explicitly synthetic criteria to exercise all
status branches; these fixtures are not agricultural references.

## Data flow and model separation

1. `cagro_locations.json` and `cagro_observations.json` retain original values.
2. `lookup_soil_observations` uses existing full-polygon locality matching rules.
   It adds association provenance without claiming exact original sample GPS.
3. After inference, `fastapi_app.build_analysis_result` calls `nutrient_layers`.
   This now also calls `screen_soil_nutrients` for the separate reference layer.
4. `result_snapshot` saves the whole result; `enrich_history_rows` restores it
   without matching again, fetching today's soil or rewriting old results.
5. Flutter reads `soil_nutrient_reference.crops[<crop name>]` for visible N/P/K.
   Single rows can display the backend reference result; multiple rows remain
   separate and expandable, with no average or representative row.

Neither `environmental_pipeline`, `model_ranking`, `predict_proba`, the model
artifact nor training data is changed. No nutrient reference status contributes
to the model ranking or to the existing environmental reference minimum score.

## Additive API schema (version 1)

`soil_nutrient_reference` contains:

- `schema_version`: 1.
- `assessment_type`: `reference_based_soil_nutrient_screening`.
- `status`: `matched` or `unavailable`; only server-matched rows with known
  matching provenance are eligible. No polygon/no valid association is unavailable.
- `used_for_model_prediction`: false.
- `note`: historical/locality limitations and field/laboratory verification advice.
- `message`: unavailable, historical evidence, or multiple-observation explanation.
- `crops`: keyed by unchanged approved crop names. Each contains `records`,
  `combined_status=Not assessed` and `combined_reason`. No combined NPK score exists.
- Each record: `record_id`, `provenance` (a complete copy of the matched original
  row including source/file/row/hash, original address, raw nutrient values/units,
  nitrogen method, sample date/year, location confidence/precision, original GPS
  flag and match type/details), and `factors`.
- Each factor: `factor` (nitrogen/phosphorus/potassium), `label`, original `value`
  and `unit`, `source`, `quality` (estimated_from_organic_matter,
  historical_reported_observation, or unavailable), `nutrient_definition` (OM-derived N or unknown
  unless explicitly documented), original `method`, `status`, `reason`,
  `requirement` (compatible documented rule or null), `used_for_model_prediction`
  (false) and `assessment_type`.
- Status: Suitable within documented optimal range; Limited within documented
  accepted range; Outside documented range outside the accepted range; otherwise
  Not assessed. No range or value is fabricated for missing data.

Existing `cagro_soil`, `soil_nutrients_observed`, `soil_location_match`, model-input
layers, aliases and score fields are unchanged. This schema adds no DB column.

## Farmer display and backward compatibility

Crop details distinguish **AI Crop Ranking** from **Environmental & Soil Reference
Assessment**. Matched CAGRO is preferred over legacy model estimates for visible
N/P/K. Each summary is labelled Nitrogen/Phosphorus/Potassium (CAGRO), with original
units for a single observation. Multiple matches show Not assessed and a multiple
historical observations message, with individual records below. Expanding a row
shows its own nutrient cards/statuses and original provenance. Missing compatible
criteria explicitly show Not assessed, never a fabricated preferred range.

The historical note states that current conditions may differ and field or lab
verification is recommended. The locality context is not an exact farm soil test.
Unmatched farms show CAGRO unavailability and may retain the existing model nutrient
cards labelled “Existing model estimate; not a soil test.”

Old snapshots containing matched `cagro_soil` can display their original values
without inventing reference grades. Snapshots without CAGRO data retain legacy
model displays. Neither history nor model scores are retroactively altered.

## Deployment and verification

Deploy the backend for new reference snapshots; rebuild/deploy Flutter (including
the Vercel web deployment if that hosts this Flutter build). No retraining or DB
migration is required. Old analyses need rerunning only to acquire missing CAGRO
evidence/new backend assessment metadata. Rerunning does not create missing
criteria; all current crop nutrients remain Not assessed.

```powershell
.\.tools\python\python.exe -m pytest backend/tests -q -p no:cacheprovider
flutter test --no-pub test/cagro_nutrient_reference_test.dart test/cagro_soil_card_test.dart test/environmental_factor_display_test.dart test/annual_rainfall_display_test.dart test/crop_details_sheet_test.dart test/model_explanation_test.dart
```
