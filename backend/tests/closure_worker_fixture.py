"""Subprocess fixture. Hard-coded disposable port; refuses any other database."""
import sys
import re
import json
import psycopg2
from psycopg2.extras import RealDictCursor
import database as db
import analysis_jobs as jobs
import qa_closure

mode,schema=sys.argv[1:3]
assert re.fullmatch(r'defense_[a-f0-9]{32}',schema)
db.get_conn=lambda:psycopg2.connect('postgresql://defense_test@127.0.0.1:55439/postgres',cursor_factory=RealDictCursor,options=f'-c search_path={schema}')
if mode=='hold':
    uid,key=int(sys.argv[3]),sys.argv[4]
    with db.analysis_request_lock(uid,key) as held:
        assert held
        jobs._update(uid,key,'running')
        print('LOCK_READY',flush=True)
        sys.stdin.read()
elif mode=='quota':
    results=[qa_closure.consume_quota('multi-process-fixture','multiprocess',10) for _ in range(8)]
    print(json.dumps({'allowed':results.count(0),'blocked':sum(v>0 for v in results)}),flush=True)
else:
    raise ValueError('Unsupported fixture mode')
