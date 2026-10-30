"""Formal admission policy; fixture boundaries are not production geography."""
import json
from copy import deepcopy
from unittest.mock import Mock
import pytest
from test_mobile_workflow import api
from test_cagro_soil import square, boundary
import cagro_soil
from analysis_coverage import check_coverage, coverage_catalog, farm_coverage, VERSION
from geometry import polygon_centroid


@pytest.fixture(autouse=True)
def clean_boundary_config(monkeypatch):
    monkeypatch.delenv('CAGRO_LOCALITY_BOUNDARIES_PATH', raising=False)
    monkeypatch.setenv('CAGRO_REFERENCE_ENABLED', '1')


@pytest.mark.parametrize('lat,lon,supported', [(7.39242,125.62293,True), (7.29811,125.66111,True), (7.29,125.62,False), (7.39163,125.59919,False)])
def test_existing_coverage_only(lat, lon, supported):
    coverage, soil = check_coverage(square(lat, lon))
    assert coverage['supported'] is supported
    assert coverage['used_for_model_prediction'] is False
    assert bool(soil['observations']) is supported
    if not supported:
        assert coverage['nutrient_source'] is None


def test_full_boundary_required_and_no_new_radius():
    assert not check_coverage(square(7.39242,125.62293,.004))[0]['supported']
    catalog = coverage_catalog()
    assert len(catalog['reference_locations']) == 2
    assert catalog['boundaries'] == []


def test_reviewed_boundary_priority_and_crossing(tmp_path, monkeypatch):
    ring = [[125.622,7.392],[125.624,7.392],[125.624,7.394],[125.622,7.394],[125.622,7.392]]
    path = tmp_path / 'fixture.json'
    path.write_text(json.dumps({'features': [boundary('dapco', ring)]}))
    monkeypatch.setenv('CAGRO_LOCALITY_BOUNDARIES_PATH', str(path))
    coverage, _ = check_coverage(square(7.393,125.623))
    assert coverage['supported']
    assert all(m['match']['method'] == 'verified_locality_boundary' for m in coverage['matches'])
    assert not check_coverage(square(7.392,125.62293))[0]['supported']
    # Crossing and too far from the mapped anchor cannot fall back to proximity.
    assert not check_coverage(square(7.394,125.624,.001))[0]['supported']
    assert len(coverage_catalog()['boundaries']) == 1


def test_missing_records_never_produce_coverage(monkeypatch):
    read = cagro_soil._read
    monkeypatch.setattr(cagro_soil, '_read', lambda path: [] if str(path).endswith('cagro_observations.json') else read(path))
    assert not check_coverage(square(7.39242,125.62293))[0]['supported']
    assert not coverage_catalog()['reference_locations']


def test_centroid_uses_area_not_vertex_average():
    ring = [{'lat':7.29,'lng':125.62}, {'lat':7.29,'lng':125.621}, {'lat':7.29,'lng':125.624}, {'lat':7.294,'lng':125.624}, {'lat':7.294,'lng':125.62}]
    for points in [ring, ring+[ring[0]], list(reversed(ring))]:
        assert polygon_centroid(points) == pytest.approx((7.292,125.622))
    row = {'polygon': ring, 'center_lat': 0}
    before = deepcopy(row)
    assert farm_coverage(row)['center_lat'] == pytest.approx(7.292)
    assert row == before


def test_preflight_allows_model_estimates_independently_of_cagro_coverage(client, monkeypatch):
    infer = Mock(side_effect=AssertionError('No model/provider call allowed'))
    monkeypatch.setattr(api, 'analyze_location', infer)
    monkeypatch.setattr(api, 'screen_land_cover', infer)
    polygon = square(7.29,125.62)
    response = client.post('/api/mobile/analysis-coverage', json={'polygon':polygon})
    assert response.json()['analysis_coverage']['supported'] is False
    assert response.json()['analysis_coverage']['preliminary_supported'] is True
    assert response.json()['analysis_coverage']['can_analyze'] is True
    assert response.json()['analysis_coverage']['analysis_mode'] == 'legacy_model_estimates'
    infer.assert_not_called()
    supported = client.post('/api/mobile/analysis-coverage', json={'polygon':square(7.39242,125.62293)}).json()
    assert supported['analysis_coverage']['supported']
    assert supported['center_lat'] == pytest.approx(7.39242)
    assert len(client.get('/api/mobile/analysis-coverage/catalog').json()['reference_locations']) == 2


def test_web_cannot_bypass_with_supported_client_polygon(client, monkeypatch):
    monkeypatch.setattr(api, 'find_analysis_request', lambda *args: None)
    monkeypatch.setattr(api, 'current_user', lambda request: {'id':10, 'role':'farmer'})
    monkeypatch.setattr(api, 'get_farm_parcel', lambda *a: {'id':1,'farm_name':'Farm', 'boundary_version':1, 'polygon':square(7.29,125.53)})
    infer = Mock()
    monkeypatch.setattr(api, 'analyze_location', infer)
    response = client.post('/api/analysis', headers={'Idempotency-Key':'coverage-guard-test'}, json={'farm_id':1,'polygon':square(7.39242,125.62293), 'analysis_coverage':{'supported':True}})
    assert response.status_code == 400
    infer.assert_not_called()


def test_mobile_uses_stored_unsupported_farm_even_if_client_claims_coverage(client, monkeypatch):
    monkeypatch.setattr(api, 'get_farm_parcel', lambda *a: {'id':1,'farm_name':'Farm', 'boundary_version':1, 'polygon':square(7.29,125.53)})
    infer = Mock()
    monkeypatch.setattr(api, 'analyze_location', infer)
    response = client.post('/api/mobile/analysis', json={'farm_id':1,'polygon':square(7.39242,125.62293), 'analysis_coverage':{'supported':True}})
    assert response.status_code == 400
    infer.assert_not_called()


def test_snapshot_preserves_version_coverage_provenance_and_legacy():
    from database import enrich_history_rows
    coverage, soil = check_coverage(square(7.39242,125.62293))
    snapshot = {'analysis_schema_version':VERSION, 'analysis_coverage':coverage,'cagro_soil':soil}
    restored = enrich_history_rows([{'result_snapshot':deepcopy(snapshot)}])[0]
    for key in snapshot:
        assert restored[key] == snapshot[key]
    legacy = enrich_history_rows([{'result_snapshot':{'nitrogen':80}}])[0]
    assert legacy['nitrogen'] == 80 and 'analysis_coverage' not in legacy
