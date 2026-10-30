"""Validation and consumers for the controlled administration contract."""
from copy import deepcopy
from datetime import date, timedelta
import json
from pathlib import Path

import pytest
from pydantic import ValidationError
import controlled_records as records


def body(kind='crop_requirement', **overrides):
    payloads = {
        'crop_requirement': ('rice_rainfall', {'crop': 'rice', 'factor': 'rainfall', 'unit': 'mm/year', 'period': 'annual_mean_total',
            'preferred_min': 2000, 'preferred_max': 2500, 'absolute_min': 1000, 'absolute_max': 4000}),
        'planting_calendar': ('rice', {'crop': 'rice', 'months': [2, 8]}),
        'environmental_source': ('ndvi', {'layer': 'ndvi', 'source_id': records.LAYERS['ndvi']['source'], 'unit': 'index', 'period': 'latest_scene'}),
        'model_version': ('installed_model', {'sha256': 'a'*64}),
        'supporting_reference': ('reviewed_local_reference', {'applies_to': 'analysis', 'citation': 'Controlled software fixture, not agronomic evidence'}),
        'system_setting': ('analysis_sampling', {'sample_count': 5}),
    }
    key, payload = payloads[kind]
    return {'kind': kind, 'record_key': key, 'expected_revision': 0, 'title': 'Controlled test reference',
        'scope': 'Panabo City', 'evidence_url': 'https://example.org/controlled-fixture',
        'reference': 'Software test only', 'method': 'Synthetic reference contract test, not field validation',
        'valid_from': str(date.today()-timedelta(days=1)), 'valid_until': str(date.today()+timedelta(days=30)),
        'review_status': 'reviewed', 'review_note': 'Reviewed only as a software test fixture', 'payload': deepcopy(payload), **overrides}


def saved(value, index=1):
    doc = records.document(records.RecordBody(**value))
    return {'id': index, 'kind': doc['kind'], 'record_key': doc['record_key'], 'revision': 1,
            'document': doc, 'content_sha256': records.digest(doc), 'generation': 1}


@pytest.mark.parametrize('kind', records.KINDS)
def test_supported_typed_record_contracts(kind):
    parsed = records.RecordBody(**body(kind))
    assert records.document(parsed)['kind'] == kind
    assert 'expected_revision' not in records.document(parsed)


@pytest.mark.parametrize('change', [
    lambda b: b.update(secret_key='private'),
    lambda b: b.update(evidence_url='file:///private/model.pkl'),
    lambda b: b.update(evidence_url='https://user:password@example.org/reference'),
    lambda b: b.update(evidence_url='https://example.org/reference?token=secret'),
    lambda b: b.update(evidence_url='https://127.0.0.1/reference'),
    lambda b: b.update(valid_until='2000-01-01'),
    lambda b: b.update(review_note=''),
    lambda b: b['payload'].update(preferred_min=3000, preferred_max=2000),
    lambda b: b['payload'].update(absolute_min=2200),
    lambda b: b['payload'].update(preferred_min=True),
    lambda b: b['payload'].update(preferred_min=float('nan')),
    lambda b: b['payload'].update(unit='mm/30 days'),
    lambda b: b['payload'].update(period='selected_calendar_month'),
    lambda b: b['payload'].update(factor='nitrogen'),
    lambda b: b['payload'].update(crop='unapproved_crop'),
    lambda b: b['payload'].update(crop=[]),
    lambda b: b['payload'].update(factor={}),
])
def test_invalid_unreviewed_private_or_incompatible_requirements_rejected(change):
    value = body();change(value)
    with pytest.raises((ValidationError, ValueError)):
        records.RecordBody(**value)


@pytest.mark.parametrize('kind,delta', [
    ('planting_calendar', {'months': [1,1]}), ('planting_calendar', {'months': [0,13]}),
    ('planting_calendar', {'months': [True]}), ('system_setting', {'sample_count': 200}),
    ('system_setting', {'sample_count': True}), ('model_version', {'path': 'untrusted.pkl'}),
    ('environmental_source', {'source_id': 'https://attacker.example/private'}),
    ('environmental_source', {'unit': 'percent'}),
])
def test_unsafe_source_model_or_setting_contract_rejected(kind, delta):
    value = body(kind);value['payload'].update(delta)
    with pytest.raises(ValidationError): records.RecordBody(**value)


def test_consumers_use_saved_versions_without_changing_model_or_local_explanation():
    source = json.loads(Path('test/fixtures/local_analysis.json').read_text())
    before = deepcopy(source)
    active = [saved(body(k), i+1) for i,k in enumerate(records.KINDS) if k!='model_version']
    records.attach_controlled_records(source, active)
    rain = next(f for c in source['crop_assessments'] if c['crop']=='Rice' for f in c['factors'] if f['factor']=='rainfall')
    assert rain['requirement']['optimal'] == [2000,2500]
    assert rain['requirement']['controlled_revision'] == 1
    assert source['seasonal_assessment']['calendar']['crops'][0]['selected_month_listed'] is False
    ndvi = next(v for v in source['spatial_assessment']['layers'] if v['id']=='ndvi')
    assert ndvi['controlled_source_reference']['revision'] == 1
    assert source['supporting_references'][0]['document']['payload']['citation']
    for key in ['model_explanation', 'local_model_explanation', 'crop_compatibility_pct', 'predicted_crop', 'nitrogen', 'phosphorus', 'potassium']:
        assert source[key] == before[key],key
    for current, old in zip(source['crop_assessments'], before['crop_assessments']):
        assert current['compatibility_pct'] == old['compatibility_pct']
    frozen = deepcopy(source['configuration_snapshot'])
    active[0]['document']['payload']['preferred_min'] = 123
    assert source['configuration_snapshot'] == frozen


def test_no_active_records_preserves_default_nine_samples_and_existing_evidence():
    result = {'crop_assessments': [], 'model_explanation': {'saved': True}}
    records.attach_controlled_records(result, [])
    assert result['model_explanation'] == {'saved': True}
    assert result['configuration_snapshot']['parcel_sample_limit'] == 9


@pytest.mark.parametrize('role', ['farmer','agricultural_planning_analyst'])
def test_non_admin_roles_cannot_read_create_or_activate(client, role, monkeypatch):
    import fastapi_app as api
    api.app.dependency_overrides[api.get_api_user] = lambda: {'id': 10, 'role': role}
    monkeypatch.setattr(records, 'list_records', lambda *a: pytest.fail('Unauthorized database read'))
    assert client.get('/api/admin/controlled-records').status_code == 403
    assert client.get('/api/admin/controlled-records/catalog').status_code == 403
    assert client.post('/api/admin/controlled-records', json=body()).status_code == 403
    assert client.post('/api/admin/controlled-records/activation', json={'record_id':1,'expected_generation':0}).status_code == 403
