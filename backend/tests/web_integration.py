"""Actual SQL regression in an owned, automatically removed local test schema."""
import json
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from unittest.mock import patch
from defense_integration import isolated, db, api, TestClient
from web_summary import summary

def run():
    with isolated() as connect:
        password='SyntheticOnly!2026'
        owner=db.create_user('Web fixture','web-fixture@example.com',api.hash_password(password))
        foreign=db.create_user('Other fixture','web-foreign@example.com',api.hash_password(password))
        with connect() as conn,conn.cursor() as cur:
            for uid,score,mode in [(owner['id'],0,''),(owner['id'],100,''),(owner['id'],None,''),(owner['id'],99,'preliminary_environmental'),(foreign['id'],95,'')]:
                cur.execute('INSERT INTO analysis_sessions(user_id,center_lat,center_lon,place_name,result_snapshot,area_hectares) VALUES(%s,7.29,125.62,%s,%s::jsonb,1) RETURNING id',(uid,'Synthetic web parcel',json.dumps({'analysis_mode':mode})))
                sid=cur.fetchone()['id']
                cur.execute("INSERT INTO crop_recommendations(session_id,predicted_crop,compatibility_pct,is_crop_recommended) VALUES(%s,'rice',%s,TRUE)",(sid,score))
        data=summary(owner['id'])
        assert data['analysis_count']==4 and data['scored_count']==2
        assert data['average_model_score']==50 and data['cumulative_area_ha']==4
        assert [data[k] for k in ['high_count','medium_count','low_count','very_low_count']]==[1,0,0,1]
        assert data['frequencies']==[{'crop':'rice','count':3}]
        assert summary(foreign['id'])['analysis_count']==1
        assert len(db.get_user_history(owner['id'],q='Synthetic',limit=2))==2
        assert not db.get_user_history(owner['id'],q="' OR 1=1 --",limit=2)
        with patch.object(api,'init_db',lambda:None),TestClient(api.app) as client:
            token=api.generate_mobile_token(db.get_user_by_id(owner['id']))
            headers={'Authorization':'Bearer '+token}
            assert client.get('/api/web/summary',headers=headers).json()['analysis_count']==4
            assert client.get('/api/web/history?limit=2',headers=headers).json()['has_more'] is True
            assert client.post('/api/web/account-action',headers=headers,json={'action':'delete','current_password':'incorrect'}).status_code==401
            assert db.get_user_by_id(owner['id'])
            assert client.post('/api/web/account-action',headers=headers,json={'action':'delete','current_password':password}).status_code==200
            assert db.get_user_by_id(owner['id']) is None
            assert client.get('/api/mobile/me',headers=headers).status_code==401
            assert summary(foreign['id'])['analysis_count']==1
        print('PASS: real local PostgreSQL whole-account score/zero/missing/preliminary/owner aggregates, bounded search/injection handling, reauthenticated disposable deletion and old-token rejection; foreign owner retained.')

if __name__=='__main__': run()
