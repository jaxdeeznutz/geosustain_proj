# Phase 8 - nutrient data intake preparation

Status: preparation in progress; dataset-dependent work is `PENDING_EXTERNAL`.
No runtime/model/nutrient-source changes have been made in this phase.

## Existing material

`DATA_INTAKE_AUDIT.json` records checksums, fields, row counts and numeric ambiguities
for the two earlier source-image transcriptions: 11 rows in soil_table_2025.csv and
20 in soil_table_organic.csv. Their source limitations remain authoritative in
`data/cagro_pending/README.md`. These are reference-only files, not validated input
to the runtime model or a current parcel soil-observation dataset.

The second table's Organic column is not nitrogen. Ambiguous punctuation remains
raw; it is not repaired by guessing. Repeated addresses remain separate source
rows. Addresses and a visible year do not supply sample IDs, exact dates, depth,
coordinates, verified coverage or current farm association. Raw source images and
private location data must not be published by this preparation work.

The existing note says CAGRO clarification is unavailable. Do not repeatedly request
it as if it were a known obtainable input. Record missing metadata as unknown and
inspect any new source files or accompanying laboratory documentation if supplied.

## Required evidence before ingestion or nutrient grading

| Evidence | Intake rule |
| --- | --- |
| Provider, source document and usage basis | Record actual source, access/ownership restrictions, acquisition date and immutable file checksum. |
| Sample identity and date | Preserve individual sample identifiers and actual sampling dates; flag absent fields. |
| Spatial association | Preserve supplied coordinates/geometry, their basis and resolution; document verified farm/locality linkage rather than inventing it from an address. |
| Depth and sampling protocol | Record depth interval, collection/compositing method and interpretation limits. |
| Nutrient identity and units | Record nitrogen form and explicit N/P/K units; distinguish elemental/extraction or other reported chemical basis. |
| Laboratory/estimation method | Preserve the actual laboratory method or model/version, including phosphorus and potassium extraction basis where applicable. |
| Quality and uncertainty | Retain measured/modelled/historical/estimated status, uncertainty, detection limits, missing-value rules and exclusions. |
| Crop nutrient criterion | Require a traceable criterion compatible with observation units, method, depth and temporal basis; a new dataset alone does not justify a grade. |
| Agricultural interpretation | Record actual qualified review when required, without treating software owner acceptance as agronomic validation. |

## Immutable ingestion contract

1. Copy a supplied source into a controlled intake location and record its hash;
   preserve original names/content. Keep transformations and decisions in a
   separate manifest. Do not edit the reference CSVs in place.
2. Validate required metadata and raw values before numeric normalization. Flag
   ambiguous, missing, nonfinite or inconsistent values. Do not infer units from
   magnitude or convert organic content into nitrogen.
3. Retain source sample IDs, source-row identity and any stated uncertainty.
   Detect duplicates without automatically deduplicating or averaging them.
4. Separate local historical measurements, remote modelled layers and existing
   inference proxies. Decide display, grading and inference eligibility separately.
5. Require an explicit spatial/temporal association rule with limitations before
   assigning a record to a parcel. Keep absent/incompatible nutrients Not assessed.
6. Store the selected source/units/method/association in each new saved snapshot;
   old results retain their own versions. Reports and screens must agree.

## Model and evaluation boundary

Keep current estimated N/P/K labels, Not assessed nutrient grades and the current
CAGRO-disabled behavior. Do not feed new physical-unit measurements into an
unresolved legacy model feature contract. Resolve nutrient and climate training
contracts before any changed inference or training.

Use Phase 4's isolated comparison tooling only with an evidenced compatible
dataset/feature outcome. Record dataset/model/configuration hashes, held-out
evaluation, class support, leakage checks, actual metrics and limitations. Do not
invent manuscript results or select a new production model from a convenient
score. Changed artifacts require attribution reconstruction and affected
integration/report/history regressions before they become a new candidate.

## Completion paths

- **Defensible data/method/model outcome:** record the actual source review and
  compatibility/evaluation evidence, then run the affected acceptance checks.
- **Limited-proxy study conclusion:** only if an actual qualified/adviser-approved
  scope decision is obtained and recorded, retain explicit proxy and unknown-data
  limitations. No such decision is recorded by this preparation document.

Until one of those outcomes is evidenced, scientific completion remains open.
Independent Phase 9 preparation may continue, but participant results, deployment
and release/scientific signoff must not be fabricated or implied.
