"""Validate coverage, dependencies, skills, links and initial planning state."""
import csv
import hashlib
import importlib.util
import json
import re
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
plan = json.loads((HERE / "plan.json").read_text(encoding="utf-8"))
review_path = ROOT / plan["review_path"]
review = json.loads(review_path.read_text(encoding="utf-8"))
assert hashlib.sha256(review_path.read_bytes()).hexdigest() == plan["review_sha256"], "Review changed; reconcile baseline"
review_ids = {f["id"] for f in review["findings"]}
assert review_ids == {f"WEB-{i:02d}" for i in range(1,19)}
assert plan["findings"] == review["findings"], "Original finding content must be retained"
phases = plan["phases"]
by_id = {p["id"]: p for p in phases}
assert len(by_id) == len(phases) == 8
assert list(by_id) == [f"{i:02d}" for i in range(8)]
owners = Counter(issue for p in phases for issue in p["issues"])
assert set(owners) == review_ids and all(n == 1 for n in owners.values()), "Each issue needs exactly one repair owner"
visited, active = set(), set()
def visit(key):
    assert key not in active, "Cyclic dependency"
    if key in visited: return
    active.add(key)
    for dep in by_id[key]["depends"]:
        assert dep in by_id and dep != key
        visit(dep)
    active.remove(key)
    visited.add(key)
for phase in phases: visit(phase["id"])
assert set(by_id["07"]["depends"]) == set(by_id)-{"07"}

tasks = [t for p in phases for t in p["tasks"]]
allowed_statuses={'NOT_STARTED','IN_PROGRESS','CODE_COMPLETE','VERIFIED_LOCAL','VERIFIED_LIVE','PENDING_EXTERNAL','REQUIRES_MANUAL','COMPLETE','PARTIAL'}
assert len(tasks) == len({t["id"] for t in tasks}) == 37
for p in phases:
    assert (HERE/p["file"]).is_file() and (HERE/p["skill_path"]).is_file()
    assert p["status"] in allowed_statuses
    for path in p["files"]:
        assert (ROOT/path).exists(), f"Referenced implementation path absent: {path}"
    for task in p["tasks"]:
        assert task["status"] in allowed_statuses and task["phase"] == p["id"]
        assert all(task.get(field) for field in ["id","title","work","acceptance","evidence","kind"])

with (HERE/"EXECUTION_TRACKER.csv").open(encoding="utf-8",newline="") as h:
    tracker=list(csv.DictReader(h))
assert len(tracker)==len(tasks)
assert {r["task_id"] for r in tracker} == {t["id"] for t in tasks}
for row in tracker:
    assert row['status']==next(t['status'] for t in tasks if t['id']==row['task_id'])
    if row['local_test_evidence']:
        assert (ROOT/row['local_test_evidence']).exists()
    if row['status']=='NOT_STARTED':
        assert not any(row[c] for c in ["code_or_config_revision","local_test_evidence","deployed_web_api_identity","live_test_evidence","reviewed_by","reviewed_at"])

links=0
broken=[]
for path in HERE.rglob("*.md"):
    content=path.read_text(encoding="utf-8")
    for href in re.findall(r"\[[^\]]*\]\(([^)]+)\)",content):
        if href.startswith(("https:","http:","#")): continue
        target=href.split("#",1)[0].strip("<>")
        links+=1
        if target and not (path.parent/target).exists(): broken.append(f"{path.name}: {href}")
assert not broken,broken

# Run the available skill-creator validator against each real skill entrypoint.
validator_path = Path.home()/".codex/skills/.system/skill-creator/scripts/quick_validate.py"
validated_skills=[]
if validator_path.exists():
    spec=importlib.util.spec_from_file_location("skill_validator",validator_path)
    validator=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(validator)
    for p in phases:
        valid,message=validator.validate_skill(HERE/"skills"/p["skill"])
        assert valid,f"{p['skill']}: {message}"
        validated_skills.append(p["skill"])
else:
    raise RuntimeError("Skill-creator validator is absent; use its current installed location")

result=dict(valid=True,phases=len(phases),tasks=len(tasks),findings=len(review_ids),
            exactly_one_owner_per_finding=True,dependency_graph_acyclic=True,
            original_review_preserved=True,tracker_consistent=True,
            task_status_counts=dict(Counter(t['status'] for t in tasks)),
            local_markdown_links_checked=links,broken_local_links=broken,
            skills_validated=validated_skills,
            scope="Plan and skill structure only; no application implementation or acceptance inferred")
(HERE/"PLAN_VALIDATION.json").write_text(json.dumps(result,indent=2),encoding="utf-8")
print(json.dumps(result,indent=2))
