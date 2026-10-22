# Backend

The active entry point is fastapi_app:app. See ../README.md for environment setup, run commands and tests. The model requires scikit-learn 1.8.0, pinned in requirements.txt. app.py is the retained legacy Flask application and uses requirements-legacy.txt.

Model release commands, health fields, the blocked retraining attempt, and saved-analysis behavior are documented in [MODEL_VERSIONING.md](../docs/MODEL_VERSIONING.md).
