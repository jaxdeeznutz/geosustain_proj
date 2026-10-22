# Production crop model release audit — 2026-10-22

## Outcome and root cause

Version before and after this work is the same:

`6dee915ad58e55e376bcfb5a74ecee9db086491cf5fe29a1b3149f5b45be9278`

This is the SHA-256 of the existing 37,233,297-byte `backend/crop_model.pkl`.
The pickle, feature pickle and datasets were **not replaced or retrained**.
Training was attempted and correctly blocked by the existing climate provenance
guard. No new production artifact or evaluation metrics are claimed.

Evidence:

- Current training code filters to the approved 13 labels. The saved forest
  contains 17 classes, including `blackgram`, `mango`, `mungbean`, `pigeonpeas`.
  It therefore does not reflect the current class-filtering pipeline. Its exact
  historical training script, source data hash, timestamp and evaluation are
  unavailable. File dates cannot establish these facts.
- Training previously read/wrote filenames relative to the shell's working
  directory; inference loads assets relative to `backend/rainfallDatasets.py`.
  A run elsewhere could produce files outside the directory inference uses.
- Inference already calculated a SHA-256 when importing the pickle, but `/health`
  only exposed the application revision. A Git revision does not identify which
  model is in memory. Changing a file does not reload a running worker.
- Both Render builds install requirements; they do not train a model. Artifact
  changes must be included in a release and workers restarted.
- History restores `analysis_sessions.result_snapshot`. Retrying a completed
  mobile analysis with the same idempotency/request key also restores the saved
  result before inference. These are intentionally immutable snapshots.

The current approved class names remain unchanged. `maize` is the model label
for the existing Corn display name. Ranking continues to filter to the approved
catalog without renormalizing class scores. Random Forest remains production;
Decision Tree and scaled SVM comparisons remain on the same existing split.

## Training → saving → loading → versioning

Run from the repository root using the existing local Python tool:

```powershell
.\.tools\python\python.exe backend/training/train_model.py
```

In a normal installed Python environment, the equivalent command is:

```text
python backend/training/train_model.py
```

Paths now resolve to `backend/` from any working directory. The seed (42),
profiles, sampling, balancing, Random Forest parameters and comparison models
are unchanged. The training-period guard runs before reading/augmenting data
or publishing assets. The current command exits nonzero with:

```text
Climate training contract unresolved: Crop_recommendation.csv rainfall period None;
inference expects rolling_30_days.
```

The CSV's rainfall/temperature/humidity periods are undocumented. Local synthetic
rainfall is described as rolling 30 days, while local temperature/humidity periods
are unspecified. Inference expects rolling 30-day rainfall, annual mean air
temperature and current humidity. Supply documented compatible training data and
review the source/inference contracts before retraining. Do not bypass the guard,
infer periods from numeric ranges, relabel the existing data, or manufacture a
conversion. See [CLIMATE_VARIABLE_CONTRACT.md](CLIMATE_VARIABLE_CONTRACT.md).

Once the provenance issue is resolved, a successful run stages and validates:

1. `crop_model.pkl` — fitted RandomForestClassifier.
2. `crop_model_features.pkl` — ordered feature list.
3. `crop_model_metadata.json` — schema, exact artifact SHA-256, classes/order,
   UTC training completion timestamp, seed, script/dataset/climate-contract hashes,
   scikit-learn version, forest parameters, provenance and evaluation metrics.
4. `model_comparison_report.json` — RF/DT/SVM metrics bound to the artifact version.
5. `Crop_recommendation_with_gis.csv` — augmented data used by this run.

The staged model is actually reloaded with its feature file and metadata before
publication. Publication uses individual file replacements, not an atomic release
of the entire directory: stop training against a directory used by starting
workers, and deploy all files together. Mixed artifact/metadata releases fail
validation. Workers do not hot reload.

Metadata timestamps are separate from the pickle identity. Metadata-only edits
do not claim a new model. Any change to the deployed pickle bytes changes its
version. The current manifest is an honest legacy audit: unknown fields are null,
`training.status=legacy_unverified`, and seed 42 is read from the existing forest.
It does not associate the current training script or data with the old artifact.

## Verify and restart/redeploy

Read-only verification loads the same artifacts as inference, without database or
environmental-provider initialization:

