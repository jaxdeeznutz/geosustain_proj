"""Real SQL and API acceptance, inside the verified disposable schema only."""
import sys
import json
from datetime import date
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parent))
from defense_integration import isolated, db, api, TestClient
import operator_workflow as workflow


def run():
    with isolated() as connect:
        password=api.hash_password('SyntheticOnly!2026')
        farmer=db.create_user('Synthetic farmer','operator-owner@example.com',password)
        other=db.create_user('Foreign owner','operator-foreign@example.com',password)
        reviewers=[db.create_user('Synthetic reviewer '+str(n),'operator-reviewer'+str(n)+'@example.com',password,role='agricultural_planning_analyst') for n in (1,2)]
        polygon=[{'lat':7.29,'lng':125.62},{'lat':7.29,'lng':125.621},{'lat':7.291,'lng':125.621}]
        farm=db.create_farm_parcel(farmer['id'],'Synthetic parcel',polygon)
        def session(owner=farmer['id']):
            with connect() as conn,conn.cursor() as cur:
                cur.execute('''INSERT INTO analysis_sessions(user_id,farm_id,center_lat,center_lon,selected_polygon,
                    boundary_version,farm_name_snapshot,area_hectares,result_snapshot)
                    VALUES(%s,%s,7.29,125.62,%s::jsonb,1,'Synthetic parcel',1,%s::jsonb) RETURNING id''',
                    (owner,farm['id'],json.dumps(polygon),json.dumps({'analysis_mode':'preliminary_environmental','selected_polygon':polygon})))
                return cur.fetchone()['id']
        first=session();db.submit_analysis_to_planner(farmer['id'],first)
        case_id=workflow.inbox()['queue'][0]['case_id']
        headers=lambda u:{'Authorization':'Bearer '+api.generate_mobile_token(u)}
        with patch.object(api,'init_db',lambda:None),TestClient(api.app) as client:
            rh=headers(reviewers[0]);fh=headers(farmer);oh=headers(other)
            assert client.get('/api/operator/inbox',headers=fh).status_code==403
            assert client.get(f'/api/mobile/review-cases/{case_id}',headers=oh).status_code==404
            assert client.post('/api/planner/verify',headers=rh,json={'session_id':first,'status':'rejected','notes':' '}).status_code==422
            assert client.post(f'/api/operator/cases/{case_id}/decision',headers=rh,json={'version':1,'status':'verified'}).status_code==422
            asked=client.post(f'/api/operator/cases/{case_id}/decision',headers=rh,json={'version':1,'status':'needs_information','notes':'Confirm the parcel outline.','reason':'boundary_issue'})
            assert asked.status_code==200,asked.text
            assert asked.json()['case']['status']=='needs_information'
            new=session();foreign=session(other['id'])
            assert client.post(f'/api/mobile/review-cases/{case_id}/resubmit',headers=fh,json={'version':2,'session_id':foreign,'notes':'Corrected'}).status_code==409
            corrected=client.post(f'/api/mobile/review-cases/{case_id}/resubmit',headers=fh,json={'version':2,'session_id':new,'notes':'Corrected outline, new analysis.'})
            assert corrected.status_code==200,corrected.text
            assert len(corrected.json()['revisions'])==2
            assert db.get_user_analysis(farmer['id'],first)['verification_status']=='needs_information'
            decision={'version':3,'status':'verified','notes':'Reviewed available preliminary evidence.','checklist':{key:True for key in workflow.CHECKS}}
            accepted=client.post(f'/api/operator/cases/{case_id}/decision',headers=rh,json=decision)
            assert accepted.status_code==200,accepted.text
            assert client.post(f'/api/operator/cases/{case_id}/decision',headers=headers(reviewers[1]),json={**decision,'status':'rejected','reason':'other'}).status_code==409
            renamed=db.update_farm_parcel(farmer['id'],farm['id'],farm_name='Renamed only',expected_boundary_version=1)
            assert workflow.detail(case_id)['geometry_matches_current'] is True
            moved=[{**p,'lng':p['lng']+.001} for p in polygon]
            db.update_farm_parcel(farmer['id'],farm['id'],polygon=moved,expected_boundary_version=renamed['boundary_version'])
            assert workflow.detail(case_id)['geometry_matches_current'] is False
            added=client.post(f'/api/operator/cases/{case_id}/followups',headers=rh,json={'title':'Synthetic field follow-up','due_on':date.today().isoformat()})
            assert added.status_code==200,added.text
            task=added.json()['followups'][0]['id']
            assert client.post(f'/api/operator/cases/{case_id}/followups/{task}/complete',headers=headers(reviewers[1])).status_code==409
            events=client.get('/api/mobile/activity',headers=rh)
            assert events.status_code==200,events.text
            from activity_notifications import inbox
            inbox(reviewers[0]['id']);inbox(reviewers[0]['id'])
            with connect() as conn,conn.cursor() as cur:
                cur.execute("SELECT COUNT(*) AS n FROM activity_notifications WHERE event_key=%s",('followup-due:'+str(task),));assert cur.fetchone()['n']==1
            assert client.post(f'/api/operator/cases/{case_id}/followups/{task}/complete',headers=rh).status_code==200
            with connect() as conn,conn.cursor() as cur:
                cur.execute('''INSERT INTO analysis_sessions(user_id,farm_id,center_lat,center_lon,area_hectares,verification_status,submitted_at)
                    SELECT %s,%s,7.29,125.62,1,'pending',NOW() FROM generate_series(1,500)''',(farmer['id'],farm['id']))
                workflow.migrate(cur)
            listing=client.get('/api/operator/inbox?limit=20',headers=rh).json()
            assert len(listing['queue'])==20 and listing['has_more']
            assert not any(k in listing['queue'][0] for k in ('result_snapshot','heatmap_grid','farmer_email'))
            assert client.get('/api/operator/inbox?q=not-present',headers=rh).json()['queue']==[]
            assert len(client.get('/api/operator/inbox?status=all&view=reviewed_week',headers=rh).json()['queue'])==1
            assert len(client.get('/api/operator/inbox?status=all&view=preliminary',headers=rh).json()['queue'])==1
            assert client.get('/api/operator/inbox?status=all&view=followups_due',headers=rh).json()['queue']==[]
            newest=client.get('/api/operator/map?sort=newest&limit=1',headers=rh).json()['queue'][0]['case_id']
            oldest=client.get('/api/operator/map?sort=oldest&limit=1',headers=rh).json()['queue'][0]['case_id']
            assert newest>oldest
            assert client.get('/api/operator/map?west=NaN',headers=rh).status_code==422
            stats=client.get('/api/operator/overview',headers=rh).json()
            assert stats['distinct_farms']==1 and stats['parcel_area_sum_ha']==1 and stats['cases']==501
            assert client.get(f'/api/operator/cases/by-session/{foreign}',headers=rh).status_code==404
            fixture=accepted.json();fixture['case']['owner_id']=0
            out=Path('defense-evidence/operator-workflow-execution');out.mkdir(parents=True,exist_ok=True)
            (out/'synthetic-review-report.json').write_text(json.dumps(fixture,indent=2))
        print('PASS: owner/role denial, required reasons/checklist, information request -> linked resubmission -> accept, stale reviewer conflict, immutable old revision, rename versus geometry, assigned follow-up/deduped due activity, 500-case bounded projection/search and one-farm aggregates. Isolated schema removed.')


if __name__=='__main__':run()
