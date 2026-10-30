"""Evaluation leakage/replay/publication regressions; no crop/field validation."""
from copy import deepcopy
import json
from unittest.mock import patch

import numpy as np
import pytest
from sklearn.metrics import accuracy_score, precision_recall_fscore_support

from training import evaluate_models as evaluation
from training.controlled_fixture import make_fixture
from training.climate_training_contract import validate_training_periods


@pytest.fixture(scope='module')
def controlled(tmp_path_factory):
    parent = tmp_path_factory.mktemp('evaluation-inputs')
    with patch.object(evaluation, 'OUTPUT_ROOTS', (parent,)):
        dataset, contract = make_fixture(parent/'fixture')
    return dataset, contract


@pytest.fixture(scope='module')
def evaluated(controlled):
    dataset, contract = controlled
    config = evaluation.Config(cv_folds=3, bootstrap_replicates=80, forest_trees=12)
    report, splits = evaluation.evaluate(dataset, contract, config)
    return report, splits, config


def test_duplicate_features_and_declared_units_form_transitive_components(controlled):
    dataset, contract = controlled
    frame, sha, _ = evaluation.read_data(dataset, contract)
    groups, _, _ = evaluation.independent_groups(frame, contract, sha)
    assert len(set(groups)) == 89
    assert len(set(groups[:8])) == 1
    frame.loc[8, evaluation.FEATURES] = frame.loc[4, evaluation.FEATURES]
    groups, _, _ = evaluation.independent_groups(frame, contract, sha)
    assert len(set(groups[:12])) == 1
    assert len(set(groups)) == 88


def test_all_algorithms_share_the_same_leakage_free_holdout_and_cv(evaluated):
    report, splits, _ = evaluated
    train = [r for r in splits['records'] if r['role'] == 'train']
    holdout = [r for r in splits['records'] if r['role'] == 'holdout']
    assert not {r['group_key'] for r in train} & {r['group_key'] for r in holdout}
    assert not {r['feature_hash'] for r in train} & {r['feature_hash'] for r in holdout}
    expected = {r['record_key'] for r in holdout}
    assert len(expected) == report['support']['holdout']['rows']
    records = {r['record_key']: r for r in splits['records']}
    for name in evaluation.MODEL_NAMES:
        assert {r['record_key'] for r in report['models'][name]['predictions']} == expected
        assert len(report['cv'][name]['folds']) == len(splits['cv'])
    for fold in splits['cv']:
        a, b = [records[k] for k in fold['train_keys']], [records[k] for k in fold['validation_keys']]
        assert not {r['group_key'] for r in a} & {r['group_key'] for r in b}
        assert not {r['feature_hash'] for r in a} & {r['feature_hash'] for r in b}
        assert set(fold['train_keys']+fold['validation_keys']) == {r['record_key'] for r in train}
        assert not expected & set(fold['train_keys']+fold['validation_keys'])


def test_scaler_fits_training_rows_only_in_outer_and_every_inner_fold(controlled, evaluated):
    dataset, contract = controlled
    report, splits, _ = evaluated
    frame, sha, _ = evaluation.read_data(dataset, contract)
    _, keys, _ = evaluation.independent_groups(frame, contract, sha)
    positions = {key: i for i, key in enumerate(keys)}
    rows = [positions[r['record_key']] for r in splits['records'] if r['role'] == 'train']
    scaler = report['models']['svm']
    np.testing.assert_allclose(scaler['scaler_mean'], frame.iloc[rows][evaluation.FEATURES].mean().to_numpy())
    assert scaler['scaler_samples_seen'] == len(rows)
    assert not np.allclose(scaler['scaler_mean'], frame[evaluation.FEATURES].mean().to_numpy())
    for fitted, fold in zip(report['cv']['svm']['folds'], splits['cv']):
        subset = [positions[k] for k in fold['train_keys']]
        np.testing.assert_allclose(fitted['scaler_mean'], frame.iloc[subset][evaluation.FEATURES].mean().to_numpy())
        assert fitted['scaler_samples_seen'] == len(subset)


