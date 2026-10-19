"""Never allow an offline test to fall through to a real database."""

import sys
from pathlib import Path
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import database


@pytest.fixture(autouse=True)
def forbid_live_database(monkeypatch):
    def blocked():
        raise AssertionError("Test attempted an unmocked database connection")

    monkeypatch.setattr(database, "get_conn", blocked)


@pytest.fixture(autouse=True)
def reset_auth_throttle():
    from fastapi_app import app
    from auth_security import AuthSecurityMiddleware
    stack = app.middleware_stack
    while stack is not None:
        if isinstance(stack, AuthSecurityMiddleware):
            stack.attempts.clear()
        stack = getattr(stack, 'app', None)


@pytest.fixture(autouse=True)
def offline_land_cover(monkeypatch):
    import fastapi_app
    monkeypatch.setattr(fastapi_app, 'screen_land_cover', lambda *args: {
        'allow_crops': True, 'status': 'eligible', 'source': 'offline test fixture'})
