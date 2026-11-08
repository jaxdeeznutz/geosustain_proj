"""Real SQL checks in the guarded disposable local PostgreSQL test schema."""
import json
import sys
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parent))
from defense_integration import isolated, db, api, TestClient
from recommendation_patterns import patterns, model_identity


def run():
    version, _ = model_identity()
    with isolated() as connect:
        farmer = db.create_user('Pattern fixture', 'pattern-farmer@example.com', 'unused-test-only')
        other = db.create_user('Private fixture', 'pattern-other@example.com', 'unused-test-only')
        analyst = db.create_user('Analyst fixture', 'pattern-analyst@example.com', 'unused-test-only', role='agricultural_planning_analyst')
        with connect() as conn, conn.cursor() as cur:
            def record(owner, crop, score, model, month, *, submit=True, mode='crop_model', nested=True):
                snap = {'analysis_mode': mode}
                if model is not None:
                    snap.update({'model_explanation': {'model_version': model}} if nested else {'model_version': model})
                cur.execute('''INSERT INTO analysis_sessions(user_id,center_lat,center_lon,place_name,
                  result_snapshot,area_hectares,analyzed_at) VALUES(%s,7.29,125.62,'Synthetic pattern parcel',%s::jsonb,1,%s) RETURNING id''',
                            (owner, json.dumps(snap), month + '-01'))
                sid = cur.fetchone()['id']
                cur.execute('''INSERT INTO crop_recommendations(session_id,predicted_crop,compatibility_pct,is_crop_recommended)
                  VALUES(%s,%s,%s,TRUE)''', (sid, crop, score))
                case = None
                if submit:
                    cur.execute("INSERT INTO review_cases(owner_id,current_session_id,status) VALUES(%s,%s,'pending') RETURNING id", (owner, sid))
                    case = cur.fetchone()['id']
                return sid, case
            old_sid, case = record(farmer['id'], 'Rice', 99, version, '2026-07')
            sid, _ = record(farmer['id'], 'Rice', 0, version, '2026-09', submit=False)
            cur.execute('UPDATE review_cases SET current_session_id=%s WHERE id=%s', (sid, case))
            record(other['id'], 'Banana', 90, version, '2026-11', nested=False)
            record(farmer['id'], 'Banana (Cavendish/Lakatan)', 85, 'old-model', '2026-07')
            record(farmer['id'], 'Rice', 99, None, '2026-08')
            record(farmer['id'], 'Rice', 99, version, '2026-10', mode='preliminary_environmental')
            record(other['id'], 'Mango', 100, version, '2026-11', submit=False)
            record(analyst['id'], 'Mango', 100, version, '2026-11', submit=False)
        current = patterns(analyst['id'], submitted=True)
        assert current['analysis_count'] == 3 and current['overall_count'] == 5 and current['archived_count'] == 2
        assert current['scored_count'] == 2 and current['average_model_score'] == 45
        assert current['frequencies'] == [{'crop': 'Banana', 'count': 1}, {'crop': 'Rice', 'count': 1}]
        assert current['monthly'] == [{'month': f'2026-{m:02d}', 'count': 1 if m in (9, 11) else 0} for m in range(6, 12)]
        assert old_sid not in [r['session_id'] for r in current['recent_records']]
        all_versions = patterns(analyst['id'], submitted=True, model_scope='all')
        assert all_versions['analysis_count'] == 5 and all_versions['scored_count'] == 4
        assert any(r['crop'] == 'Banana (Cavendish/Lakatan)' for r in all_versions['frequencies'])
        assert patterns(analyst['id'])['analysis_count'] == 1  # Personal route remains owner-bound.
        with patch.object(api, 'init_db', lambda: None), TestClient(api.app) as client:
            farmer_headers = {'Authorization': 'Bearer ' + api.generate_mobile_token(db.get_user_by_id(farmer['id']))}
            analyst_headers = {'Authorization': 'Bearer ' + api.generate_mobile_token(db.get_user_by_id(analyst['id']))}
            assert client.get('/api/operator/recommendation-patterns', headers=farmer_headers).status_code == 403
            response = client.get('/api/operator/recommendation-patterns', headers=analyst_headers)
            assert response.status_code == 200 and response.json()['average_model_score'] == 45
            assert client.get('/api/operator/recommendation-patterns?model_scope=bad', headers=analyst_headers).status_code == 422
            personal = client.get('/api/web/recommendation-patterns?user_id=999', headers=analyst_headers).json()
            assert personal['analysis_count'] == 1
        print('PASS: real PostgreSQL current model, historical scope, missing versions, zero score, preliminary exclusion, latest revisions, chronological zero months and role/owner boundaries.')


def current_pipeline_records():
    """Use the production persistence path and current environmental labels."""
    version, _ = model_identity()
    with isolated() as connect:
        farmer = db.create_user('Current pipeline fixture', 'current-pattern-farmer@example.com', 'unused-test-only')
        analyst = db.create_user('Current analyst fixture', 'current-pattern-analyst@example.com', 'unused-test-only', role='agricultural_planning_analyst')

        def save(score, *, submit=True, mode='environmental_model_no_npk', allow=True, recommended=True):
            result = {
                'lat': 7.29, 'lon': 125.62, 'area_hectares': 1,
                'place_name': 'Synthetic current pipeline parcel',
                'analysis_mode': mode, 'recommendation_basis': 'model_probability',
                'model_version': version, 'model_explanation': {'model_version': version},
                'predicted_crop': 'Mango', 'crop_compatibility_pct': score,
                'is_crop_recommended': recommended,
                'land_type': 'Vegetation observation only',
                'land_cover': {'allow_crops': allow, 'status': 'unknown' if allow else 'water'},
            }
            sid = db.save_analysis_session(farmer['id'], result, 'synthetic-pattern-regression')
            if submit:
                with connect() as conn, conn.cursor() as cur:
                    cur.execute("INSERT INTO review_cases(owner_id,current_session_id,status) VALUES(%s,%s,'pending')", (farmer['id'], sid))
            return sid

        save(55.6)
        save(40)
        save(99, submit=False)  # Unsubmitted analyses do not enter analyst totals.
        save(100, mode='preliminary_environmental')
        save(100, allow=False)  # Even stale positive flags cannot clear a blocked land check.
        save(100, recommended=False)
        summary = patterns(analyst['id'], submitted=True)
        assert summary['analysis_count'] == 5
        assert summary['scored_count'] == 2, summary
        assert round(float(summary['average_model_score']), 1) == 47.8
        assert summary['frequencies'] == [{'crop': 'Mango', 'count': 2}]
        assert sum(r['count'] for r in summary['monthly']) == 2
        assert patterns(analyst['id'])['analysis_count'] == 0
        print('PASS: actual saved seven-input pipeline records populate Mango frequency, score average/distribution and dated trends; unsubmitted, preliminary and blocked results remain excluded.')


if __name__ == '__main__':
    run()
    current_pipeline_records()
