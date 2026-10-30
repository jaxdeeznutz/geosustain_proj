# Humidity and NDVI application screening

New analyses save `application_screening` (`application-screening-v1`) independently
of documented reference assessments and the Random Forest snapshot. The client
displays these checks as **Application screening**. They do not affect crop scores,
rank order, authentication, CAGRO configuration, or the model input formulas.

Only current humidity (`%`, `current`) and NDVI (`index`, `latest_scene`) use the
existing heuristic tuples in `rainfallDatasets.CROP_ENV_PROFILES`. Preferred bounds
are Suitable, accepted bounds outside preferred are Limited, and values outside
accepted bounds are Not suitable. All endpoints are inclusive. NDVI describes
vegetation condition, not proof that the recommended crop is suitable; current
humidity is not a long-term climate average. These are application heuristics,
not validated agronomic criteria.

Each check saves its observation, preferred/accepted bounds, source, profile key,
interpretation and status. Banana uses the original catalog mapping to
`banana (cavendish/lakatan)`, visibly disclosed in its interpretation. Mango has no
legacy profile and remains Not assessed. Missing, nonfinite, physically invalid,
fallback, or incompatible-period/unit observations also remain Not assessed.
Polygon checks use the existing complete-sample aggregate measurements.

NPK estimates remain displayed and Not assessed. Other factors retain their
documented assessments. Existing saved records are not rewritten or newly graded.
Deploy the backend and rebuild the Flutter client, then run a new analysis to
see these checks. No database migration or model retraining is required.
