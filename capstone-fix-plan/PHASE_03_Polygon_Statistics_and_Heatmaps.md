# Phase 3 - Polygon statistics and heatmaps

Dependency: Phases 0-1; coordinate snapshot fields with Phase 2. Nutrient datasets are not needed for available non-nutrient layers.

## Problem and intended behavior

Nine sample points and sample-centered rectangles do not establish complete polygon statistics or clipped spatial layers. Provide the documented spatial analysis at each source's actual resolution without inventing finer detail.

## Implementation tasks

- Add a polygon/raster processing path for supported environmental layers with explicit CRS, scale, projection, represented dates, masks, geometry intersection and reducer definitions.
- Calculate supported minimum, maximum, mean, median, standard deviation and valid-data count/coverage. Define area-weighted versus pixel-count coverage, edge-pixel handling and standard-deviation convention. Report unavailable statistics where the source is a point product rather than fabricate raster coverage.
- Keep these zonal statistics separate from the existing sample-based model ranking. Preserve sampled inference inputs and averaging semantics until a separately validated model change is approved.
- Clip rendered/exported cells or raster tiles to the actual farm geometry. Include missing/masked areas rather than fill them with zeros or nearby values.
- Provide layer legends with variable, units, class ranges, interpretation, source, period, native/effective resolution and no-data category. Descriptive high/low colors must not imply agronomic suitability.
- Persist sufficient geometry, layer metadata, statistics and durable reproduction inputs for reopening/export; handle expiring map URLs without presenting a newly retrieved date as the original saved observation.
- Bound geometry size, resolution, provider calls and output size. Use jobs/caching where needed rather than block ordinary screens indefinitely.

## Likely files

Environmental retrieval/reducers, `backend/fastapi_app.py`, `backend/environmental_pipeline.py`, saved snapshot handling, mobile `lib/screens/map_screen.dart`, analyst map/workbench and report consumers.

## Acceptance

Compare a small known raster and polygon against an independent calculation/GIS reference, not the same reducer under test. Cover irregular boundaries, small parcels relative to coarse pixels, partial/no coverage, nodata and constant-valued layers. Verify count, statistics and coverage definitions. Visually check clipping, legend, zoom and exports on Android/web. Confirm model rankings remain unchanged for unchanged recorded model inputs.

Complete when supported spatial claims have independent evidence, displayed layers stay within the parcel, and missing/coarse data are accurately represented. Any remaining sampling approximation needs its own label and documented scope decision.