def test_known_imbalanced_confusion_matrix_metrics_and_weighted_f1():
    matrix = [[40, 10], [0, 5]]
    got = evaluation.metrics_from_matrix(matrix)
    true = ['a']*50+['b']*5
    predicted = ['a']*40+['b']*15
    precision, recall, macro, _ = precision_recall_fscore_support(true, predicted, average='macro')
    _, _, weighted, _ = precision_recall_fscore_support(true, predicted, average='weighted')
    assert got == pytest.approx({'accuracy': accuracy_score(true, predicted), 'precision_macro': precision,
                                 'recall_macro': recall, 'f1_macro': macro, 'f1_weighted': weighted})
    assert got['accuracy'] == pytest.approx(45/55)
    assert got['precision_macro'] == pytest.approx(2/3)
    assert got['recall_macro'] == pytest.approx(.9)
    assert got['f1_macro'] != got['f1_weighted']


def test_all_metrics_support_confusion_uncertainty_and_timing_are_recorded(evaluated):
    report, _, config = evaluated
    for row in report['models'].values():
        assert set(row['metrics']) == set(evaluation.METRICS)
        matrix = np.asarray(row['confusion_matrix'])
        assert matrix.sum() == report['support']['holdout']['rows']
        for i, label in enumerate(row['class_order']):
            assert row['per_class'][label]['support'] == matrix[i].sum()
        assert row['fit_seconds'] >= 0 and row['predict_seconds'] >= 0
        assert row['uncertainty']['replicates'] == config.bootstrap_replicates
        for interval in row['uncertainty']['metrics'].values():
            assert 0 <= interval['lower'] <= interval['upper'] <= 1
    assert report['selection']['holdout_used_for_selection'] is False
    assert report['selection']['production_changed'] is False


def test_selection_can_choose_decision_tree_instead_of_assuming_forest():
    cv = {name: {'mean': {'f1_macro': value, 'accuracy': .5}}
          for name, value in [('decision_tree', .9), ('svm', .8), ('random_forest', .7)]}
    assert evaluation.select_model(cv) == 'decision_tree'
    for value in cv.values():
        value['mean']['f1_macro'] = .8
    assert evaluation.select_model(cv) == 'decision_tree'


def test_replay_preserves_splits_predictions_metrics_ci_and_scaler_state(controlled, evaluated):
    report, splits, config = evaluated
    other, other_splits = evaluation.evaluate(*controlled, config)
    assert splits == other_splits
    assert report['reproducibility_sha256'] == other['reproducibility_sha256']
    assert evaluation.reproducible_result(report) == evaluation.reproducible_result(other)
    assert report['models']['svm']['fit_seconds'] != other['models']['svm']['fit_seconds']


def test_contract_hash_feature_period_and_scientific_guards(controlled):
    dataset, contract = controlled
    wrong = deepcopy(contract); wrong['dataset_sha256'] = '0'*64
    with pytest.raises(evaluation.EvaluationError, match='schema/hash'):
        evaluation.read_data(dataset, wrong)
    wrong = deepcopy(contract); wrong['feature_order'].reverse()
    with pytest.raises(evaluation.EvaluationError, match='feature order'):
        evaluation.read_data(dataset, wrong)
    wrong = deepcopy(contract); wrong['purpose'] = 'scientific_evaluation'; wrong['data_basis'] = 'documented_independent_records'
    with pytest.raises(evaluation.EvaluationError, match='unresolved'):
        evaluation.read_data(dataset, wrong)
    for item in wrong['features'].values():
        item.update(unit='documented_unit', method='Measured using source protocol', period='source_period')
    wrong['measurement_review'] = {'status': 'documented_compatible', 'reference': 'test-only record', 'reviewer': 'fixture', 'date': '2026-10-29'}
    wrong['climate_sources'] = {'unknown_csv': {'rainfall': None, 'temperature': None, 'humidity': None}}
    with pytest.raises(ValueError, match='Climate training contract unresolved'):
        evaluation.read_data(dataset, wrong)
    with pytest.raises(ValueError, match='unresolved'):
        validate_training_periods()


