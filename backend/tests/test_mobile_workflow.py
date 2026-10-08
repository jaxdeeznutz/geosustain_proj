"""Offline workflow/security regression tests, no provider requests or live DB."""

from unittest.mock import Mock
import pytest
from fastapi.testclient import TestClient
from test_regressions import api
import database as db
from geometry import normalize_polygon, polygon_area_m2

RING = [
    {"lat": 7.29, "lng": 125.62},
    {"lat": 7.29, "lng": 125.621},
    {"lat": 7.291, "lng": 125.621},
    {"lat": 7.291, "lng": 125.62},
]


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setattr(api, "init_db", lambda: None)
    api.app.dependency_overrides[api.get_api_user] = lambda: {
        "id": 10,
        "role": "farmer",
        "is_active": True,
    }
    with TestClient(api.app) as client:
        yield client
    api.app.dependency_overrides.clear()


def test_closed_geometry_and_invalid_boundaries():
    ring = normalize_polygon(RING)
    assert ring[0] == ring[-1]
    assert 12000 < polygon_area_m2(ring) < 12500
    for points in [
        RING[:2],
        [RING[0]] * 3,
        [RING[0], RING[2], RING[1], RING[3]],
        RING + [{"lat": 0, "lng": 0}],
        RING + [{"lat": float("nan"), "lng": 125.6}],
    ]:
        with pytest.raises(ValueError):
            normalize_polygon(points)


def test_other_users_farm_fails_before_inference(client, monkeypatch):
    monkeypatch.setattr(api, "get_farm_parcel", lambda *args: None)
    build = Mock()
    monkeypatch.setattr(api, "build_analysis_result", build)
    assert (
        client.post(
            "/api/mobile/analysis", json={"farm_id": 99, "polygon": RING}
        ).status_code
        == 404
    )
    build.assert_not_called()


def test_owned_farm_uses_server_boundary_and_new_draft(client, monkeypatch):
    farm = {
        "id": 7,
        "farm_name": "Farm",
        "polygon": RING,
        "boundary_version": 2,
        "is_archived": False,
    }
    monkeypatch.setattr(api, "get_farm_parcel", lambda *args: farm)
    build = Mock(
        return_value=(
            {"lat": 7.29, "lon": 125.62, "selected_polygon": normalize_polygon(RING)},
            "polygon",
        )
    )
    save = Mock(return_value=101)
    monkeypatch.setattr(api, "build_analysis_result", build)
    monkeypatch.setattr(api, "save_analysis_session", save)
    monkeypatch.setattr(
        api,
        "get_user_analysis",
        lambda uid, sid: {
            "session_id": sid,
            "verification_status": "draft",
            "farm_id": 7,
        },
    )
    response = client.post(
        "/api/mobile/analysis", json={"farm_id": 7, "polygon": RING[:3]}
    )
    assert response.status_code == 200
    assert response.json()["verification_status"] == "draft"
    assert build.call_args.kwargs["body"]["polygon"] == RING
    assert save.call_args.args[1]["boundary_version"] == 2


def test_analysis_retry_returns_saved_snapshot_without_inference(client, monkeypatch):
    prior = {"session_id": 50, "verification_status": "pending"}
    monkeypatch.setattr(api, "find_analysis_request", lambda *args: prior)
    build = Mock()
    monkeypatch.setattr(api, "build_analysis_result", build)
    response = client.post(
        "/api/mobile/analysis",
        headers={"Idempotency-Key": "same-key"},
        json={"polygon": RING},
    )
    assert response.json() == prior
    build.assert_not_called()


def test_analysis_key_mismatch_is_conflict(client, monkeypatch):
    monkeypatch.setattr(
        api, "find_analysis_request", Mock(side_effect=ValueError("different inputs"))
    )
    assert (
        client.post(
            "/api/mobile/analysis",
            headers={"Idempotency-Key": "same"},
            json={"polygon": RING},
        ).status_code
        == 409
    )


def test_database_failure_is_not_success(client, monkeypatch):
    import psycopg2

    monkeypatch.setattr(
        api,
        "build_analysis_result",
        lambda **kw: ({"lat": 7.29, "lon": 125.62}, "polygon"),
    )
    monkeypatch.setattr(
        api,
        "save_analysis_session",
        Mock(side_effect=psycopg2.OperationalError("private connection details")),
    )
    response = client.post("/api/mobile/analysis", json={"polygon": RING})
    assert response.status_code == 503
    assert "private connection" not in response.text


