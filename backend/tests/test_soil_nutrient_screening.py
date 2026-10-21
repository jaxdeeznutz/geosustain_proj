"""Synthetic criteria test mechanics only; none are production agronomic ranges."""
from copy import deepcopy
import json

import pytest

from cagro_soil import lookup_soil_observations, nutrient_layers
from crop_requirements import NUTRIENT_REQUIREMENTS, REQUIREMENTS
from soil_nutrient_screening import screen_soil_nutrients, observation
from test_cagro_soil import square


def matched():
    return lookup_soil_observations(square(7.39242, 125.62293))


def synthetic_case(value):
    soil = matched()
    soil['observations'] = soil['observations'][:1]  # Test fixture, not production selection.
    soil['observations'][0]['estimated_nitrogen_pct'] = value
    observed = observation(soil['observations'][0], 'nitrogen')
    rule = {'source': {'title': 'Synthetic test fixture', 'citation': 'TEST ONLY, not an agricultural reference', 'section': None},
            'unit': observed['unit'], 'nutrient_definition': observed['nutrient_definition'],
            'method': observed['method'], 'limitations': 'Test mechanics only; never install in production',
            'optimal': [1, 2], 'absolute': [0, 3]}
    return soil, {'Rice': {'nitrogen': rule}}


@pytest.mark.parametrize('value,status', [(1.5, 'Suitable'), (2.5, 'Limited'), (4, 'Outside documented range'), (None, 'Not assessed')])
def test_compatible_fixture_statuses(value, status):
    soil, rules = synthetic_case(value)
    result = screen_soil_nutrients(soil, rules)
    factor = result['crops']['Rice']['records'][0]['factors'][0]
    assert factor['status'] == status
    assert factor['used_for_model_prediction'] is False


def test_production_has_no_invented_criteria_and_preserves_all_provenance():
    soil = matched()
    before = deepcopy(soil)
    result = screen_soil_nutrients(soil)
    assert set(NUTRIENT_REQUIREMENTS) == set(REQUIREMENTS)
    assert all(not rules for rules in NUTRIENT_REQUIREMENTS.values())
    assert soil == before
    for crop in result['crops'].values():
        assert crop['combined_status'] == 'Not assessed'
        assert len(crop['records']) == len(soil['observations']) == 4
        for record, row in zip(crop['records'], soil['observations']):
            assert record['provenance'] == row
            assert record['factors'][0]['value'] == row['estimated_nitrogen_pct']
            assert all(f['status'] == 'Not assessed' for f in record['factors'])
    assert 'Multiple historical' in result['message']


@pytest.mark.parametrize('field,value', [('unit', 'ppm'), ('method', None), ('nutrient_definition', 'total_nitrogen')])
def test_incompatible_criterion_not_assessed(field, value):
    soil, rules = synthetic_case(1.5)
    rules['Rice']['nitrogen'][field] = value
    factor = screen_soil_nutrients(soil, rules)['crops']['Rice']['records'][0]['factors'][0]
    assert factor['status'] == 'Not assessed'
    assert factor['requirement'] is None


def test_no_match_or_missing_association_is_unavailable():
    for soil in [lookup_soil_observations([]), {'status': 'unavailable', 'observations': matched()['observations']},
                 {'status': 'matched', 'observations': [{'id': 'missing-match'}]}]:
        result = screen_soil_nutrients(soil)
        assert result['status'] == 'unavailable'
        assert all(not c['records'] for c in result['crops'].values())


def test_unknown_methods_cannot_pass_and_no_absolute_range_is_not_invented():
    soil, rules = synthetic_case(4)
    rules['Rice']['nitrogen'].pop('absolute')
    assert screen_soil_nutrients(soil, rules)['crops']['Rice']['records'][0]['factors'][0]['status'] == 'Not assessed'
    rules['Rice']['nitrogen']['source'] = {}
    assert screen_soil_nutrients(soil, rules)['crops']['Rice']['records'][0]['factors'][0]['requirement'] is None


def test_reference_layer_does_not_change_ranking_model_inputs_or_saved_provenance():
    from model_ranking import attach_model_ranking
    from database import enrich_history_rows
    snapshot = {'model_version': 'test', 'status': 'unavailable', 'features': [],
                'samples': [{'inputs': {'N': 80, 'P': 47, 'K': 50},
                             'class_probabilities': {'rice': .4, 'banana': .6}}]}
    analysis = attach_model_ranking({}, [snapshot])
    before = deepcopy(analysis)
    soil = matched()
    analysis.update(cagro_soil=soil, **nutrient_layers(soil, analysis))
    for key in before:
        assert analysis[key] == before[key]
    restored = enrich_history_rows([{'result_snapshot': json.loads(json.dumps(analysis))}])[0]
    assert restored['soil_nutrient_reference'] == analysis['soil_nutrient_reference']
    assert restored['cagro_soil'] == soil
