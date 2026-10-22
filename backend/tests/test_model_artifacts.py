"""Version/contract regression tests; tiny forests are test-only, never deployed."""
from copy import deepcopy
import json
import subprocess
import sys

import joblib
import numpy as np
import pandas as pd
import pytest
from fastapi.testclient import TestClient
from sklearn.ensemble import RandomForestClassifier
from sklearn.tree import DecisionTreeClassifier

from model_artifacts import (APPROVED_LABELS, BACKEND_DIR, FEATURES, METADATA_FILE,
                             ModelArtifactError, artifact_version, load_model_artifact,
                             save_training_artifact)


@pytest.fixture
def release(tmp_path, monkeypatch):
    monkeypatch.delenv('GEOSUSTAIN_EXPECTED_MODEL_VERSION', raising=False)
    # Numeric values only exercise serialization/contracts, not agronomic profiles.
    frame = pd.DataFrame(np.arange(520).reshape(52, 10), columns=FEATURES)
    labels = sorted(APPROVED_LABELS) * 4
    forest = RandomForestClassifier(n_estimators=2, random_state=42).fit(frame, labels)
    training = {
        'status': 'recorded', 'timestamp_utc': '2026-10-22T00:00:00+00:00',
        'random_seed': 42, 'script_sha256': 'a' * 64, 'dataset_sha256': 'b' * 64,
        'provenance': {'scope': 'test fixture only'},
        'evaluation': {'scope': 'serialization test; not evaluated for deployment'},
    }
    metadata = save_training_artifact(forest, FEATURES, training, {}, frame, tmp_path)
    return tmp_path, frame, labels, metadata


def change_metadata(directory, mutate):
    path = directory / METADATA_FILE
    metadata = json.loads(path.read_text(encoding='utf-8'))
    mutate(metadata)
    path.write_text(json.dumps(metadata), encoding='utf-8')


def test_training_publication_loads_exact_bytes_metadata_and_predictions(release):
    directory, frame, _, metadata = release
    loaded = load_model_artifact(directory, require_metadata=True)
    assert loaded.version == artifact_version((directory / 'crop_model.pkl').read_bytes())
    assert loaded.version == metadata['model_version']
    assert loaded.metadata == metadata
    assert loaded.metadata_status == 'recorded'
    np.testing.assert_allclose(loaded.model.predict_proba(frame),
                               joblib.load(directory / 'crop_model.pkl').predict_proba(frame))
    report = json.loads((directory / 'model_comparison_report.json').read_text())
    assert report['model_version'] == loaded.version
    assert loaded.health()['feature_contract']['names'] == FEATURES
    assert loaded.health()['supported_classes'] == sorted(APPROVED_LABELS)


@pytest.mark.parametrize('location', ['features_file', 'metadata', 'estimator'])
def test_feature_order_mismatch_rejected(release, location):
    directory, frame, labels, _ = release
    if location == 'features_file':
        joblib.dump(list(reversed(FEATURES)), directory / 'crop_model_features.pkl')
    elif location == 'metadata':
        change_metadata(directory, lambda m: m.update(feature_names=list(reversed(FEATURES))))
    else:
        reordered = RandomForestClassifier(n_estimators=2, random_state=42).fit(
            frame[list(reversed(FEATURES))], labels)
        joblib.dump(reordered, directory / 'crop_model.pkl')
    with pytest.raises(ModelArtifactError, match='feature order'):
        load_model_artifact(directory)


def test_missing_sidecar_is_explicit_legacy_and_can_be_required(release):
    directory, *_ = release
    (directory / METADATA_FILE).unlink()
    loaded = load_model_artifact(directory)
    assert loaded.metadata_status == 'missing_legacy'
    assert loaded.health()['training'] is None
    assert loaded.health()['warnings']
    with pytest.raises(ModelArtifactError, match='metadata is missing'):
        load_model_artifact(directory, require_metadata=True)


@pytest.mark.parametrize('change', ['missing_version', 'wrong_version', 'wrong_classes', 'incomplete_training'])
def test_invalid_present_metadata_never_silently_treated_as_legacy(release, change):
    directory, *_ = release
    mutations = {
        'missing_version': lambda m: m.pop('model_version'),
        'wrong_version': lambda m: m.update(model_version='old'),
        'wrong_classes': lambda m: m.update(classes=['rice']),
        'incomplete_training': lambda m: m['training'].pop('timestamp_utc'),
    }
    change_metadata(directory, mutations[change])
    with pytest.raises(ModelArtifactError):
        load_model_artifact(directory)


def test_stale_metadata_and_expected_version_reject_replacement(release):
    directory, frame, labels, metadata = release
    changed = RandomForestClassifier(n_estimators=3, random_state=7).fit(frame, labels)
    joblib.dump(changed, directory / 'crop_model.pkl')
    with pytest.raises(ModelArtifactError, match='version metadata'):
        load_model_artifact(directory)
    with pytest.raises(ModelArtifactError, match='EXPECTED_MODEL_VERSION'):
        load_model_artifact(directory, expected_version=metadata['model_version'])


def test_stale_process_requires_restart_then_fresh_load_has_new_version(release):
    directory, frame, labels, metadata = release
    old = load_model_artifact(directory)
    previous_prediction = old.model.predict_proba(frame)
    changed = RandomForestClassifier(n_estimators=3, random_state=7).fit(frame, labels)
    new = save_training_artifact(changed, FEATURES, metadata['training'], {}, frame, directory)
    assert old.health()['status'] == 'stale'
    assert old.health()['restart_required'] is True
    assert old.health()['model_version'] == metadata['model_version']
    assert old.health()['artifact_version_on_disk'] == new['model_version']
    np.testing.assert_allclose(old.model.predict_proba(frame), previous_prediction)
    fresh = load_model_artifact(directory, expected_version=new['model_version'])
    assert fresh.version != old.version
    assert fresh.health()['restart_required'] is False


