"""Explicit local PostgreSQL integration check in a disposable isolated schema.
Run from project root: python backend/tests/integration_postgres.py
Uses configured DATABASE_URL only when hostname is local; no existing data touched.
External analysis providers are stubbed; model inference is tested separately.
"""

import sys
import uuid
from pathlib import Path
from urllib.parse import urlparse
from unittest.mock import patch
import psycopg2
from psycopg2 import sql
from psycopg2.extras import RealDictCursor
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import database as db
import fastapi_app as api
from geometry import normalize_polygon, polygon_area_m2


def run():
    if urlparse(db.DATABASE_URL).hostname not in ("localhost", "127.0.0.1", "::1"):
        raise RuntimeError("Integration tests require a local PostgreSQL target.")
    schema = "geo_mobile_test_" + uuid.uuid4().hex
    admin = psycopg2.connect(db.DATABASE_URL)
    admin.autocommit = True
    with admin.cursor() as cur:
        cur.execute(sql.SQL("CREATE SCHEMA {}").format(sql.Identifier(schema)))

    def isolated_connection():
        return psycopg2.connect(
            db.DATABASE_URL,
            cursor_factory=RealDictCursor,
            options=f"-c search_path={schema}",
        )

    ring = normalize_polygon(
        [
            {"lat": 7.29, "lng": 125.62},
            {"lat": 7.29, "lng": 125.621},
            {"lat": 7.291, "lng": 125.621},
            {"lat": 7.291, "lng": 125.62},
        ]
    )

    def analyze(body):
        boundary = normalize_polygon(body["polygon"])
        return {
            "lat": 7.2905,
            "lon": 125.6205,
            "selected_polygon": boundary,
            "area_m2": polygon_area_m2(boundary),
            "area_hectares": polygon_area_m2(boundary) / 10000,
            "predicted_crop": "cacao",
            "crop_compatibility_pct": 71,
            "xai_explanation": {"summary": "Fixture explanation"},
            "top_crop_recommendations": [{"crop": "cacao", "compatibility_pct": 71}],
            "analysis_summary": "Integration fixture result",
            "place_name": body.get("place_name"),
        }, "selected-polygon"

    try:
        with (
            patch.object(db, "get_conn", isolated_connection),
            patch.object(
                api, "build_analysis_result", side_effect=lambda body: analyze(body)
            ),
        ):
            with TestClient(api.app) as client:
                db.init_db()  # additive migration must be repeatable
                # Reproduce imported rows whose explicit IDs did not advance SERIAL.
                with isolated_connection() as conn:
                    with conn.cursor() as cur:
                        cur.execute(
                            "INSERT INTO users (id,username,email,password_hash) VALUES (1,'Imported Farmer','imported@example.com',%s)",
                            (api.hash_password("imported-password"),),
                        )
                signup = {
                    "username": "Fixture Farmer",
                    "email": " FARMER@example.com ",
                    "password": "fixture-password",
                    "role": "super_admin",
                }
                created = client.post("/api/mobile/register", json=signup)
                assert created.status_code == 201, created.text
                assert db.get_user_by_id(1)["email"] == "imported@example.com"
                assert db.get_user_by_email("farmer@example.com")["id"] > 1
                print(
                    "PASS registration recovers an out-of-sync user ID sequence without replacing imported users"
                )
                assert (
                    client.post("/api/mobile/register", json=signup).status_code == 409
                )
                login = client.post(
                    "/api/mobile/login",
                    json={
                        "email": "farmer@example.com",
                        "password": "fixture-password",
                    },
                )
                assert login.status_code == 200, login.text
                assert login.json()["user"]["role"] == "farmer"
                token = login.json()["token"]
                headers = {"Authorization": "Bearer " + token}
                assert client.get("/api/mobile/me", headers=headers).status_code == 200
                print(
                    "PASS register/login/duplicate signup/farmer role/session restore"
                )
                farm_body = {
                    "farm_name": "Fixture Farm",
                    "polygon": ring,
                    "mapping_method": "gps_walk",
                    "gps_accuracy_m": 5,
                }
                farm = client.post(
                    "/api/mobile/farms",
                    json=farm_body,
                    headers={**headers, "Idempotency-Key": "farm-one"},
                )
                assert farm.status_code == 201, farm.text
                fid = farm.json()["farm"]["id"]
                retry = client.post(
                    "/api/mobile/farms",
                    json=farm_body,
                    headers={**headers, "Idempotency-Key": "farm-one"},
                )
                assert retry.json()["farm"]["id"] == fid
                assert (
                    len(
                        client.get("/api/mobile/farms", headers=headers).json()["farms"]
                    )
                    == 1
                )
                assert (
                    client.get("/api/planner/queue", headers=headers).status_code == 403
                )
                print("PASS GPS farm save/retry/analyst access restriction")
                payload = {
                    "farm_id": fid,
                    "polygon": ring,
                    "intended_planting_month": 10,
                }
                uid = db.get_user_by_email('farmer@example.com')['id']
                assert client.get('/api/mobile/history', headers=headers).json()['history'] == []
                with db.analysis_request_lock(uid, 'analysis-one') as acquired:
                    assert acquired
                    assert client.get('/api/mobile/analysis-requests/analysis-one', headers=headers).json()['status'] == 'processing'
                    busy = client.post('/api/mobile/analysis', json=payload, headers={**headers, 'Idempotency-Key':'analysis-one'})
                    assert busy.status_code == 202
                    assert db.get_user_history(uid) == []
                assert client.get('/api/mobile/analysis-requests/analysis-one', headers=headers).json()['status'] == 'not_found'
                print('PASS in-flight PostgreSQL lock/recovery status/no duplicate inference')
                result = client.post(
                    "/api/mobile/analysis",
                    json=payload,
                    headers={**headers, "Idempotency-Key": "analysis-one"},
                )
                assert result.status_code == 200, result.text
                sid = result.json()["session_id"]
                status = client.get('/api/mobile/analysis-requests/analysis-one', headers=headers).json()
                assert status['status'] == 'completed' and status['analysis']['session_id'] == sid
                assert status['analysis']['owner_id'] == uid
                assert status['analysis']['owner_display_name'] == 'Fixture Farmer'
                empty_farm = db.create_farm_parcel(uid, 'Empty farm', ring, location_name='Panabo', mapping_method='manual_draw')
                empty_id = empty_farm['id']
                assert client.get(f'/api/mobile/history?farm_id={empty_id}', headers=headers).json()['history'] == []
                scoped = client.get(f'/api/mobile/history?farm_id={fid}', headers=headers).json()['history']
                assert len(scoped) == 1 and scoped[0]['farm_id'] == fid
                print('PASS farm-specific history/verified owner identity/empty farm stays unanalyzed')
                assert result.json()["verification_status"] == "draft"
                again = client.post(
                    "/api/mobile/analysis",
                    json=payload,
                    headers={**headers, "Idempotency-Key": "analysis-one"},
                )
                assert again.json()["session_id"] == sid
                persisted = client.get(
                    f"/api/mobile/analyses/{sid}", headers=headers
                ).json()["analysis"]
                assert persisted["xai_explanation"]["summary"] == "Fixture explanation"
                assert persisted["selected_polygon"] == ring
                print("PASS analysis persistence/retry/exact polygon and XAI snapshot")
                for _ in range(2):
                    assert (
                        client.post(
                            "/api/mobile/submit-to-planner",
                            json={"session_id": sid},
                            headers=headers,
                        ).status_code
                        == 200
                    )
                reviewer = db.create_user(
                    "Fixture Analyst",
                    "analyst@example.com",
                    api.hash_password("reviewer-password"),
                    "agricultural_planning_analyst",
                )
                reviewer = db.get_user_by_id(reviewer["id"])
                rh = {"Authorization": "Bearer " + api.generate_mobile_token(reviewer)}
                queue = client.get("/api/planner/queue", headers=rh).json()["queue"]
                assert len(queue) == 1 and queue[0]["session_id"] == sid
                decision = client.post(
                    "/api/planner/verify",
                    headers=rh,
                    json={
                        "session_id": sid,
                        "status": "verified",
                        "notes": "Fixture field review",
                    },
                )
                assert decision.status_code == 200, decision.text
                history = client.get("/api/mobile/history", headers=headers).json()[
                    "history"
                ]
                assert history[0]["verification_status"] == "verified"
                assert history[0]["planner_notes"] == "Fixture field review"
                assert history[0]["verified_at"]
                print(
                    "PASS submission/analyst queue/decision/feedback returned to farmer"
                )
                new_ring = normalize_polygon(
                    [{"lat": p["lat"] + 0.0001, "lng": p["lng"]} for p in ring]
                )
                edit = client.patch(
                    f"/api/mobile/farms/{fid}",
                    headers=headers,
                    json={"polygon": new_ring},
                )
                assert edit.status_code == 200, edit.text
                old = client.get(f"/api/mobile/analyses/{sid}", headers=headers).json()[
                    "analysis"
                ]
                assert (
                    old["selected_polygon"] == ring
                    and old["verification_status"] == "verified"
                )
                reanalysis = client.post(
                    "/api/mobile/analysis",
                    headers={**headers, "Idempotency-Key": "analysis-two"},
                    json={"farm_id": fid, "polygon": new_ring},
                )
                assert reanalysis.status_code == 200, reanalysis.text
                assert reanalysis.json()["verification_status"] == "draft"
                assert reanalysis.json()["session_id"] != sid
                assert reanalysis.json()["boundary_version"] == 2
                print(
                    "PASS boundary version/history preservation/reanalysis starts unsubmitted"
                )
                other = db.create_user(
                    "Other Farmer",
                    "other@example.com",
                    api.hash_password("other-password"),
                    "farmer",
                )
                oh = {"Authorization": "Bearer " + api.generate_mobile_token(other)}
                assert (
                    client.get(f"/api/mobile/farms/{fid}", headers=oh).status_code
                    == 404
                )
                assert (
                    client.get(f"/api/mobile/analyses/{sid}", headers=oh).status_code
                    == 404
                )
                assert (
                    client.post(
                        "/api/mobile/analysis",
                        headers=oh,
                        json={"farm_id": fid, "polygon": ring},
                    ).status_code
                    == 404
                )
                assert (
                    client.post(
                        "/api/mobile/submit-to-planner",
                        headers=oh,
                        json={"session_id": sid},
                    ).status_code
                    == 404
                )
                assert client.get('/api/mobile/analysis-requests/analysis-one', headers=oh).json()['status'] == 'not_found'
                assert client.get(f'/api/mobile/history?farm_id={fid}', headers=oh).status_code == 404
                change = client.post(
                    "/api/mobile/change-password",
                    headers=headers,
                    json={
                        "current_password": "fixture-password",
                        "new_password": "fixture-new-password",
                    },
                )
                assert change.status_code == 200, change.text
                assert client.get("/api/mobile/me", headers=headers).status_code == 401
                assert (
                    client.get(
                        "/api/mobile/me",
                        headers={"Authorization": "Bearer " + change.json()["token"]},
                    ).status_code
                    == 200
                )
                assert (
                    client.post(
                        "/api/mobile/login",
                        json={
                            "email": "farmer@example.com",
                            "password": "fixture-new-password",
                        },
                    ).status_code
                    == 200
                )
                print("PASS ownership/password change/old session revocation")
    finally:
        with admin.cursor() as cur:
            cur.execute(
                sql.SQL("DROP SCHEMA {} CASCADE").format(sql.Identifier(schema))
            )
        admin.close()
        print("Disposable test schema removed; original records unchanged.")


if __name__ == "__main__":
    run()
