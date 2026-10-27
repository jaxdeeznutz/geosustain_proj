"""Keep the tracker and phase execution notes aligned with actual outcomes."""
import csv
import json
import re
from datetime import datetime, timezone
from pathlib import Path

HERE=Path(__file__).resolve().parent
ROOT=HERE.parent
def record(phase, summary, remaining, statuses=None, evidence=None):
    plan=json.loads((HERE/'plan.json').read_text(encoding='utf-8'))
    p=next(p for p in plan['phases'] if p['id']==phase)
    statuses=statuses or {}
    for task in p['tasks']:
        task['status']=statuses.get(task['id'],'CODE_COMPLETE')
    p['status']='COMPLETE' if all(t['status']=='COMPLETE' for t in p['tasks']) else 'PARTIAL'
    receipt={'phase':phase,'updated_at_utc':datetime.now(timezone.utc).isoformat(),'status':p['status'],'summary':summary,'remaining':remaining,'tasks':{t['id']:t['status'] for t in p['tasks']},'evidence':evidence or []}
    out=ROOT/'defense-evidence/web-fix-execution'/('phase-'+phase)
    out.mkdir(parents=True,exist_ok=True)
    (out/'results.json').write_text(json.dumps(receipt,indent=2),encoding='utf-8')
    (out/'README.md').write_text(f"# Web phase {phase}\n\nStatus: {p['status']}\n\n{summary}\n\n## Remaining acceptance\n\n"+'\n'.join('- '+x for x in remaining)+'\n\nSee [structured results](results.json).\n',encoding='utf-8')
    (HERE/'plan.json').write_text(json.dumps(plan,indent=2),encoding='utf-8')
    tracker=HERE/'EXECUTION_TRACKER.csv'
    with tracker.open(encoding='utf-8',newline='') as h:
        reader=csv.DictReader(h);fields=reader.fieldnames;rows=list(reader)
    for row in rows:
        if row['phase']==phase:
            row['status']=receipt['tasks'][row['task_id']]
            row['local_test_evidence']=str(out.relative_to(ROOT)).replace('\\','/')+'/results.json'
            row['remaining_gate']='; '.join(remaining)
    with tracker.open('w',encoding='utf-8',newline='') as h:
        writer=csv.DictWriter(h,fieldnames=fields);writer.writeheader();writer.writerows(rows)
    path=HERE/p['file'];content=path.read_text(encoding='utf-8')
    content=content.replace('**Status:** NOT_STARTED — planned work only.',f"**Status:** {p['status']} — see current execution below.")
    marker='\n## Current execution\n'
    content=content.split(marker)[0]+marker+'\n'+summary+'\n\n**Remaining:** '+'; '.join(remaining)+f"\n\n[Execution evidence](../defense-evidence/web-fix-execution/phase-{phase}/README.md).\n"
    for task in p['tasks']:
        content=re.sub(r"\| "+re.escape(task['id'])+r" \| [^|\n]+ \| [^|\n]+ \|",f"| {task['id']} | {task['status']} | Current execution below |",content)
    path.write_text(content,encoding='utf-8')
    return receipt