```powershell
.\.tools\python\python.exe backend/verify_model.py --expected-version 6dee915ad58e55e376bcfb5a74ecee9db086491cf5fe29a1b3149f5b45be9278
```

This passed locally. For future newly trained releases, also use
`--require-training-metadata`; that option deliberately rejects today's legacy
manifest. Missing metadata without strict mode remains readable for legacy
releases with `metadata_status=missing_legacy`. Present but missing/wrong version,
feature order, or classes fails validation rather than silently downgrading.

To release this change:

1. Include the code and current legacy metadata manifest in the deployment.
   No database migration, Flutter change or retrain is needed for diagnostics.
2. Set `GEOSUSTAIN_EXPECTED_MODEL_VERSION` on Render to the exact version above.
   For a future approved retrain, update this pin to the newly printed SHA-256
   together with that release's model, feature file, metadata and comparison report.
   A stale artifact with its own matching old metadata is detectable only against
   an independently specified expected version.
3. Redeploy/restart **all** Uvicorn workers. Both Render YAML variants now run
   `python verify_model.py` before starting Uvicorn. If Render uses a manually
   configured start command, apply the matching command from the YAML. No training
   runs during startup. For a local backend restart:

   ```text
   python -m uvicorn fastapi_app:app --app-dir backend --host 0.0.0.0 --port 8000
   ```

4. Read `/health` or `/api/health`. Verify `revision` is the intended code release,
   `model.model_version` equals the intended model SHA-256,
   `model.artifact_version_on_disk` matches it, and `model.restart_required=false`.
   Health also exposes `feature_contract`, all artifact `classes`, approved
   `supported_classes`, `approved_classes`, training metadata and warnings.
   In-memory/disk disagreement reports `model.status=stale` and outer
   `status=degraded`. Loading failure reports `unavailable` with no invented version.
   HTTP 200 still means the service is reachable; inspect the JSON status fields.
5. Submit a **new** analysis and compare its `model_version` and
   `model_explanation.model_version` with health. A changed model need not change
   the winning crop for every parcel; compare versions before inferring staleness.

Local FastAPI TestClient verification proved both health routes and an actual
forest inference snapshot use the repository artifact's exact SHA-256. The public
`https://geosustain.onrender.com/health` was inaccessible through the available web
tool during this audit. No deployment was performed and the remote artifact
version is unverified; local proof is not proof of the remote worker's state.

## Regression verification

```powershell
.\.tools\python\python.exe -m pytest backend/tests -q -p no:cacheprovider --basetemp=.tools/pytest-model-version-all
.\.tools\python\python.exe -m ruff check backend/model_artifacts.py backend/verify_model.py backend/training/train_model.py backend/tests/test_model_artifacts.py backend/rainfallDatasets.py backend/fastapi_app.py --select F
git diff --check
```

Results: **224 passed**, including **19 new artifact/version test cases**; three
existing FastAPI/Starlette deprecation warnings. Changed-file lint and diff checks
passed. Repository-wide `ruff check backend --select F` still finds nine unrelated
fixture-import findings in untouched tests; they were not changed for this task.

New tests cover feature-order mismatches in the estimator, feature file and JSON;
missing version metadata and explicit legacy compatibility; stale metadata;
expected-version mismatches; old in-memory workers after file replacement; fresh
loading after replacement; staged-validation failure preserving existing files;
rejecting comparison estimators as production; real backend health/inference
identity; snapshot version immutability; safe training-guard failure; and CLI
verification outside the repository working directory. Tiny forests exist only
in temporary test fixtures and never replace production artifacts.

## Saved analyses and remaining limitations

No old analysis must be rerun just to remain readable. To obtain recommendations
from a future new model, every desired old analysis must be submitted as a **new
analysis with a new request/idempotency key** after deployment. Opening history,
saved reports, or retrying an old completed request does not update its snapshot.
Older snapshots without version metadata cannot be assigned a model retrospectively.

Today's model version and predictions are preserved, so rerunning today does not
apply profile changes or repair unknown training provenance. New diagnostics
identify the artifact; they do not establish agronomic validity. N/P/K physical
units and methods remain unverified, GIS/local rows are synthetic proxies, and
CAGRO historical evidence is not forced into the model. Existing evaluation
balances before splitting, so resampled duplicates may cross the split and its
held-out classification metrics are not independent field validation. No model
class score is accuracy, certainty, harvest probability or measured land suitability.
