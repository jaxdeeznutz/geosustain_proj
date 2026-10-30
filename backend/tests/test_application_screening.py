from copy import deepcopy

import pytest

from application_screening import attach_application_screening, VERSION, SOURCE
from model_ranking import attach_model_ranking


def record(humidity=80, ndvi=.65, crop='Banana'):
    return {'crop_assessments': [{'crop': crop}], 'environmental_measurements': {
        'humidity_current': {'value': humidity, 'unit': '%', 'period': 'current',
                             'quality': 'modelled', 'source': 'Controlled fixture'},
        'ndvi': {'value': ndvi, 'unit': 'index', 'period': 'latest_scene',
                 'quality': 'modelled', 'source': 'Controlled fixture'}}}


def saved(result):
    return attach_application_screening(result)['application_screening']['crops'][0]


@pytest.mark.parametrize('value,status', [(70, 'suitable'), (95, 'suitable'),
    (55, 'limited'), (100, 'limited'), (54.9, 'not_suitable'), (0, 'not_suitable')])
def test_current_humidity_inclusive_preferred_and_accepted_boundaries(value, status):
    check = saved(record(humidity=value))['factors']['humidity']
    assert check['status'] == status
    assert check['period'] == 'current'
    assert check['preferred'] == [70, 95]
    assert check['accepted'] == [55, 100]
    assert 'not a climate average' in check['interpretation']


@pytest.mark.parametrize('value,status', [(.45, 'suitable'), (.85, 'suitable'),
    (.25, 'limited'), (.95, 'limited'), (.249, 'not_suitable'), (.951, 'not_suitable'),
    (-1, 'not_suitable')])
def test_ndvi_is_a_separate_vegetation_condition_check(value, status):
    check = saved(record(ndvi=value))['factors']['ndvi']
    assert check['status'] == status
    assert 'not proof of crop suitability' in check['interpretation']


@pytest.mark.parametrize('key,value', [('humidity_current', None), ('humidity_current', 101),
    ('humidity_current', -1), ('ndvi', 1.01), ('ndvi', -1.01), ('ndvi', float('nan')),
    ('ndvi', float('inf')), ('ndvi', True), ('humidity_current', '80')])
def test_missing_or_invalid_readings_are_never_graded(key, value):
    result = record()
    result['environmental_measurements'][key]['value'] = value
    factor = 'humidity' if key == 'humidity_current' else 'ndvi'
    check = saved(result)['factors'][factor]
    assert check['status'] == 'unassessed'
    assert check['value'] is None


@pytest.mark.parametrize('key,field,value', [
    ('humidity_current', 'period', 'annual_mean'), ('humidity_current', 'unit', 'fraction'),
    ('humidity_current', 'quality', 'fallback_default'), ('ndvi', 'period', 'unknown'),
    ('ndvi', 'unit', '%'), ('ndvi', 'quality', 'unavailable')])
def test_only_compatible_observations_are_assessed(key, field, value):
    result = record()
    result['environmental_measurements'][key][field] = value
    factor = 'humidity' if key == 'humidity_current' else 'ndvi'
    assert saved(result)['factors'][factor]['status'] == 'unassessed'


def test_provenance_mapping_and_missing_crop_range_are_explicit():
    banana = saved(record())
    assert banana['profile_key'] == 'banana (cavendish/lakatan)'
    assert banana['source'] == SOURCE
    mango = saved(record(crop='Mango'))
    assert mango['profile_key'] is None
    assert all(f['status'] == 'unassessed' for f in mango['factors'].values())
    assert mango['factors']['ndvi']['value'] == .65
    assert set(banana['factors']) == {'humidity', 'ndvi'}  # Never add NPK grades.


def test_attachment_preserves_all_scores_crop_references_and_model_explanation():
    result = record()
    result['crop_assessments'][0]['factors'] = [{'factor': 'soil_ph', 'score': 100}]
    snapshot = {'model_version': 'test', 'samples': [
        {'class_probabilities': {'banana': .6, 'rice': .4}}]}
    attach_model_ranking(result, [snapshot])
    previous = deepcopy(result)
    attach_application_screening(result)
    screening = result.pop('application_screening')
    assert screening['version'] == VERSION
    assert screening['used_for_ranking'] is False
    assert result == previous
    # Saved measurement snapshots must not alias mutable input dictionaries.
    screening['crops'][0]['factors']['ndvi']['measurement']['value'] = 0
    assert result == previous


def test_no_crop_analysis_does_not_create_checks():
    result = {'land_status': 'Water'}
    assert attach_application_screening(deepcopy(result)) == result
