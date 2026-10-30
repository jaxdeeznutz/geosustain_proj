# Phase 2 - Seasonal assessment

Dependency: Phases 0-1 and the source/configuration contract. Nutrient datasets are not needed.

## Problem and intended behavior

The modern model path currently saves the intended month then returns before its historical monthly summary. Attach a separate seasonal evidence snapshot without altering crop rankings or adding unvalidated seasonal score weights.

## Implementation tasks

- Retrieve and persist documented historical monthly climate information for the selected month, with source, location/spatial method, baseline years, valid observations, units, represented period and quality.
- Keep five-year annual references, selected-month climate, recent completed 30-day conditions and current humidity separate. Do not compare totals from unequal-duration windows as equivalent or synthesize a blended temperature.
- Use calendar records with explicit evidence and validity scope. Where a calendar or monthly observation is unavailable, say so; do not generate an unsupported In season label.
- Preserve the planting month and analysis timestamp. If year-dependent advice is needed, define how the year is selected rather than imply an unknown future forecast.
- Save a plain-language seasonal summary, limitations and any justified bounded actions. Integrate the same snapshot into farmer results, analyst review, history/reopen and reports.
- Cache and bound provider work, disclose partial retrieval and preserve the distinction between retrospective context and forecast.

## Likely files

`backend/fastapi_app.py`, `backend/environmental_pipeline.py`, `backend/climate_contract.py`, seasonal summary helpers, farmer/analyst result and report consumers. Coordinate calendar versioning with Phase 6.

## Acceptance

Use controlled months/windows, unavailable-provider responses and saved snapshots to verify that selecting a different month changes relevant seasonal context when evidence supports it. Confirm appropriate missing-calendar behavior and report/reopen parity. Assert unchanged model probabilities, crop order and existing annual factor grades. Later run a bounded real-provider check when configured.

Complete when every new formal analysis contains a saved seasonal summary or an explicit evidence-unavailable state, and supported seasonal claims are verified. A missing source is not a positive seasonal assessment.
