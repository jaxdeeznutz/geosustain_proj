"""Never allow an offline test to fall through to a real database."""

import sys
from pathlib import Path
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import database
from contextlib import nullcontext
from fastapi.testclient import TestClient


@pytest.fixture
def client(monkeypatch):
    import fastapi_app as api
    monkeypatch.setattr(api, 'init_db', lambda: None)
    monkeypatch.setattr(api, 'analysis_request_lock', lambda *args: nullcontext(True))
    api.app.dependency_overrides[api.get_api_user] = lambda: {
        'id': 10, 'role': 'farmer', 'is_active': True}
    with TestClient(api.app) as instance:
        yield instance
    api.app.dependency_overrides.clear()


@pytest.fixture(autouse=True)
def forbid_live_database(monkeypatch):
    import qa_closure
    monkeypatch.setattr(qa_closure, 'consume_quota', lambda *args, **kwargs: 0)
    def blocked():
        raise AssertionError("Test attempted an unmocked database connection")

    monkeypatch.setattr(database, "get_conn", blocked)
    monkeypatch.setattr(database, 'start_session', lambda *args: None)


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
