from copy import deepcopy

import pytest

from nutrient_contract import legacy_inputs, model_values, recorded_inputs, UNIT
from model_ranking import ModelRankingUnavailable
from cagro_soil import nutrient_layers, lookup_soil_observations


def contract():
    return legacy_inputs(80, 47, 50, 'measured', 'SoilGrids 2.0 nitrogen')


@pytest.mark.parametrize('field,value', [('unit', 'ppm'), ('unit', '%'),
    ('compatible', False), ('value', None), ('value', float('nan')),
    ('quality', 'measured'), ('contract_version', 'unknown'), ('method', None)])
def test_rejects_incompatible_or_missing_input(field, value):
    nutrients = contract()
    nutrients['P'][field] = value
    with pytest.raises(ModelRankingUnavailable):
        model_values(nutrients)


def test_missing_nutrient_rejected():
    nutrients = contract()
    del nutrients['N']
    with pytest.raises(ModelRankingUnavailable):
        model_values(nutrients)


def test_unavailable_nitrogen_is_not_admitted_even_with_numeric_placeholder():
    with pytest.raises(ModelRankingUnavailable):
        model_values(legacy_inputs(80, 47, 50, 'unavailable', 'Unavailable'))


def test_legacy_values_unchanged_but_never_claim_measurement_or_scientific_compatibility():
    nutrients = contract()
    assert model_values(nutrients) == {'N': 80, 'P': 47, 'K': 50}
    assert all(n['quality'] == 'estimated_proxy' and n['unit'] == UNIT
               and n['scientific_compatibility'] == 'unverified' and n['date'] is None
               for n in nutrients.values())
    assert legacy_inputs(80, 47, 50, 'fallback_default', 'Regional default')['N']['quality'] == 'fallback_default'


@pytest.mark.parametrize('matched', [True, False])
def test_cagro_cannot_replace_recorded_model_inputs(matched):
    polygon = [{'lat': 7.39242 + dy, 'lng': 125.62293 + dx}
               for dy, dx in [(-.0001, -.0001), (-.0001, .0001), (.0001, .0001), (.0001, -.0001)]]
    soil = lookup_soil_observations(polygon if matched else [])
    analysis = {'model_explanation': {'model_version': 'test', 'samples': [
        {'inputs': model_values(contract()), 'model_nutrient_inputs': contract()}]}}
    before = deepcopy(analysis)
    layers = nutrient_layers(soil, analysis)
    assert analysis == before
    assert bool(layers['soil_nutrients_observed']['records']) == matched
    assert layers['soil_nutrients_observed']['used_for_prediction'] is False
    assert layers['model_nutrient_inputs']['samples'][0]['nutrients'] == contract()
    for row in layers['soil_nutrients_observed']['records']:
        with pytest.raises(ModelRankingUnavailable):
            model_values(dict(zip(('N', 'P', 'K'), (row['nitrogen'], row['phosphorus'], row['potassium']))))


def test_history_does_not_reconstruct_contract():
    assert recorded_inputs([{'inputs': {'N': 80, 'P': 47, 'K': 50}}])['samples'] == []
    from database import enrich_history_rows
    saved = {'model_nutrient_inputs': recorded_inputs([{'model_nutrient_inputs': contract()}])}
    assert enrich_history_rows([{'result_snapshot': saved}])[0]['model_nutrient_inputs'] == saved['model_nutrient_inputs']


def test_incompatible_contract_never_reaches_forest(monkeypatch):
    import rainfallDatasets as env
    from unittest.mock import Mock
    forest = Mock()
    monkeypatch.setattr(env, 'MODEL', forest)
    nutrients = contract()
    nutrients['N']['unit'] = '%'
    with pytest.raises(ModelRankingUnavailable):
        env.get_ai_prediction(80, 47, 50, 27, 80, 6, 100, .6, 25, 2,
                              nutrient_inputs=nutrients)
    forest.predict.assert_not_called()
    forest.predict_proba.assert_not_called()


@pytest.mark.parametrize('source,method', [('SoilGrids', 'raw / 100.0'), ('OpenLandMap', 'raw * 0.7')])
def test_provider_method_is_recorded_without_new_conversion(source, method):
    entry = legacy_inputs(80, 47, 50, 'estimated_proxy', source)['N']
    assert method in entry['method']
    assert entry['value'] == 80
