from unittest.mock import Mock
import fastapi_app as api
import web_summary

def test_owned_web_history_is_bounded_search_and_validation(client, monkeypatch):
    history=Mock(return_value=[{'session_id':i} for i in range(21)])
    monkeypatch.setattr(api,'get_user_history',history)
    response=client.get('/api/web/history?offset=40&limit=20&q=farm')
    assert response.status_code==200
    assert len(response.json()['history'])==20 and response.json()['has_more']
    history.assert_called_once_with(10,limit=21,offset=40,q='farm')
    for query in ['offset=-1','limit=101','q='+'x'*161]:
        assert client.get('/api/web/history?'+query).status_code==422

def test_summary_is_bound_to_authenticated_owner(client, monkeypatch):
    summary=Mock(return_value={'analysis_count':3,'average_model_score':None})
    monkeypatch.setattr(web_summary,'summary',summary)
    assert client.get('/api/web/summary?user_id=999').json()['analysis_count']==3
    summary.assert_called_once_with(10)

def test_account_action_needs_reauth_and_does_not_delete_on_failure(client, monkeypatch):
    delete=Mock();deactivate=Mock()
    monkeypatch.setattr(api,'mobile_delete_me',delete)
    monkeypatch.setattr(api,'mobile_deactivate_me',deactivate)
    monkeypatch.setattr(api,'verify_password',lambda *args:False)
    for payload in [{'action':'delete'},{'action':'deactivate','current_password':'wrong'}]:
        assert client.post('/api/web/account-action',json=payload).status_code==401
    delete.assert_not_called();deactivate.assert_not_called()
    assert client.post('/api/web/account-action',json={'action':'promote'}).status_code==422

def test_correct_current_password_selects_one_account_action(client, monkeypatch):
    delete=Mock(return_value={'ok':True})
    monkeypatch.setattr(api,'mobile_delete_me',delete)
    monkeypatch.setattr(api,'verify_password',lambda password,_:password=='synthetic current')
    assert client.post('/api/web/account-action',json={'action':'delete','current_password':'synthetic current'}).status_code==200
    assert delete.call_count==1 and delete.call_args.kwargs['user']['id']==10

def test_foreign_google_proof_cannot_close_account(client, monkeypatch):
    import federated_identity
    monkeypatch.setattr(federated_identity,'google_identity',lambda _:({'sub':'foreign'},'foreign@example.com'))
    delete=Mock();monkeypatch.setattr(api,'mobile_delete_me',delete)
    assert client.post('/api/web/account-action',json={'action':'delete','firebase_id_token':'synthetic-proof'}).status_code==403
    delete.assert_not_called()
