"""Synthetic SOFTWARE fixtures only; no cultivar observations are manufactured."""
import hashlib
import importlib.util
import json
from pathlib import Path
import numpy as np
import pandas as pd
import pytest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('variety_training_under_test', HERE/'train_banana_varieties.py')
trainer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(trainer)


def fixture(tmp_path):
    rng = np.random.default_rng(42)
    rows = []
    for i, variety in enumerate(trainer.VARIETIES):
        for site in range(8):
            for sample in range(2):
                rows.append(dict(temperature=25+i+rng.uniform(0,.1),humidity=75+i,
                    ph=5.5+i*.1,rainfall=2000+i*100,ndvi=.65+i*.05,
                    elevation=20+site,slope=2+site*.1,variety=variety,
                    site_id=f'synthetic-{variety}-{site}',record_id=f'{variety}-{site}-{sample}',
                    observed_at='2026-01-01',source='Synthetic software-test fixture; not a real farm'))
    path=tmp_path/'data.csv';pd.DataFrame(rows).to_csv(path,index=False)
    contract=dict(dataset_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                  target='observed_banana_variety',data_basis='synthetic_software_test_fixture',
                  units=trainer.UNITS,periods=trainer.PERIODS)
    meta=tmp_path/'contract.json';meta.write_text(json.dumps(contract),encoding='utf-8')
    return path,meta


def test_empty_template_never_becomes_a_trained_variety_model(tmp_path):
    path=tmp_path/'empty.csv';path.write_text(','.join(trainer.COLUMNS)+'\n')
    assert trainer.readiness(path)['variety_counts']==dict(cavendish=0,lakatan=0,saba=0)
    with pytest.raises(ValueError,match='No complete matched variety dataset'):
        trainer.train(path,tmp_path/'missing-contract.json',tmp_path/'output',trees=2)
    assert not (tmp_path/'output').exists()


def test_three_algorithms_keep_sites_apart_and_report_observed_target(tmp_path):
    path,meta=fixture(tmp_path)
    output,report=trainer.train(path,meta,tmp_path/'research',trees=2)
    assert set(r['model'] for r in report['comparisons'])=={'decision_tree','svm','random_forest'}
    parts=pd.read_csv(output/'split_assignments.csv')
    assert not set(parts[parts.partition=='train'].site_id) & set(parts[parts.partition=='holdout'].site_id)
    assert report['contract']['data_basis']=='synthetic_software_test_fixture'
    assert report['contract']['target']=='observed_banana_variety'
    assert not report['production_model_changed'] and not report['application_integration_ready']
    assert 'not a validated best-variety' in report['limitation']


def test_changed_data_cannot_bypass_source_review(tmp_path):
    path,meta=fixture(tmp_path)
    path.write_bytes(path.read_bytes()+b'\n')
    with pytest.raises(ValueError,match='hash'):
        trainer.prepare(path,meta)


def test_wrong_periods_are_not_silently_accepted(tmp_path):
    path,meta=fixture(tmp_path)
    contract=json.loads(meta.read_text());contract['periods']['rainfall']='rolling_30_days'
    meta.write_text(json.dumps(contract))
    with pytest.raises(ValueError,match='periods'):
        trainer.prepare(path,meta)
