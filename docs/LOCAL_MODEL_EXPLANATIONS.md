# Saved Explainable AI

New model-probability analyses save signed, crop-specific contributions from the
unchanged random forest. The farmer Overview, Key Factors and crop details expose
the Explainable AI panel; the analyst uses the same saved analysis component.
Both report builders use the same validated snapshot and PDF component.

## Method and output

`random_forest_tree_path_probability`, version `rf-path-probability-v1`, is an
additive tree-path class-probability decomposition. It is **not SHAP**. For each
tree, normalize its stored class vector at every node. Start at the root and
allocate each traversed child-minus-parent class-distribution change to the
feature used for that split. Repeated splits on a feature accumulate. Average
the roots, feature allocations and leaf distributions over all trees.

For class k and original sample x:

`score_k(x) = mean_tree(root_k) + sum_feature(contribution_k,feature(x))`.

The baseline is the mean stored weighted training-root distribution. It is not
a field suitability reference or a separately sampled background expectation.
Routing uses float32 input values, matching sklearn prediction behavior, while
the original float64 input values remain saved and hashed. Class positions come
from `classes_`; feature positions come from `feature_names_in_`. Every class
must reconstruct actual `predict_proba` output within absolute probability
tolerance `1e-9` (display tolerance `0.0000001` percentage points).

For parcels, average contributions from exactly the original ranking samples,
using the same arithmetic mean as the class scores. Do not predict on a centroid
or averaged inputs. Input mean/range summaries are descriptions of those samples.
Crop comparison subtracts two saved class baselines/contribution vectors, so the
baseline difference plus feature differences reconstructs their score gap.

The UI displays the three largest absolute contributions and the combined
remainder. Details and exports include every feature. Positive and negative
values raise/lower that class score relative to its baseline. They are signed
percentage points, not percentage changes, recommendations to change an input,
or causal effects. Global impurity importance stays separately labelled
**Overall model factors**; environmental grades and seasonal context remain
separate evidence.

The concise summary states why the selected crop ranks where it does, including
the saved score gap and principal feature differences versus the runner-up (for
first place) or leader. A separate research/reference panel displays compatible
saved growing-condition comparisons and citations. It never changes the ranking
or fills absent criteria. Desktop shows these panels side by side; narrow screens
and large text stack them. Technical details and both exports retain every factor.
See the [Phase 7 research alignment](../defense-evidence/capstone-fix-execution/phase-07/RESEARCH_ALIGNMENT.md)
for requirement mapping, source checks and pending acceptance.

This method follows the path decomposition described by [Palczewska et al.,
Interpreting random forest classification models](https://arxiv.org/abs/1312.1121)
and the [treeinterpreter implementation](https://github.com/andosa/treeinterpreter).
The [sklearn RandomForestClassifier contract](https://scikit-learn.org/1.8/modules/generated/sklearn.ensemble.RandomForestClassifier.html)
defines class order, float32 routing and mean tree probabilities. No external
explainer package is required.

## Persistence and validation

The existing analysis JSON stores `local_model_explanation` and each original
sample's `local_attribution` inside `model_explanation`. No schema migration is
needed. The snapshot records method/version, model SHA-256, analysis context ID,
input snapshot hash, feature/class order, active crop-to-class binding, original
inputs, base/contribution/score arrays, aggregation and limitations.

Python and Dart compute the same integrity checksums using domain UTF-8 bytes,
a zero separator, sorted compact UTF-8 JSON metadata, a zero separator and
big-endian IEEE float64 numeric values. This avoids language-specific JSON
exponent formatting. Checksums detect mismatched context/content; they are not
authentication signatures. The client checks every sample, aggregate,
crop-class binding and final score before displaying signed factors.

Historical records without matching local snapshots show explanation
unavailable. They are not explained using today's model. Legacy blended scores
are not represented as raw model-probability explanations. Missing, incompatible
or failed attributions show unavailable and leave crop results untouched.

## Bounds and limitations

Preparation caches one immutable model/version, normalizes node distributions
once, and bounds forest size to 1,000 trees, 300,000 nodes and 5,000,000 class
values. Paths are bounded to 50,000 node visits per sample. The exact-input LRU
retains at most 128 deep-copied results and rechecks the supplied source score
on a hit. A parcel accepts at most 64 samples; contracts bound 32 features and
64 classes. Cache changes are not persisted as inference metadata.

The local nine-sample benchmark recorded about 0.340 seconds cold and 0.0026
seconds warm; normalized node vectors use 25,140,416 bytes. See Phase 5
`runtime-memory.json` for the exact machine/run result. These are local timings,
not a production capacity guarantee.

Path allocation depends on split order and correlated inputs and has no causal
or Shapley consistency guarantee. The legacy training data include synthetic
GIS/local rows; field validation remains unresolved. N/P/K inputs remain
estimates/proxies with unresolved physical-unit compatibility. Scores are
uncalibrated model class scores, not harvest probabilities, nutrient measurements,
fertilizer advice or proof of crop success. A Phase 8 model/input replacement
requires repeating attribution, performance, persistence, UI and export checks.

## Local acceptance commands

Run `deployment/verify-phase-05.ps1` for offline dependency resolution, analyzer,
the full Flutter suite and web build. Report test artifacts are written under
`build/phase-05/export-qa`. Run
`.tools/python/python.exe backend/tests/phase05_manual_host.py` for the isolated
synthetic UI lab, after stopping the earlier lab host. It verifies the disposable
database directory before creating a temporary schema, denies external backend
HTTP/mail/push, uses the actual existing forest, and cleans only its schema on
exit. `--smoke` exercises SQL/API preservation and failure behavior.