def test_exact_analysis_endpoint_is_owned(client, monkeypatch):
    get = Mock(return_value=None)
    monkeypatch.setattr(api, "get_user_analysis", get)
    assert client.get("/api/mobile/analyses/44").status_code == 404
    get.assert_called_once_with(10, 44)


def test_farmer_cannot_decide_review(client):
    assert (
        client.post(
            "/api/planner/verify", json={"session_id": 5, "status": "verified"}
        ).status_code
        == 403
    )


def test_change_password_requires_current_password(client, monkeypatch):
    user = {
        "id": 10,
        "role": "farmer",
        "username": "Farmer",
        "email": "farmer@example.com",
        "password_hash": api.hash_password("old-password"),
    }
    api.app.dependency_overrides[api.get_api_user] = lambda: user
    change = Mock(return_value={**user, "password_version": 1})
    monkeypatch.setattr(api, "change_user_password", change)
    assert (
        client.post(
            "/api/mobile/change-password",
            json={"current_password": "wrong", "new_password": "new-password"},
        ).status_code
        == 400
    )
    change.assert_not_called()
    response = client.post(
        "/api/mobile/change-password",
        json={"current_password": "old-password", "new_password": "new-password"},
    )
    assert response.status_code == 200
    assert response.json()["token"]
    assert api.verify_password("new-password", change.call_args.args[2])


def test_stale_token_and_disabled_account_are_rejected(monkeypatch):
    monkeypatch.setattr(api, "init_db", lambda: None)
    user = {"id": 10, "role": "farmer", "is_active": True, "password_version": 0}
    token = api.generate_mobile_token(user)
    monkeypatch.setattr(
        api, "get_user_by_id", lambda uid: {**user, "password_version": 1}
    )
    with TestClient(api.app) as client:
        assert (
            client.get(
                "/api/mobile/me", headers={"Authorization": "Bearer " + token}
            ).status_code
            == 401
        )
        monkeypatch.setattr(
            api, "get_user_by_id", lambda uid: {**user, "is_active": False}
        )
        assert (
            client.get(
                "/api/mobile/me", headers={"Authorization": "Bearer " + token}
            ).status_code
            == 401
        )


class CaptureCursor:
    def __init__(self, replies):
        self.replies = iter(replies)
        self.queries = []

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def execute(self, query, params=()):
        assert query.count("%s") == len(params), "SQL placeholder/parameter mismatch"
        self.queries.append((query, params))

    def fetchone(self):
        return next(self.replies)


def connection(monkeypatch, replies):
    cursor = CaptureCursor(replies)
    conn = Mock()
    conn.cursor.return_value = cursor
    monkeypatch.setattr(db, "get_conn", lambda: conn)
    return conn, cursor


def test_analysis_insert_all_tables_match_sql_parameters(monkeypatch):
    conn, cur = connection(monkeypatch, [{"id": 42}])
    result = {
        "lat": 7.29,
        "lon": 125.62,
        "selected_polygon": normalize_polygon(RING),
        "xai_explanation": {"summary": "actual"},
    }
    assert db.save_analysis_session(10, result, "polygon") == 42
    assert len(cur.queries) == 4
    assert "result_snapshot" in cur.queries[0][0]
    assert (
        "verification_status" not in cur.queries[0][0]
    )  # Always database default draft.
    conn.commit.assert_called_once()


def test_farm_retry_does_not_insert_another_farm(monkeypatch):
    conn, cur = connection(monkeypatch, [{"id": 5, "request_hash": "digest"}])
    assert (
        db.create_farm_parcel(
            10, "Farm", RING, request_key="key", request_hash="digest"
        )["id"]
        == 5
    )
    assert not any("INSERT INTO farm_parcels" in sql for sql, _ in cur.queries)


def test_submission_retry_preserves_decision(monkeypatch):
    conn, cur = connection(
        monkeypatch, [None, {"id": 42, "verification_status": "verified"}]
    )
    assert db.submit_analysis_to_planner(10, 42)["verification_status"] == "verified"
    assert "verification_status = 'draft'" in cur.queries[0][0]
    assert cur.queries[0][1] == (42, 10, 10)


def test_boundary_edit_never_mutates_history(monkeypatch):
    conn, cur = connection(monkeypatch, [{"id": 5, "boundary_version": 2}])
    db.update_farm_parcel(10, 5, polygon=RING)
    assert all("UPDATE analysis_sessions" not in sql for sql, _ in cur.queries)
    assert "boundary_version=boundary_version+1" in cur.queries[0][0]
    assert cur.queries[0][1][-2:] == [5, 10]
