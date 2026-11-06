"""Seven-crop migration experiments never bypass production measurement guards."""
from copy import deepcopy
import json

import numpy as np
import pandas as pd
import pytest

from crop_requirements import REQUIREMENTS
from model_artifacts import APPROVED_LABELS, FEATURES, ModelArtifactError, load_model_artifact
from training import train_seven_crop_candidate as candidate
from training import verify_seven_crop_candidate as verifier


@pytest.fixture
def legacy_rows(tmp_path):
    rows = []
    for index, label in enumerate(sorted(APPROVED_LABELS)):
        for j in range(16):
            # Serialization/leakage fixture only, not agronomic measurements.
            rows.append({**{name: float(index * 30 + j + k / 100)
                             for k, name in enumerate(FEATURES)}, 'label': label})
    path = tmp_path / 'legacy.csv'
    pd.DataFrame(rows + [deepcopy(rows[0])] * 3 + [{**rows[0], 'label': 'abaca'}]).to_csv(path, index=False)
    return path, rows


def test_model_scope_and_serving_catalog_share_exactly_the_seven_required_crops():
    expected = {'banana', 'coconut', 'rice', 'durian', 'mango', 'rubber', 'cacao'}
    assert APPROVED_LABELS == expected == {name.lower() for name in REQUIREMENTS}


def test_preparation_excludes_unapproved_rows_and_deduplicates_before_split(legacy_rows):
    path, rows = legacy_rows
    frame, audit = candidate.prepare_data(path)
    assert len(frame) == len(rows)
    assert audit['duplicate_rows_removed_before_split'] == 3
    assert audit['excluded_other_crop_rows'] == 1
    forest, metrics, splits = candidate.fit_candidate(frame, trees=3)
    assert set(forest.classes_) == APPROVED_LABELS
    train = set(map(tuple, frame.iloc[splits['train']][FEATURES].to_numpy()))
    test = set(map(tuple, frame.iloc[splits['holdout']][FEATURES].to_numpy()))
    assert not train & test
    assert len(train | test) == len(rows)
    assert all(np.asarray(item['confusion_matrix']).shape == (7, 7) for item in metrics.values())


@pytest.mark.parametrize('mutation,message', [
    ('missing_crop', 'every|exactly all seven'),
    ('missing_value', 'nonfinite'),
    ('conflicting_labels', 'conflicting'),
    ('missing_feature', 'all ten features'),
])
def test_bad_source_rows_fail_without_imputation_or_label_substitution(legacy_rows, mutation, message):
    path, rows = legacy_rows
    frame = pd.DataFrame(rows)
    if mutation == 'missing_crop':
        frame = frame[frame.label != 'mango']
    elif mutation == 'missing_value':
        frame.loc[0, 'N'] = np.nan
    elif mutation == 'conflicting_labels':
        row = frame.iloc[0].copy()
        row['label'] = 'rice'
        frame = pd.concat([frame, row.to_frame().T], ignore_index=True)
    else:
        frame = frame.drop(columns=['N'])
    frame.to_csv(path, index=False)
    with pytest.raises(ValueError, match=message):
        candidate.prepare_data(path)


def test_candidate_roundtrip_explanations_and_nonproduction_status(tmp_path, monkeypatch, legacy_rows):
    path, _ = legacy_rows
    protected = tmp_path / 'backend' / 'crop_model.pkl'
    protected.parent.mkdir()
    protected.write_bytes(b'Existing protected deployment artifact')
    monkeypatch.setattr(candidate, 'REPO', tmp_path)
    monkeypatch.setattr(candidate, 'OUTPUT_ROOT', tmp_path / 'research')
    monkeypatch.setattr(candidate, 'PROTECTED', (protected,))
    before = candidate.protected_hashes()
    output = candidate.OUTPUT_ROOT / 'fixture-run'
    report = candidate.train(path, output, trees=3)
    assert report['production_promotion_allowed'] is False
    assert report['checks']['production_artifacts_unchanged']
    assert report['checks']['saved_local_explanation'] == 'available'
    assert candidate.protected_hashes() == before
    assert any('Climate training contract unresolved' in item for item in report['promotion_blockers'])
    explanation = json.loads((output / 'synthetic_source_explanation.json').read_text())
    assert len(explanation['local_model_explanation']['class_order']) == 7
    assert {crop['crop'].lower() for crop in explanation['crop_assessments']} == APPROVED_LABELS
    monkeypatch.setattr(verifier, 'BACKEND', tmp_path / 'backend')
    monkeypatch.setattr(verifier, 'OUTPUT_ROOT', candidate.OUTPUT_ROOT)
    assert verifier.verify(output)['saved_explanation_verified']
    report_file = output / 'training_report.json'
    report_bytes = report_file.read_bytes()
    modified = deepcopy(report)
    modified['comparison']['random_forest']['accuracy'] += .01
    report_file.write_text(json.dumps(modified))
    with pytest.raises(ValueError, match='accuracy does not replay'):
        verifier.verify(output)
    report_file.write_bytes(report_bytes)
    # A candidate cannot be copied into production and mistaken for reviewed data.
    with pytest.raises(ModelArtifactError, match='training provenance status'):
        load_model_artifact(output)
    with pytest.raises(ValueError, match='already exists'):
        candidate.train(path, output, trees=3)


def test_output_rejects_production_and_unrelated_directories(tmp_path, legacy_rows):
    path, _ = legacy_rows
    before = candidate.protected_hashes()
    with pytest.raises(ValueError, match='production output is forbidden'):
        candidate.train(path, candidate.BACKEND)
    with pytest.raises(ValueError, match='production output is forbidden'):
        candidate.train(path, tmp_path / 'unrelated')
    assert candidate.protected_hashes() == before