def test_failed_staged_validation_does_not_replace_existing_release(release):
    directory, frame, _, metadata = release
    before = {p.name: p.read_bytes() for p in directory.iterdir()}
    with pytest.raises(ModelArtifactError, match='feature order'):
        save_training_artifact(load_model_artifact(directory).model, list(reversed(FEATURES)),
                               metadata['training'], {}, frame, directory)
    assert {p.name: p.read_bytes() for p in directory.iterdir()} == before


def test_comparison_estimator_cannot_replace_production_forest(release):
    directory, frame, labels, _ = release
    joblib.dump(DecisionTreeClassifier().fit(frame, labels), directory / 'crop_model.pkl')
    with pytest.raises(ModelArtifactError, match='RandomForestClassifier'):
        load_model_artifact(directory)


def test_expected_version_environment_rejects_stale_deployment(release, monkeypatch):
    directory, *_ = release
    monkeypatch.setenv('GEOSUSTAIN_EXPECTED_MODEL_VERSION', '0' * 64)
    with pytest.raises(ModelArtifactError, match='EXPECTED_MODEL_VERSION'):
        load_model_artifact(directory)


def test_backend_health_and_snapshot_prove_actual_repository_artifact(monkeypatch):
    import fastapi_app as api
    import rainfallDatasets as engine
    from model_explainability import forest_snapshot
    monkeypatch.setattr(api, 'init_db', lambda: None)
    expected = artifact_version((BACKEND_DIR / 'crop_model.pkl').read_bytes())
    assert engine.MODEL_VERSION == expected
    with TestClient(api.app) as client:
        for route in ('/health', '/api/health'):
            health = client.get(route).json()
            assert health['model']['model_version'] == expected
            assert health['model']['artifact_version_on_disk'] == expected
            assert health['model']['feature_contract']['names'] == FEATURES
            assert health['model']['metadata_status'] == 'legacy_unverified'
    inputs = dict(zip(FEATURES, [80, 47, 50, 27.5, 80, 6, 105, .6, 25, 2]))
    frame = pd.DataFrame([inputs], columns=FEATURES)
    probabilities = dict(zip(engine.MODEL.classes_, engine.MODEL.predict_proba(frame)[0]))
    snapshot = forest_snapshot(engine.MODEL, engine.MODEL_VERSION, inputs,
                               engine.MODEL.predict(frame)[0], probabilities)
    assert snapshot['model_version'] == snapshot['samples'][0]['model_version'] == expected


def test_health_reports_stale_and_unavailable_without_fabricated_version(release, monkeypatch):
    import fastapi_app as api
    import rainfallDatasets as engine
    directory, *_ = release
    loaded = load_model_artifact(directory)
    monkeypatch.setattr(engine, 'LOADED_MODEL', loaded)
    (directory / 'crop_model.pkl').write_bytes(b'replaced on disk')
    assert api.health()['status'] == 'degraded'
    assert api.health()['model']['restart_required'] is True
    monkeypatch.setattr(engine, 'LOADED_MODEL', None)
    monkeypatch.setattr(engine, 'MODEL_LOAD_ERROR', 'ModelArtifactError')
    assert api.health()['model']['status'] == 'unavailable'
    assert api.health()['model']['model_version'] is None


def test_history_keeps_original_model_version_after_model_replacement(monkeypatch):
    import database
    import rainfallDatasets as engine
    stored = {'model_version': 'old-artifact', 'model_explanation': {
        'model_version': 'old-artifact', 'samples': [{'model_version': 'old-artifact'}]}}
    original = deepcopy(stored)
    monkeypatch.setattr(engine, 'MODEL_VERSION', 'new-artifact')
    restored = database.enrich_history_rows([{'result_snapshot': stored}])[0]
    assert restored['model_version'] == restored['model_explanation']['model_version'] == 'old-artifact'
    assert stored == original


def test_training_guard_blocks_before_touching_artifacts_from_any_directory(tmp_path):
    files = ('crop_model.pkl', 'crop_model_features.pkl', METADATA_FILE,
             'Crop_recommendation_with_gis.csv')
    before = {f: artifact_version((BACKEND_DIR / f).read_bytes()) for f in files}
    process = subprocess.run([sys.executable, str(BACKEND_DIR / 'training' / 'train_model.py')],
                             cwd=tmp_path, capture_output=True, text=True, timeout=60)
    assert process.returncode != 0
    assert 'Climate training contract unresolved' in process.stderr
    assert {f: artifact_version((BACKEND_DIR / f).read_bytes()) for f in files} == before
    assert not list(tmp_path.iterdir())


def test_verification_command_works_outside_repository(release):
    directory, *_ = release
    version = artifact_version((BACKEND_DIR / 'crop_model.pkl').read_bytes())
    command = [sys.executable, str(BACKEND_DIR / 'verify_model.py'), '--expected-version', version]
    process = subprocess.run(command, cwd=directory, capture_output=True, text=True, timeout=60)
    assert process.returncode == 0, process.stderr
    assert json.loads(process.stdout)['model_version'] == version
    wrong = subprocess.run(command[:-1] + ['0' * 64], cwd=directory,
                           capture_output=True, text=True, timeout=60)
    assert wrong.returncode != 0
