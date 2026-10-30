# Phase 5 - Individual prediction explanations

Dependency: Phase 4 model/input audit and current ranking contract. New nutrient datasets are not needed to implement explanations of the existing model, whose scientific limitations must remain visible.

## Implementation tasks

- Select and verify a compatible local attribution method for the exact deployed model/output. Do not relabel global impurity importance as local, signed or crop-specific evidence.
- Explain the selected crop's actual uncalibrated class score, with the correct class index, expected/base output, contribution units and feature order. Explicitly handle different explainer/library output shapes.
- For polygons, preserve per-sample class attributions and combine only compatible contributions using the same arithmetic mean used for the final class probability. Do not explain a new centroid prediction as though it were the aggregated parcel score.
- Include alternative-crop comparison where supported. Distinguish model contributions from separate documented factor grades, heuristic checks and seasonal evidence.
- Save method/version, model hash, input hash, crop class, base value, contributions and aggregation with the analysis. Do not substitute current global settings into old explanations.
- Present understandable supporting/limiting contributions with limits: attribution describes model behavior, not causal crop success or proof that estimated NPK was measured.
- On explainer failure, expose an unavailable explanation without fabricated bars or positive/negative text. Assess runtime/memory and cache exact-context results where justified.

## Likely files

`backend/model_explainability.py`, ranking/pipeline integration, dependency constraints as necessary, `lib/screens/analysis_explanation.dart`, crop sheets, analyst workbench/reports and saved fixtures.

## Acceptance

Verify base value plus signed contributions reconstructs the explained class score within a recorded tolerance. Test class/output mapping, multiple samples, missing attribution and model/input/context mismatch. Check that ranking scores are unchanged and saved/reopened/exported explanations match. Visually inspect a representative farmer and analyst explanation.

Implementation may be complete for the legacy artifact while its agricultural validity remains unresolved. Any Phase 8 model/input change requires affected attribution and performance validation again before final release.
