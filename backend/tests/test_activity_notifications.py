from unittest.mock import Mock
import activity_notifications as activity

def test_activity_filters_and_read_use_authenticated_owner(client, monkeypatch):
    inbox=Mock(return_value={'notifications':[],'unread_count':0,'has_more':False})
    read=Mock(return_value=None); all_read=Mock(return_value={'marked_read':2})
    monkeypatch.setattr(activity,'inbox',inbox)
    monkeypatch.setattr(activity,'mark_read',read)
    monkeypatch.setattr(activity,'mark_all',all_read)
    assert client.get('/api/mobile/activity?unread_only=true&event_type=review&offset=50').status_code==200
    inbox.assert_called_once_with(10,50,50,True,'review')
    assert client.post('/api/mobile/activity/99/read').status_code==404
    read.assert_called_once_with(10,99)
    assert client.post('/api/mobile/activity/read-all').json()=={'marked_read':2}
    all_read.assert_called_once_with(10)

def test_activity_rejects_unbounded_paging_and_unknown_types(client):
    for query in ('limit=101','offset=-1','event_type=arbitrary','unread_only=invalid'):
        assert client.get('/api/mobile/activity?'+query).status_code==422

def test_partial_activity_is_truthful_and_retry_is_deduplicated():
    cur=Mock()
    activity.analysis_saved(cur,10,42,True)
    sql,params=cur.execute.call_args_list[0].args
    assert 'ON CONFLICT(user_id,event_key) DO NOTHING' in sql
    assert params[0]=='analysis_partial' and 'partial' in params[1]
    assert params[-2:]==(42,10)
    push_sql,push_params=cur.execute.call_args_list[1].args
    assert 'ON CONFLICT(token,activity_id) DO NOTHING' in push_sql
    assert 'u.password_version=p.password_version' in push_sql
    assert push_params==(10,42)

def test_analyst_alerts_require_active_authorized_role_and_pending_submission():
    cur=Mock();activity.submitted(cur,10,42)
    sql,params=cur.execute.call_args.args
    assert "role='agricultural_planning_analyst'" in sql
    assert "is_active=TRUE" in sql and "verification_status='pending'" in sql
    assert params==(42,10)

def test_failure_activity_uses_safe_reason_and_owned_target():
    cur=Mock();activity.failed(cur,10,'request-key',55,503)
    sql,params=cur.execute.call_args.args
    assert 'f.farmer_id=u.id' in sql and 'ON CONFLICT' in sql
    assert params[0]=='failed:request-key' and 'retained' in params[1]
    assert params[-2:]==(55,10)
