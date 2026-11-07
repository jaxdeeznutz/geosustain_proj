"""Inbox filters and recorded geometry contract without a live database."""
from unittest.mock import patch
import operator_workflow as workflow


def test_decision_history_includes_only_recorded_terminal_decisions():
    where, values = workflow.conditions(q='Farm', place='Panabo', view='decisions')
    assert "c.status IN ('verified','rejected')" in where
    assert values == ['%Farm%', '%Panabo%']
    assert '7 days' not in where


def test_inbox_selects_saved_polygon_once_and_retains_pagination():
    class Cursor:
        def __enter__(self): return self
        def __exit__(self, *args): pass
        def execute(self, sql, values):
            assert sql.count('s.selected_polygon') == 1
            assert values[-2:] == (3, 0)
        def fetchall(self):
            return [{'case_id': n, 'selected_polygon': [{'lat': 7.29, 'lng': 125.62}]} for n in range(3)]
    class Connection:
        def cursor(self): return Cursor()
        def close(self): pass
    with patch.object(workflow.db, 'get_conn', return_value=Connection()):
        result = workflow.inbox(limit=2, view='decisions', status='all')
    assert len(result['queue']) == 2 and result['has_more']
    assert result['queue'][0]['selected_polygon']
