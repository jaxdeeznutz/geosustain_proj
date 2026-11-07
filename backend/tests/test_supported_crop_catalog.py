"""The admin catalogue and enabled inputs must agree with the seven-crop scope."""
from unittest.mock import Mock

import database as db
from crop_requirements import REQUIREMENTS


EXPECTED = {'banana', 'cacao', 'coconut', 'durian', 'mango', 'rice', 'rubber'}


def test_catalog_matches_reference_scope():
    assert db.supported_crop_keys() == EXPECTED == {name.lower() for name in REQUIREMENTS}


def test_startup_reconciliation_retains_rows_supported_edits_and_audits_only_retired(monkeypatch):
    cur = Mock()
    cur.fetchall.side_effect = [[{'id': 15, 'crop_key': 'papaya'}, {'id': 16, 'crop_key': 'banana (saba)'}], []]
    audit = Mock()
    monkeypatch.setattr(db, 'audit_in_transaction', audit)
    assert len(db.reconcile_supported_crop_catalog(cur)) == 2
    assert db.reconcile_supported_crop_catalog(cur) == []
    assert audit.call_count == 2
    statements = [call.args for call in cur.execute.call_args_list]
    inserts = [args for args in statements if args[0].startswith('INSERT')]
    assert len(inserts) == 14
    assert {args[1][0] for args in inserts} == EXPECTED
    assert all('ON CONFLICT (crop_key) DO NOTHING' in args[0] for args in inserts)
    updates = [args for args in statements if args[0].startswith('UPDATE')]
    assert all('is_active=TRUE AND NOT (crop_key=ANY(%s))' in args[0] for args in updates)
    assert all(set(args[1][0]) == EXPECTED for args in updates)
    assert all('DELETE' not in args[0] for args in statements)
    assert all(call.args[3] == 'crop_catalog_reconciled' for call in audit.call_args_list)


def test_admin_list_and_enabled_filter_use_same_supported_keys(monkeypatch):
    cur = Mock()
    cur.__enter__ = Mock(return_value=cur)
    cur.__exit__ = Mock(return_value=False)
    conn = Mock()
    conn.__enter__ = Mock(return_value=conn)
    conn.__exit__ = Mock(return_value=False)
    conn.cursor.return_value = cur
    monkeypatch.setattr(db, 'get_conn', lambda: conn)
    cur.fetchall.return_value = [{'crop_key': 'banana', 'is_active': True}]
    rows = db.list_crop_reference()
    assert len(rows) == 1 and rows[0]['crop_key'] == 'banana' and rows[0]['is_active']
    assert [p['label'] for p in rows[0]['varieties']] == ['Cavendish', 'Lakatan', 'Saba']
    assert rows[0]['variety_prediction_scope'] == 'crop_group_only'
    assert 'crop_key=ANY(%s)' in cur.execute.call_args.args[0]
    assert set(cur.execute.call_args.args[1][0]) == EXPECTED
    assert db.get_active_crop_keys() == {'banana'}
    assert 'is_active = TRUE AND crop_key=ANY(%s)' in cur.execute.call_args.args[0]
    cur.fetchall.return_value = []
    assert db.get_active_crop_keys() == set()  # Disabling all seven remains intentional.


def test_legacy_crop_cannot_be_reactivated(monkeypatch):
    connect = Mock(side_effect=AssertionError('Unsupported updates must not open a connection.'))
    monkeypatch.setattr(db, 'get_conn', connect)
    assert db.update_crop_reference('papaya', is_active=True) is None
    assert db.update_crop_reference('banana (saba)', label='Banana') is None
    connect.assert_not_called()


def test_variety_profiles_do_not_add_model_classes_or_reuse_mutable_reference_data():
    from crop_varieties import with_variety_reference
    row = {'crop_key': 'banana', 'is_active': True}
    enriched = with_variety_reference(row)
    assert 'varieties' not in row
    assert len(enriched['varieties']) == 3
    assert db.supported_crop_keys() == EXPECTED
    for profile in enriched['varieties']:
        assert profile['sources'] and all(s['url'].startswith('https://') for s in profile['sources'])
        assert not any(k in profile for k in ['compatibility_pct', 'model_probability_pct', 'is_active'])
    enriched['varieties'][0]['label'] = 'Changed by caller'
    assert with_variety_reference(row)['varieties'][0]['label'] == 'Cavendish'
    assert with_variety_reference({'crop_key': 'rice'}) == {'crop_key': 'rice'}
