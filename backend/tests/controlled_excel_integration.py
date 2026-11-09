"""Exercise XLSX import against a guarded disposable PostgreSQL schema only."""
import base64
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
sys.path.insert(0,str(Path(__file__).resolve().parent))
from fastapi.testclient import TestClient
from defense_integration import isolated
from test_controlled_excel import workbook,row
import controlled_records as records
import database as db
import fastapi_app as api


def run():
    artifact = Path('backend/crop_model.pkl')
    model_before = hashlib.sha256(artifact.read_bytes()).hexdigest()
    with isolated() as connect:
        admin = db.create_user('Excel Admin','excel-admin@example.com','unused-test-only',role='super_admin')
        second = db.create_user('Other Admin','excel-other@example.com','unused-test-only',role='super_admin')
        farmer = db.create_user('Excel Farmer','excel-farmer@example.com','unused-test-only')
        headers=lambda user:{'Authorization':'Bearer '+api.generate_mobile_token(user)}
        old={'lat':7.29,'lon':125.62,'predicted_crop':'Mango','crop_compatibility_pct':47.5,
             'analysis_mode':'environmental_model_no_npk','model_version':model_before,'is_crop_recommended':True}
        sid=db.save_analysis_session(farmer['id'],old,'excel-preservation-fixture')
        source=workbook([row(),row(crop='Mango',factor='soil_ph',unit='pH',period='soil_surface',
                                  preferred_min=6,preferred_max=7,absolute_min=5,absolute_max=8)])
        with patch.object(api,'init_db',lambda:None),TestClient(api.app) as client:
            def preview(content=source):
                response=client.post('/api/admin/controlled-records/excel/preview',headers=headers(admin),
                    json={'filename':'requirements.xlsx','content_base64':base64.b64encode(content).decode()})
                assert response.status_code==200,response.text
                return response.json()
            def body(preview,activate=True):
                return {'upload_id':preview['upload_id'],'expected':[r.get('expected', {'record_key':'rice_rainfall','revision':0,'generation':0}) for r in preview['rows']],
                        'activate':activate,'review_note':'Reviewed this synthetic software fixture only.' if activate else ''}
            def apply(value,user=admin):
                return client.post('/api/admin/controlled-records/excel/apply',headers=headers(user),json=value)
            p=preview()
            assert p['total_rows']==p['valid_rows']==2
            assert records.list_records()==[] and records.load_active_records()==[]
            missing_review={**body(p),'review_note':''}
            assert apply(missing_review).status_code==422
            assert apply(body(p),second).status_code==422
            imported=apply(body(p)); assert imported.status_code==200,imported.text
            assert imported.json()['imported']==2 and imported.json()['activated']
            assert apply(body(p)).json()==imported.json()  # Lost-response retry is idempotent.
            active=records.load_active_records()
            assert len(active)==2 and len(records.list_records())==2
            assert all(r['document']['evidence_url']=='' for r in active)
            assert all(r['document']['source_file']['sha256']==hashlib.sha256(source).hexdigest() for r in active)
            downloaded=client.get('/api/admin/controlled-records/excel/files/'+p['upload_id'],headers=headers(admin))
            assert downloaded.content==source
            assert client.get('/api/admin/controlled-records/excel/files/'+p['upload_id'],headers=headers(farmer)).status_code==403
            with connect() as conn,conn.cursor() as cur:
                cur.execute('SELECT result_snapshot FROM analysis_sessions WHERE id=%s',(sid,))
                assert cur.fetchone()['result_snapshot']==old
            fixture=json.loads(Path('test/fixtures/controlled_analysis.json').read_text())
            before=deepcopy(fixture)
            records.attach_controlled_records(fixture,active)
            rain=next(f for crop in fixture['crop_assessments'] if crop['crop']=='Rice' for f in crop['factors'] if f['factor']=='rainfall')
            assert rain['requirement']['optimal']==[2000,2500]
            assert rain['requirement']['source']['source_file']['sha256']==p['sha256']
            for key in ['predicted_crop','crop_compatibility_pct','model_explanation','local_model_explanation']:
                assert fixture[key]==before[key],key
            stale=preview()
            rice=next(r for r in active if r['record_key']=='rice_rainfall')
            edited=records.RecordBody(**rice['document'],expected_revision=rice['revision'])
            records.create_revision(edited,admin)
            # Mango sorts before Rice: its attempted insert/activation must roll back.
            failed=apply(body(stale)); assert failed.status_code==409,failed.text
            assert len(records.list_records())==3
            mango=next(r for r in records.list_records() if r['record_key']=='mango_soil_ph')
            assert mango['revision']==1
            assert {r['id'] for r in records.load_active_records()}=={r['id'] for r in active}
            bad=preview(workbook([row(preferred_min=9000)]))
            assert bad['valid_rows']==0
            assert apply(body(bad)).status_code==422
            assert len(records.list_records())==3
            draft=preview(workbook([row(crop='Cacao')]))
            result=apply(body(draft,False)); assert result.status_code==200,result.text
            assert not result.json()['activated'] and len(records.load_active_records())==2
            assert hashlib.sha256(artifact.read_bytes()).hexdigest()==model_before
        print('PASS: real XLSX preview without changes, reviewed batch activation, idempotent retry, private source download, stale atomic rollback, invalid-row denial, draft-only import, immutable saved analysis and unchanged RF ranking/artifact.')


if __name__=='__main__': run()
