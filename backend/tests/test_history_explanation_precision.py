"""SQL summary precision must never change a saved model explanation binding."""
from copy import deepcopy
from decimal import Decimal

from database import enrich_history_rows
from crop_requirements import REQUIREMENTS
from suitability import assess


def test_joined_rounded_score_does_not_overwrite_inference_snapshot():
    saved = {'crop_compatibility_pct': 31.772727272727273,
             'predicted_crop': 'Banana', 'model_version': 'recorded-model',
             'prediction_context_id': 'saved-context',
             'local_model_explanation': {'selected_score': 31.772727272727273}}
    before = deepcopy(saved)
    restored = enrich_history_rows([{'session_id': 41, 'verification_status': 'verified',
        'compatibility_pct': Decimal('31.77'), 'result_snapshot': saved}])[0]
    assert restored['crop_compatibility_pct'] == saved['local_model_explanation']['selected_score']
    assert restored['compatibility_pct'] == saved['crop_compatibility_pct']
    assert restored['verification_status'] == 'verified'
    assert restored['session_id'] == 41
    assert saved == before


def test_legacy_history_without_snapshot_keeps_its_recorded_summary():
    row = enrich_history_rows([{'predicted_crop': 'Rice', 'compatibility_pct': Decimal('16.10')}])[0]
    assert row['crop_compatibility_pct'] == Decimal('16.10')
    assert 'local_model_explanation' not in row


def test_screenshot_rice_slope_has_published_moderate_limitations():
    observations = {
        'slope': {'value': 5.83, 'unit': '%', 'period': 'terrain', 'quality': 'modelled'},
        'elevation': {'value': 29.89, 'unit': 'm', 'period': 'terrain', 'quality': 'modelled'},
    }
    rice = next(c for c in assess(observations) if c['crop'] == 'Rice')
    factors = {f['factor']: f for f in rice['factors']}
    assert factors['slope']['score'] == 67
    assert factors['slope']['result'] == 'S2'
    assert factors['slope']['requirement']['source']['url'].endswith('Davao-del-Norte_SUITABILITY-rice.pdf')
    assert factors['elevation']['score'] == 100
    assert factors['elevation']['requirement']['range_basis'] == 'absolute_limit'
    assert rice['compatibility_pct'] is None  # Two factors do not establish overall suitability.


def test_slope_wrong_units_are_not_graded_and_historical_criteria_stay_frozen():
    rice = next(c for c in assess({'slope': {'value': 5.83, 'unit': 'degrees',
        'period': 'terrain', 'quality': 'modelled'}}) if c['crop'] == 'Rice')
    assert next(f for f in rice['factors'] if f['factor'] == 'slope')['score'] is None
    old = {'crop_config_version': 'older-catalog', 'crop_assessments': [{'crop': 'Rice', 'factors': []}]}
    assert enrich_history_rows([{'result_snapshot': old}])[0]['crop_assessments'] == old['crop_assessments']


def test_rice_slope_source_boundaries_keep_the_more_limiting_shared_endpoint():
    from suitability import factor_result
    for value, expected in [(0, 'S1'), (2.99, 'S1'), (3, 'S2'), (5.83, 'S2'),
                            (8, 'S3'), (18, 'S3'), (18.01, 'N')]:
        assert factor_result(value, REQUIREMENTS['Rice']['slope'], 'slope')[1] == expected
