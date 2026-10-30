"""Actual isolated SQL/API administration, activation, consumers and rollback."""
from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
from pathlib import Path
import json
import sys
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from phase06_manual_host import workspace, api, db, TestClient
from test_controlled_records import body
import controlled_records as records


def run(write_fixtures=True):
    out = Path('defense-evidence/capstone-fix-execution/phase-06');out.mkdir(parents=True,exist_ok=True)
    checks=[]
    with workspace() as (farmer, analyst, farm, admin), TestClient(api.app) as client:
        with db.get_conn() as conn, conn.cursor() as cur:
            records.rollback(cur);records.migrate(cur);records.migrate(cur);conn.commit()
        checks.append('Idempotent migration and empty-table rollback/remigration passed on the verified disposable server')
        ah={'Authorization':'Bearer '+api.generate_mobile_token(admin)}
        fh={'Authorization':'Bearer '+api.generate_mobile_token(farmer)}
        ph={'Authorization':'Bearer '+api.generate_mobile_token(analyst)}
        payload={'farm_id':farm['id'],'boundary_version':1,'intended_planting_month':2}
        def analyze(key):
            response=client.post('/api/mobile/analysis',headers={**fh,'Idempotency-Key':key},json=payload)
            assert response.status_code==200,response.text
            return response.json()
        before=analyze('phase06-before')
        assert before['configuration_snapshot']['records']==[]
        rows={}
        for kind in records.KINDS:
            value=body(kind)
            if kind=='model_version':value['payload']['sha256']=records.installed_model()['sha256']
            response=client.post('/api/admin/controlled-records',headers=ah,json=value)
            assert response.status_code==201,response.text
            row=response.json()['record'];rows[kind]=row
            assert client.post('/api/admin/controlled-records',headers=ah,json=value).status_code==409
            activated=client.post('/api/admin/controlled-records/activation',headers=ah,json={'record_id':row['id'],'expected_generation':0})
            assert activated.status_code==200,activated.text
        checks.append('All six categories create immutable revisions and activate through typed authorized API; stale revision saves rejected')
        after=analyze('phase06-after')
        assert after['configuration_snapshot']['parcel_sample_limit']==5
        assert 1 <= len(after['model_explanation']['samples']) <=5
        assert len(after['configuration_snapshot']['records'])==6
        assert after['local_model_explanation']['status']=='available'
        assert after['installed_model_reference']['document']['payload']['sha256']==after['model_version']
        assert after['seasonal_assessment']['calendar']['crops'][0]['selected_month_listed']
        rain=next(f for c in after['crop_assessments'] if c['crop']=='Rice' for f in c['factors'] if f['factor']=='rainfall')
        assert rain['requirement']['optimal']==[2000,2500] and rain['score']==100
        assert next(l for l in after['spatial_assessment']['layers'] if l['id']=='ndvi')['controlled_source_reference']['id']==rows['environmental_source']['id']
        checks.append('New actual-model inference consumes sample limit, crop ranges, selected-month calendar, source metadata, installed-model identity and supporting citation; local attribution remains additive')
        frozen=deepcopy(after)
        setting=body('system_setting',expected_revision=1);setting['payload']['sample_count']=9
        second=client.post('/api/admin/controlled-records',headers=ah,json=setting).json()['record']
        def activate():
            try:return records.set_activation(records.ActivationBody(record_id=second['id'],expected_generation=1),admin)['generation']
            except records.Conflict:return 'conflict'
        with ThreadPoolExecutor(max_workers=2) as pool: outcomes=list(pool.map(lambda _:activate(),range(2)))
        assert sorted(map(str,outcomes))==['2','conflict'],outcomes
        # Explicit rollback is a version-pointer operation, never an overwrite.
        records.set_activation(records.ActivationBody(record_id=rows['system_setting']['id'],expected_generation=2),admin)
        assert records.sampling_count(records.load_active_records())==5
        checks.append('Concurrent activation has one winner; stale generations fail; previously reviewed revision can be reactivated as rollback')
        saved=client.get(f"/api/mobile/analyses/{after['session_id']}",headers=fh).json()['analysis']
        assert saved['configuration_snapshot']==frozen['configuration_snapshot']
        assert db.get_user_analysis(farmer['id'],before['session_id'])['configuration_snapshot']==before['configuration_snapshot']
        assert client.post('/api/mobile/submit-to-planner',headers=fh,json={'session_id':after['session_id']}).status_code==200
        case=client.get(f"/api/operator/cases/by-session/{after['session_id']}",headers=ph).json()
        assert case['analysis']['configuration_snapshot']==frozen['configuration_snapshot']
        assert case['analysis']['local_model_explanation']==frozen['local_model_explanation']
        checks.append('Earlier analyses and submitted analyst evidence retain exact configuration, spatial and explanation snapshots after edits/activation rollback')
        for headers in [fh,ph]:
            assert client.get('/api/admin/controlled-records',headers=headers).status_code==403
            assert client.post('/api/admin/controlled-records',headers=headers,json=body()).status_code==403
            assert client.post('/api/admin/controlled-records/activation',headers=headers,json={'record_id':1,'expected_generation':0}).status_code==403
        invalid=body('environmental_source');invalid['payload']['source_id']='attacker/private'
        assert client.post('/api/admin/controlled-records',headers=ah,json=invalid).status_code==422
        draft=body('supporting_reference',record_key='unreviewed_reference',review_status='draft')
        draftrow=client.post('/api/admin/controlled-records',headers=ah,json=draft).json()['record']
        assert client.post('/api/admin/controlled-records/activation',headers=ah,json={'record_id':draftrow['id'],'expected_generation':0}).status_code==422
        mismatch=body('model_version',expected_revision=1)
        badmodel=client.post('/api/admin/controlled-records',headers=ah,json=mismatch).json()['record']
        assert client.post('/api/admin/controlled-records/activation',headers=ah,json={'record_id':badmodel['id'],'expected_generation':1}).status_code==422
        checks.append('Farmer/analyst read and mutation denied; unsafe source IDs, draft activation and model identity mismatch rejected')
        count=len(records.list_records(limit=100))
        with patch.object(db,'audit_in_transaction',side_effect=RuntimeError('Controlled audit failure')):
            try:records.create_revision(records.RecordBody(**body('supporting_reference',record_key='audit_failure')),admin)
            except RuntimeError:pass
            else:raise AssertionError('Audit failure did not abort mutation')
        assert len(records.list_records(limit=100))==count
        with db.get_conn() as conn,conn.cursor() as cur:
            try:records.rollback(cur)
            except records.Conflict:pass
            else:raise AssertionError('Used reference tables were destructively rolled back')
            cur.execute("SELECT * FROM audit_logs WHERE action LIKE 'controlled_record_%' ORDER BY id")
            audit=[dict(row) for row in cur.fetchall()]
            assert all(v['actor_user_id']==admin['id'] and v['actor_reference']==f"account:{admin['id']}" for v in audit)
            assert any(v['action']=='controlled_record_activation' and v['details']['before_record_id'] for v in audit)
        checks.append('Audit history retains actor/date/version pointer changes; failed audit rolls back the revision; used-table rollback refuses evidence loss')
        with db.get_conn() as conn,conn.cursor() as cur:
            cur.execute('UPDATE crop_reference SET is_active=FALSE');conn.commit()
        assert db.get_active_crop_keys()==set()
        disabled=client.post('/api/mobile/analysis',headers={**fh,'Idempotency-Key':'phase06-all-disabled'},json=payload)
        assert disabled.status_code==503,disabled.text
        assert client.patch('/api/admin/crops/rice',headers=ah,json={'is_active':True}).status_code==200
        restricted=analyze('phase06-rice-only')
        assert [c['crop'] for c in restricted['crop_assessments']]==['Rice']
        assert restricted['configuration_snapshot']['enabled_crop_keys']==['rice']
        assert restricted['local_model_explanation']['status']=='available'
        assert db.get_user_analysis(farmer['id'],after['session_id'])['local_model_explanation']==frozen['local_model_explanation']
        assert client.patch('/api/admin/crops/rice',headers=ah,json={'optimal':[0,1]}).status_code==422
        checks.append('Disabling every crop never re-enables the catalog; enabling Rice affects only new ranking and saves the exact filter; unsupported legacy crop fields rejected')
        if write_fixtures:
            Path('test/fixtures/controlled_analysis.json').write_text(json.dumps(saved,indent=2)+'\n')
            Path('test/fixtures/controlled_catalog.json').write_text(json.dumps(records.catalog(),indent=2)+'\n')
            Path('test/fixtures/controlled_records.json').write_text(json.dumps(records.list_records(limit=100),default=str,indent=2)+'\n')
    (out/'sql-api-results.json').write_text(json.dumps({'status':'passed','checks':checks,'basis':'Verified disposable PostgreSQL schema and real existing forest; synthetic observations and controlled administrative fixtures, not reviewed agronomic evidence. Temporary schema dropped.'},indent=2)+'\n')
    for check in checks:print('PASS:',check)


if __name__=='__main__':run(write_fixtures='--no-fixtures' not in sys.argv)
