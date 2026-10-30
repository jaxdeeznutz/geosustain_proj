"""Phase 1 SQL/API journey in defense_integration's verified disposable schema.

Run directly from the repository root. No live provider, email or push delivery.
"""
import json
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import sys
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from defense_integration import isolated, db, api, TestClient
import analysis_jobs
import push_delivery
import operator_workflow as workflow

OUT = Path('defense-evidence/capstone-fix-execution/phase-01')
RING = [{'lat': 7.29, 'lng': 125.62}, {'lat': 7.29, 'lng': 125.621},
        {'lat': 7.291, 'lng': 125.621}, {'lat': 7.291, 'lng': 125.62}]


def run():
    checks = []
    def passed(name):
        checks.append(name)
        print('PASS:', name)

    with isolated() as connect:
        password = api.hash_password('SyntheticOnly!Phase01')
        farmer = db.create_user('Phase01 farmer', 'phase01-owner@example.com', password)
        other = db.create_user('Phase01 other', 'phase01-other@example.com', password)
        analyst = db.create_user('Phase01 analyst', 'phase01-analyst@example.com', password,
                                 role='agricultural_planning_analyst')
        admin = db.create_user('Phase01 admin', 'phase01-admin@example.com', password, role='super_admin')
        farm = db.create_farm_parcel(farmer['id'], 'Phase01 parcel', RING)
        headers = lambda user: {'Authorization': 'Bearer ' + api.generate_mobile_token(user)}
        fh, oh, ah, sh = map(headers, [farmer, other, analyst, admin])
        sequence = 0

        def infer(*, body):
            return {'lat': 7.2905, 'lon': 125.6205,
                    'selected_polygon': body.get('polygon') or [],
                    'nitrogen': 80, 'phosphorus': 47, 'potassium': 50,
                    'predicted_crop': 'Rice', 'crop_compatibility_pct': 65,
                    'top_crop_recommendations': [{'crop': 'Rice', 'compatibility_pct': 65}],
                    'analysis_summary': 'Controlled inference fixture; not provider validation.'}, 'fixture'

        with (patch.object(api, 'init_db', lambda: None),
              patch.object(api, 'build_analysis_result', side_effect=infer),
              patch.object(analysis_jobs, 'enabled', lambda: False),
              patch.object(analysis_jobs, 'start_worker', lambda: None),
              patch.object(push_delivery, 'start_worker', lambda: None),
              TestClient(api.app) as client):
            def analyze(body, who=fh):
                nonlocal sequence
                sequence += 1
                return client.post('/api/mobile/analysis', headers={**who, 'Idempotency-Key': 'phase01-'+str(sequence)}, json=body)

            def formal(version=1):
                response = analyze({'farm_id': farm['id'], 'boundary_version': version})
                assert response.status_code == 200, response.text
                result = response.json()
                assert result['formal_submission_eligible'] is True
                assert result['analysis_scope'] == 'formal_farm_polygon'
                assert (result['nitrogen'], result['phosphorus'], result['potassium']) == (80, 47, 50)
                assert result['crop_compatibility_pct'] == 65
                return result

            def submit(record, who=fh):
                return client.post('/api/mobile/submit-to-planner', headers=who, json={'session_id': record['session_id']})

            first = formal()
            stale = formal()
            assert first['verification_status'] == 'draft'
            with ThreadPoolExecutor(max_workers=2) as pool:
                submitted = list(pool.map(lambda _: db.submit_analysis_to_planner(farmer['id'], first['session_id']), range(2)))
            assert all(row['verification_status'] == 'pending' for row in submitted)
            assert submit(first).status_code == 200
            case = workflow.inbox()['queue'][0]
            case_id = case['case_id']
            assert sum(event['kind'] == 'submitted' for event in workflow.detail(case_id)['events']) == 1
            passed('Owned saved-polygon result stays a draft until deliberate submission; NPK and score unchanged')
            passed('Concurrent first submissions produce one submitted event and one review case')

            for body, scope in [({'lat': 7.29, 'lon': 125.62}, 'preliminary_point_inspection'),
                                ({'polygon': RING}, 'unsaved_polygon_inspection')]:
                response = analyze(body)
                assert response.status_code == 200, response.text
                record = response.json()
                assert record['analysis_scope'] == scope
                assert record['formal_submission_eligible'] is False
                assert submit(record).status_code == 409
            passed('Point and unsaved-polygon inspections are saved honestly and cannot be submitted formally')

            assert submit(first, oh).status_code == 404
            assert client.get(f"/api/mobile/analyses/{first['session_id']}", headers=oh).status_code == 404
            assert analyze({'farm_id': farm['id']}, oh).status_code == 404
            assert analyze({'farm_id': farm['id']}, ah).status_code == 403
            assert analyze({'farm_id': farm['id']}, sh).status_code == 403
            assert client.get('/api/operator/inbox', headers=fh).status_code == 403
            assert client.get('/api/admin/dashboard', headers=ah).status_code == 403
            passed('Cross-user reads/submissions/farm inference and analyst/admin independent inference are denied')

            asked = client.post(f'/api/operator/cases/{case_id}/decision', headers=ah,
                                json={'version': 1, 'status': 'needs_information',
                                      'notes': 'Confirm the changed outline.', 'reason': 'boundary_issue'})
            assert asked.status_code == 200, asked.text
            moved = [{**point, 'lng': point['lng'] + .0001} for point in RING]
            db.update_farm_parcel(farmer['id'], farm['id'], polygon=moved, expected_boundary_version=1)
            assert submit(stale).status_code == 409
            assert analyze({'farm_id': farm['id'], 'boundary_version': 1}).status_code == 409
            assert analyze({'farm_id': farm['id'], 'boundary_version': 2, 'polygon': RING}).status_code == 409
            rejected_revision = client.post(f'/api/mobile/review-cases/{case_id}/resubmit', headers=fh,
                                           json={'version': 2, 'session_id': stale['session_id'], 'notes': 'Stale fixture'})
            assert rejected_revision.status_code == 409
            assert workflow.candidates(case_id, farmer['id']) == []
            passed('Stale initial submission, stale corrected revision and replaced client geometry fail without mutation')

            corrected = formal(2)
            candidates = workflow.candidates(case_id, farmer['id'])
            assert [r['session_id'] for r in candidates] == [corrected['session_id']]
            resubmitted = client.post(f'/api/mobile/review-cases/{case_id}/resubmit', headers=fh,
                                     json={'version': 2, 'session_id': corrected['session_id'], 'notes': 'New saved boundary analysis.'})
            assert resubmitted.status_code == 200, resubmitted.text
            assert len(resubmitted.json()['revisions']) == 2
            decision = {'version': 3, 'status': 'verified', 'notes': 'Reviewed the saved evidence and limitations.',
                        'checklist': {key: True for key in workflow.CHECKS}}
            accepted = client.post(f'/api/operator/cases/{case_id}/decision', headers=ah, json=decision)
            assert accepted.status_code == 200, accepted.text
            owner_record = client.get(f"/api/mobile/analyses/{corrected['session_id']}", headers=fh).json()['analysis']
            assert owner_record['verification_status'] == 'verified'
            assert owner_record['planner_notes'] == decision['notes']
            assert db.get_user_analysis(farmer['id'], first['session_id'])['verification_status'] == 'needs_information'
            assert client.post(f'/api/operator/cases/{case_id}/decision', headers=ah, json=decision).status_code == 409
            before = len(workflow.detail(case_id)['events'])
            assert submit(corrected).json()['submission']['verification_status'] == 'verified'
            assert len(workflow.detail(case_id)['events']) == before
            passed('Request information -> linked current-boundary revision -> verified; farmer notes/status and old revision preserved')
            passed('Submission/decision retries cannot overwrite a decision or repeat review events')

            archived = formal(2)
            db.update_farm_parcel(farmer['id'], farm['id'], is_archived=True, expected_boundary_version=2)
            assert submit(archived).status_code == 409
            assert analyze({'farm_id': farm['id']}).status_code == 404
            assert submit(corrected).json()['submission']['verification_status'] == 'verified'
            passed('Archived farms reject new analysis/submission; historical reviewed retries stay readable')

            with connect() as conn, conn.cursor() as cur:
                cur.execute("INSERT INTO analysis_sessions(user_id,center_lat,center_lon,verification_status,planner_notes) VALUES(%s,7.29,125.62,'verified','Historical note') RETURNING id", (farmer['id'],))
                old = cur.fetchone()['id']
            legacy = client.get(f'/api/mobile/analyses/{old}', headers=fh)
            assert legacy.status_code == 200
            assert legacy.json()['analysis']['planner_notes'] == 'Historical note'
            assert client.post('/api/mobile/submit-to-planner', headers=fh, json={'session_id': old}).json()['submission']['verification_status'] == 'verified'
            passed('Historical incomplete reviewed records reopen without invented farm metadata or altered decisions')

            other_farm = db.create_farm_parcel(other['id'], 'Other synthetic parcel', RING)
            for status in ('rejected', 'own_review_denied'):
                record = analyze({'farm_id': other_farm['id']}, oh).json()
                assert submit(record, oh).status_code == 200
                with connect() as conn, conn.cursor() as cur:
                    cur.execute('SELECT id FROM review_cases WHERE current_session_id=%s', (record['session_id'],))
                    other_case = cur.fetchone()['id']
                if status == 'rejected':
                    response = client.post(f'/api/operator/cases/{other_case}/decision', headers=ah,
                                           json={'version': 1, 'status': 'rejected', 'notes': 'Field evidence still needed.', 'reason': 'other'})
                    assert response.status_code == 200, response.text
                    viewed = client.get(f"/api/mobile/analyses/{record['session_id']}", headers=oh).json()['analysis']
                    assert viewed['verification_status'] == 'rejected'
                    assert viewed['planner_notes'] == 'Field evidence still needed.'
                else:
                    db.admin_update_user(other['id'], role='agricultural_planning_analyst',
                                         actor_user_id=admin['id'], actor_role='super_admin')
                    own_headers = headers(db.get_user_by_id(other['id']))
                    response = client.post(f'/api/operator/cases/{other_case}/decision', headers=own_headers,
                                           json={**decision, 'version': 1})
                    assert response.status_code == 403, response.text
            passed('Rejection notes reach the owner; a promoted analyst cannot review their own prior submission')

    OUT.mkdir(parents=True, exist_ok=True)
    (OUT/'sql-api-results.json').write_text(json.dumps({
        'status': 'PASS', 'checks': checks, 'database': 'Verified disposable instance; isolated schema removed',
        'providers': 'Controlled inference fixture; workers disabled; no external message sent',
        'limits': ['This is SQL/API acceptance, not compiled-client or physical-device acceptance.']}, indent=2)+'\n')
    print('PASS: Phase 1 SQL/API journey; isolated schema removed.')


if __name__ == '__main__':
    run()
