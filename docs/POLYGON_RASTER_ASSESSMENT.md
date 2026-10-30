# Saved polygon raster assessment

Phase 3 completed for local synthetic workflow scope and owner accepted on 29 October 2026. Client, map and report checks passed; live-provider and field validity are not claimed. Version: `polygon-raster-v1`.

## Scope and separation

Formal saved-farm results receive `spatial_assessment` alongside the existing nine model samples. Raster statistics never replace model inputs or change model scores, crop ordering, NPK estimates, annual factor grades or seasonal context. Point results receive an explicit not-applicable snapshot. Historical records without this field are not backfilled with invented rasters. Farmer detail/history, analyst cases and both report builders consume the saved snapshot rather than refreshing it when opened.

The snapshot contains its capture time, geometry hash, layer status, clipped cell fragments, statistics, masks, source collection, period, native projection, analysis projection/transform, scale, units and limitations. It stores pixel values and vectors rather than expiring provider URLs. The basemap is current navigation context, not saved observational evidence.

## Geometry, statistics and coverage

The existing exterior-ring farm contract is projected to EPSG:3857. A simple concave ring is triangulated and intersected with explicit rectangular analysis cells. Each fragment is clipped to the actual parcel; bounding-box pixels outside it are excluded. No holes or self-intersecting rings are supported. Optional spatial work is capped at 128 input vertices, 1,024 bounding cells per layer and 4,096 fragments per layer; excess work becomes unavailable without blocking the existing model result.

Each distinct intersecting analysis cell counts once even when it contributes several triangle fragments. Minimum and maximum are valid intersecting-cell extrema. Mean, median and population standard deviation use each cell's intersected projected area as weight. If cumulative weight is exactly half, median is the midpoint of the neighboring values. These are descriptive grid statistics, not field sample estimates or uncertainty intervals. Valid zero remains data; null, nonfinite values, masks and the sentinel are excluded. All masked cells return unavailable statistics, never zero-valued evidence.

Coverage is valid intersected area divided by the full projected parcel area. Grid-extent coverage is also recorded. EPSG:3857 area and ratios are explicitly projected, not geodesic or measured ground area. Native pixel counts are not represented as independent field observations. Nearest-neighbor reprojection uses an analysis ground scale no finer than the source's nominal scale, with latitude correction for the Mercator grid. Reprojection does not add spatial detail.

## Layers and time support

| Layer | Source / nominal support | Processing and mask |
| --- | --- | --- |
| Elevation, slope | USGS SRTMGL1_003, 30 m; acquisition 11-22 February 2000 | Elevation in m; slope percent = tan(terrain slope in degrees) x 100; original mask. |
| NDVI | Sentinel-2 SR Harmonized, 10 m B8/B4 | Latest scene with scene cloud percentage below 20 in the last 548 completed UTC days; explicit scene ID/date; SCL 20 m nearest mask excludes nodata, saturated/defective, shadow, medium/high cloud, cirrus and snow. No scene is an unavailable layer. |
| Soil pH | OpenLandMap v02, 250 m, b0 surface (0 cm) | Catalog scale 0.1; catalog 1950-2018 coverage describes a static model, not an individual pixel's sampling date; original mask. |
| Completed 30-day rainfall | CHIRPS daily, nominal 5,566 m | Sum of 30 complete UTC days, excluding today; all collection dates and per-pixel dates must exist. |
| Annual rainfall reference | CHIRPS daily, nominal 5,566 m | Five complete calendar years, summed and divided by five; missing dates are masked rather than filled. |
| Annual air temperature reference | ERA5-Land daily aggregated, nominal 11,132 m | Five complete calendar years, daily mean averaged; K minus 273.15; complete date and pixel support required. |

Humidity and NPK are not assigned invented raster layers. The existing point/model nutrient estimates remain labeled as estimates. Coarse products may cover a small farm with one source cell and a constant value; that is not evidence of within-farm uniformity.

Provider behavior follows the official [computePixels API](https://developers.google.com/earth-engine/reference/rest/v1/projects.image/computePixels) and [PixelGrid contract](https://developers.google.com/earth-engine/reference/rest/v1/PixelGrid). Source definitions: [Sentinel-2 harmonized](https://developers.google.com/earth-engine/datasets/catalog/COPERNICUS_S2_SR_HARMONIZED), [OpenLandMap pH](https://developers.google.com/earth-engine/datasets/catalog/OpenLandMap_SOL_SOL_PH-H2O_USDA-4C1A2A_M_v02), [SRTM](https://developers.google.com/earth-engine/datasets/catalog/USGS_SRTMGL1_003), [CHIRPS](https://developers.google.com/earth-engine/datasets/catalog/UCSB-CHG_CHIRPS_DAILY), [ERA5-Land](https://developers.google.com/earth-engine/datasets/catalog/ECMWF_ERA5_LAND_DAILY_AGGR).

## Map and exports

Farmer and analyst views offer the same seven saved layers. Blue classes describe lower/middle/higher values relative to the layer's observed min/max, not crop suitability, harvest probability or cross-farm standardized thresholds. Constant values use one neutral blue class. Gray means missing or unevaluated area. Legends expose class bounds and units; source details expose coverage, scale, dates and reducers. Reports use the same persisted clipped fragments in north-up vectors, with the boundary outline and legends. The legacy sample-centered green/red rectangles are removed; model samples remain separate evidence.

## Bounded provider work

The optional adapter reuses configured Earth Engine credentials after existing inference has initialized EE. It does not launch unbounded global discovery on advisory-only paths. Seven layers use at most two simultaneous workers and two REST requests per layer. Connect/read timeouts are 3/8 seconds; metadata is capped at 64 KiB and NPY pixels at 2 MiB. Arrays use `allow_pickle=False` and validate shape, fields and validity masks. A failed or oversized source returns a reason and gray/unavailable coverage. No credentials or access tokens are persisted. An in-process deep-copy cache retains at most 16 geometry/provider/date snapshots (900 seconds for usable data, 60 seconds for unavailable data).

These limits bound individual requests, response sizes and task counts. Socket read timeouts are not a hard whole-analysis wall-clock deadline. No successful real-provider observation has been established in this environment; synthetic lab results validate processing and saved-workflow behavior only.

## Verification

See [Phase 3 evidence](../defense-evidence/capstone-fix-execution/phase-03/README.md) and the [independent arithmetic references](../defense-evidence/capstone-fix-execution/phase-03/REFERENCE_CASES.md). Client checks, generated PDF inspection and the owner Android/web/export journey are recorded in the Phase 3 closure evidence.
