# Land-cover regression and guard

Cause: the active environmental_pipeline bypassed rainfallDatasets.classify_land, while attach_model_ranking marked positive model scores as crop recommendations. The old NDVI thresholds did not reliably distinguish buildings, bare fields and water, so they are not reinstated as ground truth.

The request now screens the entire normalized polygon (or a 20 m buffer for a point) with GOOGLE/DYNAMICWORLD/V1, at 10 m resolution. Latest cloud-masked observations within 90 days are mosaicked and pixel-area weighted. Water and built classes require >=0.6 top class confidence. Application safeguards: >=50% water/built generates an advisory; >=10% combined means refine the mixed boundary; <80% confident coverage means unknown and withholds crops. These are conservative product policy thresholds, not locally validated agronomic limits. Bare soil is not automatically called buildings; flooded vegetation is not automatically open water. Small buildings, cloud gaps and recent changes remain limitations.

Blocked/unknown areas bypass crop inference and save an advisory with empty rankings and null scores. Provider errors return a retryable failure rather than recommend crops. Eligible land still uses the existing soil, rainfall, humidity, vegetation, elevation, slope and Random Forest pipeline. Whole-boundary screening adds one GEE evaluation; clearly blocked land avoids the remaining model/environment requests. No soil dataset or retraining changes.

The mobile result view displays the advisory and mapped water/building fractions instead of crop-score cards. Previously saved analyses are unchanged: reanalyze old records. Deploy both backend and frontend. Live GEE results for the user's specific outline have not been verified.

Source and attribution: https://developers.google.com/earth-engine/datasets/catalog/GOOGLE_DYNAMICWORLD_V1 . Dynamic World Project by Google in partnership with National Geographic Society and the World Resources Institute; modified Copernicus Sentinel data; CC-BY 4.0.
