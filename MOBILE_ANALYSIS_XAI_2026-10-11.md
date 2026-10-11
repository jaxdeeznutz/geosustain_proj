# Mobile Analysis and model explanation — 11 October 2026

Implemented in the existing GeoSustain mobile project. No model retraining, scoring changes, historical record updates, database migrations, commits, pushes, or deployments were performed.

## What the project actually implemented

- The deployed artifact is a scikit-learn `RandomForestClassifier`, using the Gini criterion and ten inputs: N, P, K, temperature, humidity, pH, rainfall, NDVI, elevation, and slope.
- The previous `build_xai_explanation` function compared environmental values with configured crop ranges. Despite calling itself a “local feature-contribution explanation,” it did not read model feature importance or compute prediction-specific attribution. No SHAP, LIME, or other local attribution implementation was found in the current code or inspected Git history.
- The forest already exposes native, unsigned, overall mean-decrease-in-impurity importance through `feature_importances_`. That is now read directly from the model artifact. It is labeled **Overall model factors**, never presented as explaining a particular farm or crop. The existing method does not provide positive/negative directions or per-crop contributions.
- This interpretation follows the [scikit-learn 1.8 RandomForestClassifier documentation](https://scikit-learn.org/1.8/modules/generated/sklearn.ensemble.RandomForestClassifier.html). Impurity importance is a training-wide statistic and can favor features with many distinct values.

## Confirmed causes and repairs

1. **Missing crop explanations:** inference returned crop scores but only built condition notes for the winner. The other crop objects lacked the reason fields the mobile UI tried to read. New analyses now save crop-specific comparisons, preferred ranges, measured/scoring values, limitations, score components, and the sampled input identifier for every assessed crop with an existing profile. The UI also explains lower ranks using that crop's saved model/environment scores. Unsupported crops retain an honest unavailable/neutral-component explanation.
2. **Missing model chart:** no model-importance payload or model chart was wired into the old mobile Analysis page. Its Key factors section contained text and an ExpansionTile. The native importance is now captured during inference, serialized through the API, stored in the existing result snapshot, restored on history/detail reads, validated by the frontend, and rendered as labeled bars directly below the top crop. The five leading factors and a plain-language summary are visible; details show every feature and exact importance.
3. **Wrong crop after seasonal ranking:** the seasonal winner could inherit the earlier winner's condition text. The new winner now selects its own saved comparison. The final model snapshot is bound after seasonal ranking to the final output, score, and unique analysis context.
4. **Wrong input scope in polygons:** the old merge copied one sample's notes while averaging environmental measurements. All actual model input/output samples are now retained. Crop comparisons identify the sample used for the displayed ranking; the UI distinguishes these values from average land indicators. It does not run a new model prediction on averaged inputs and pretend that explains the original result.
5. **Rainfall mismatch:** the old explanation compared raw recent rainfall, but the existing crop scorer used a 65% regional baseline / 35% recent-rainfall blend. New condition comparisons expose the actual scoring value and retain the recent 30-day total separately. The existing zero-rainfall fallback behavior is disclosed, not changed.
6. **Cut-off descriptions:** the old main description used `maxLines: 3` and ellipsis with no expansion action. Text is now measured at its actual width and font scale, with working See more / See less controls. Each description expands independently. Scrollable crop/model details sheets have a persistent Close action. Original saved summaries and older condition notes remain readable in details without reinterpreting them as model attribution.
7. **Gray rectangle:** the attachment contains only the written request, not the referenced screenshots. The old Key factors code had no chart/image/loading placeholder that could establish that rectangle's identity. Its original cause remains unconfirmed. The redesigned page and actual-data bar chart were rendered and visually inspected at 360 and 402 px without a gray rectangle or empty fixed-height chart area. Invalid or missing importance produces a compact text state while retaining recorded outputs.

## Provenance and historical safety

- The exact bytes used to load the model are SHA-256 hashed; this identifies the deployed model artifact.
- Inference snapshots retain the feature inputs, raw predicted class, class probabilities, sample identifier, available input quality/source metadata, and native model importance. Polygon analyses retain every inference rather than only the last winner.
- The final snapshot includes the final recommendation, score, saved ranking, input snapshot hash, model version and a unique prediction context. The frontend checks context, model version, selected crop, score, and sample model versions before showing its chart.
- Existing JSONB `result_snapshot` storage already preserves these nested fields. No schema migration is needed. Authentication, ownership, farm/boundary relationships and exact-analysis selection remain unchanged.
- Historical results without a matching versioned snapshot are not re-explained with today's model or inputs. They offer their original saved notes and explain that a new analysis is needed for the new provenance. Historical results are not overwritten.
- Crop growing requirements, model output scores, and overall model feature importance have separate labels. No invented weights, signed effects, confidence percentages, or crop-specific model attributions are used.

## Mobile design

The page follows farm identity/review status, top recommendation, visible model factors, other assessed crops, land conditions, next steps and analyst review. It uses soft green for the top crop, pale blue for model information, amber for supported limitations, separate crop cards, readable text, and large controls. Existing five-tab navigation and review submission remain functional.

“Arable / vegetated” displays as **Land with plants**, reflecting the actual NDVI rule rather than claiming confirmed farmland. Suitability remains attached to its crop. Farmer labels preserve the existing boundaries: good ≥75, possible ≥50, limited ≥25, poor <25. Scores are not described as harvest probabilities. Expansion respects reduced motion by omitting the animation entirely when disabled.

## Validation

- Backend: 54 offline tests passed, including real forest inference, exact native importance values, distinct crop conditions, correct rainfall values, polygon sample retention, seasonal winner changes, historical safety, JSON serialization, SQL snapshot persistence and authenticated history responses.
- Python error/undefined-name checks passed.
- Flutter full suite: 67 tests passed. After the final lower-crop score-context refinement, all 13 affected rendering/explanation checks passed, including the added score-context check. Flutter analyzer reports no issues.
- Final release web build passed with `API_BASE_URL=https://geosustain.onrender.com`; output is `build/web`. No hosted deployment was performed.
- Narrow layouts and chart/details interactions tested at 360 px with text scales 1.0, 1.6 and 2.0. The complete Analysis page at 2.0 text scale keeps the final review control reachable above bottom navigation. Rendering checks also exercise reduced-motion expansion and preserve the selected analysis.
- Three contrasting input sets produce exactly the same raw model predictions, ranked crops, raw scores and display scores as the prior Git HEAD.
- Rendered screenshots use fixed test inputs passed through the actual deployed forest, with real native importance values. They are labeled test data, not measurements from a user's farm.

## Deployment and remaining verification

Deploy the updated Render backend and Flutter frontend together (backend first). Run a new farm analysis to create the new snapshots. Already saved analyses remain available, with honest missing-provenance states where appropriate.

No live Earth Engine request, authenticated deployed farm analysis, production database round trip, or physical phone check was performed. Database round-trip tests use captured SQL parameters and restored snapshots, not a live PostgreSQL service. The original gray rectangle cannot be conclusively diagnosed without its screenshot or runtime error.
