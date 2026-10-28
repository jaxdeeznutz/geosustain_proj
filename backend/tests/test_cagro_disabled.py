"""Temporary CAGRO switch affects new requests, never stored historical evidence."""
from copy import deepcopy
from unittest.mock import Mock

import cagro_soil
from analysis_coverage import check_coverage, coverage_catalog, require_point_coverage
from test_cagro_soil import square


def test_default_off_skips_matching_and_catalog_reads_even_in_mapped_area(monkeypatch):
    monkeypatch.delenv('CAGRO_REFERENCE_ENABLED', raising=False)
    lookup = Mock(side_effect=AssertionError('Disabled matching must not run'))
    read = Mock(side_effect=AssertionError('Disabled catalogue must not read soil files'))
    monkeypatch.setattr(cagro_soil, 'lookup_soil_observations', lookup)
    monkeypatch.setattr(cagro_soil, '_read', read)
    coverage, soil = check_coverage(square(7.39242, 125.62293))
    assert coverage['can_analyze'] and not coverage['cagro_enabled']
    assert not coverage['supported'] and coverage['matches'] == []
    assert soil['status'] == 'disabled' and soil['observations'] == []
    assert require_point_coverage(7.29, 125.62)[1]['status'] == 'disabled'
    catalog = coverage_catalog()
    assert catalog['reference_locations'] == catalog['boundaries'] == []
    assert catalog['city_boundary'] and catalog['cagro_enabled'] is False
    lookup.assert_not_called()
    read.assert_not_called()


def test_explicit_enable_restores_reference_without_using_it_for_model(monkeypatch):
    monkeypatch.setenv('CAGRO_REFERENCE_ENABLED', '1')
    monkeypatch.delenv('CAGRO_LOCALITY_BOUNDARIES_PATH', raising=False)
    coverage, soil = check_coverage(square(7.39242, 125.62293))
    assert coverage['cagro_enabled'] and coverage['supported']
    assert coverage['used_for_model_prediction'] is False
    assert soil['status'] == 'matched'


def test_disabling_does_not_rewrite_historical_snapshots(monkeypatch):
    from database import enrich_history_rows
    monkeypatch.setenv('CAGRO_REFERENCE_ENABLED', '0')
    saved = {'cagro_soil': {'status': 'matched', 'observations': [{'nitrogen_pct': .09}]},
             'land_cover': {'status': 'unknown', 'allow_crops': False},
             'is_crop_recommended': False}
    result = enrich_history_rows([{'result_snapshot': deepcopy(saved)}])[0]
    assert all(result[key] == value for key, value in saved.items())
