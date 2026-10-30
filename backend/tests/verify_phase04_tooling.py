"""Repeatable Phase 4 verification; controlled research only, no deployment."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys

REPO = Path(__file__).resolve().parents[2]
EVIDENCE = REPO/'defense-evidence/capstone-fix-execution/phase-04'


def hashes(paths):
    return {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}


def main():
    timestamp = datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S-%f')
    attempt = EVIDENCE/'attempts'/timestamp
    attempt.mkdir(parents=True, exist_ok=False)
    run = EVIDENCE/'runs'/('verify-'+timestamp)
    baseline = json.loads((EVIDENCE/'baseline-source-hashes.json').read_text())['files']
    paths = [REPO/name for name in baseline]
    before = hashes(paths)
    checks, passed, error = [], False, None

    def check(name, arguments, expected_refusal=False):
        start = datetime.now(timezone.utc).isoformat()
        result = subprocess.run([sys.executable, *arguments], cwd=REPO, capture_output=True,
                                text=True, encoding='utf-8', errors='replace', timeout=300)
        log = attempt/(name+'.log')
        log.write_text(result.stdout+'\n'+result.stderr, encoding='utf-8')
        okay = (result.returncode != 0 and 'Climate training contract unresolved' in result.stderr
                if expected_refusal else result.returncode == 0)
        checks.append({'check': name, 'arguments': arguments, 'started_at_utc': start,
                       'ended_at_utc': datetime.now(timezone.utc).isoformat(),
                       'exit_code': result.returncode, 'expected_refusal': expected_refusal,
                       'passed': okay, 'log': str(log.relative_to(REPO))})
        if not okay:
            raise RuntimeError(f'{name} failed; see {log}')
        print('PASS:', name, flush=True)

    try:
        if any(before[str(REPO/name)] != expected for name, expected in baseline.items()):
            raise RuntimeError('Phase 4 protected model/data/training baseline changed; review identities before verifying.')
        sources = ['backend/training/evaluate_models.py', 'backend/training/controlled_fixture.py',
                   'backend/training/audit_model_evidence.py', 'backend/tests/test_model_evaluation.py',
                   'backend/tests/verify_phase04_tooling.py']
        check('python-static', ['-m', 'ruff', 'check', '--select', 'F', *sources])
        check('backend-tests', ['-m', 'pytest', 'backend/tests', '-q', '-p', 'no:cacheprovider'])
        check('model-data-audit', ['backend/training/audit_model_evidence.py', '--output', str(attempt/'audit')])
        check('controlled-input', ['backend/training/controlled_fixture.py', '--output', str(run/'inputs')])
        common = ['backend/training/evaluate_models.py', '--dataset', str(run/'inputs/controlled.csv'),
                  '--contract', str(run/'inputs/contract.json')]
        check('controlled-comparison', [*common, '--output', str(run/'evaluation')])
        check('controlled-replay', [*common, '--output', str(run/'replay'), '--reproduce', str(run/'evaluation/results.json')])
        check('unresolved-training-refused', ['backend/training/train_model.py'], expected_refusal=True)
        if before != hashes(paths):
            raise RuntimeError('Protected production model/data/training assets changed during verification.')
        passed = True
    except Exception as exc:
        error = str(exc)
        print('FAILED:', error, file=sys.stderr, flush=True)
    finally:
        unchanged = before == hashes(paths)
        passed = passed and unchanged
        result = {'recorded_at_utc': datetime.now(timezone.utc).isoformat(), 'passed': passed, 'error': error,
                  'source_commit': subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=REPO, capture_output=True, text=True).stdout.strip(),
                  'source_files': hashes([REPO/name for name in ('backend/training/evaluate_models.py',
                      'backend/training/controlled_fixture.py', 'backend/training/audit_model_evidence.py',
                      'backend/tests/test_model_evaluation.py', 'backend/tests/verify_phase04_tooling.py',
                      'deployment/verify-phase-04.ps1')]),
                  'checks': checks, 'protected_assets_unchanged': unchanged,
                  'attempt': str(attempt.relative_to(REPO)), 'controlled_run': str(run.relative_to(REPO)),
                  'scope': 'Local audit and deterministic controlled tooling verification only. No agricultural accuracy, Table 13 reproduction, production replacement, provider success or deployment implied.',
                  'deferred': 'Independent scientific inputs, compatible climate/nutrient data and final production selection remain in Phase 8; actual live runtime parity requires a successful separate probe.'}
        for path in (attempt/'tooling-validation.json', EVIDENCE/'tooling-validation.json'):
            path.write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