@pytest.mark.parametrize('change', ['nonfinite', 'reused_id', 'no_group', 'crop_target'])
def test_invalid_observations_are_rejected_without_filling_or_relabeling(controlled, tmp_path, change):
    dataset, contract = controlled
    frame, _, _ = evaluation.read_data(dataset, contract)
    if change == 'nonfinite':
        frame.loc[0, 'N'] = np.nan
    elif change == 'reused_id':
        frame.loc[1, 'observation_id'] = frame.loc[0, 'observation_id']
    elif change == 'no_group':
        frame.loc[0, 'independent_unit'] = ''
    else:
        frame.loc[0, 'label'] = 'rice'
    path = tmp_path/'invalid.csv';frame.to_csv(path, index=False)
    contract = {**contract, 'dataset_sha256': evaluation.file_hash(path)}
    with pytest.raises(evaluation.EvaluationError):
        evaluation.read_data(path, contract)


def test_insufficient_independent_groups_fail_instead_of_falling_back_to_row_split(controlled):
    dataset, contract = controlled
    frame, sha, _ = evaluation.read_data(dataset, contract)
    frame['independent_unit'] = frame['label']
    with pytest.raises(evaluation.EvaluationError, match='independent connected groups'):
        evaluation.partitions(frame, contract, sha, evaluation.Config())


def test_output_cannot_publish_models_overwrite_history_or_write_into_backend(evaluated, controlled, tmp_path, monkeypatch):
    report, splits, _ = evaluated
    before = {str(p): evaluation.file_hash(p) for p in evaluation.PROTECTED}
    with pytest.raises(evaluation.EvaluationError, match='production paths'):
        evaluation.write_run(evaluation.BACKEND, report, splits, controlled[1])
    monkeypatch.setattr(evaluation, 'OUTPUT_ROOTS', (tmp_path,))
    out = tmp_path/'new-run'
    evaluation.write_run(out, report, splits, controlled[1])
    assert not any(p.suffix == '.pkl' for p in out.iterdir())
    assert {p.name for p in out.iterdir()} == {'results.json', 'splits.json', 'contract.json', 'comparison.csv', 'comparison.md', 'files.json'}
    assert json.loads((out/'results.json').read_text())['purpose'] == 'controlled_fixture'
    old = (out/'results.json').read_bytes()
    with pytest.raises(evaluation.EvaluationError, match='already exists'):
        evaluation.write_run(out, report, splits, controlled[1])
    assert (out/'results.json').read_bytes() == old
    assert before == {str(p): evaluation.file_hash(p) for p in evaluation.PROTECTED}
    assert 'NOT AGRICULTURAL VALIDATION' in (out/'comparison.md').read_text()


def test_configuration_is_bounded():
    for config in (evaluation.Config(seed=-1), evaluation.Config(cv_folds=1),
                   evaluation.Config(forest_trees=10000), evaluation.Config(bootstrap_replicates=0)):
        with pytest.raises(evaluation.EvaluationError):
            config.validate()


def test_scientific_contract_rejects_incompatible_known_units_without_conversion(controlled):
    dataset, contract = controlled
    contract = deepcopy(contract)
    contract.update(purpose='scientific_evaluation', data_basis='documented_independent_records',
                    measurement_review={'status': 'documented_compatible', 'reference': 'test-only review',
                                        'reviewer': 'fixture validator', 'date': '2026-10-29'},
                    climate_sources={'test-source': {'rainfall': 'rolling_30_days', 'temperature': 'annual_mean', 'humidity': 'current'}})
    units = {'N': 'documented_nutrient_unit', 'P': 'documented_nutrient_unit', 'K': 'documented_nutrient_unit',
             'rainfall': 'mm', 'temperature': 'C', 'humidity': '%', 'ph': 'pH', 'ndvi': 'index', 'elevation': 'm', 'slope': '%'}
    for name, item in contract['features'].items():
        item.update(unit=units[name], method='Recorded source measurement protocol', period='source_period')
    for name, period in contract['climate_sources']['test-source'].items():
        contract['features'][name]['period'] = period
    contract['features']['temperature']['unit'] = 'F'
    with pytest.raises(evaluation.EvaluationError, match='temperature unit must be explicitly C'):
        evaluation.read_data(dataset, contract)
