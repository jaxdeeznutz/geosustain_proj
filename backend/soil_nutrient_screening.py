"""Historical reference screening only; no model inputs or rankings are modified."""
from copy import deepcopy

from crop_requirements import NUTRIENT_REQUIREMENTS
from suitability import number, within

TYPE = 'reference_based_soil_nutrient_screening'
NO_CRITERION = 'Not assessed — no compatible documented crop nutrient range available.'
NOTE = ('Historical CAGRO soil observation; current field conditions may differ. '
        'Field or laboratory verification is recommended. Locality association only, '
        'not an exact current measurement from this farm.')
NUTRIENTS = ('nitrogen', 'phosphorus', 'potassium')


def observation(row, nutrient):
    estimated = nutrient == 'nitrogen' and row.get('estimated_nitrogen_pct') is not None
    key = ('estimated_nitrogen_pct' if estimated else 'nitrogen_pct') if nutrient == 'nitrogen' else nutrient + '_ppm'
    return {
        'value': row.get(key), 'unit': row.get('units', {}).get(key),
        'source': row.get('source'),
        'quality': ('unavailable' if row.get(key) is None else
                    'estimated_from_organic_matter' if estimated else 'historical_reported_observation'),
        'nutrient_definition': ('organic_matter_derived_nitrogen' if estimated else row.get(nutrient + '_definition')),
        'method': row.get('nitrogen_method') if nutrient == 'nitrogen' else row.get('laboratory_method'),
    }


def _interval(value):
    return (isinstance(value, (list, tuple)) and len(value) == 2
            and all(number(v) is not None for v in value)
            and value[0] <= value[1])


def assess_nutrient(nutrient, observed, rule):
    """No unit conversion or guessed analytical meaning; exact contract matching."""
    result = {**deepcopy(observed), 'factor': nutrient, 'label': nutrient.title(),
              'status': 'Not assessed', 'reason': NO_CRITERION, 'requirement': None,
              'used_for_model_prediction': False, 'assessment_type': TYPE}
    if not rule:
        return result
    source = rule.get('source') or {}
    if (not source.get('title') or not (source.get('url') or source.get('citation'))
            or not rule.get('limitations') or not _interval(rule.get('optimal'))
            or (rule.get('absolute') is not None and not _interval(rule['absolute']))):
        return result
    if any(not observed.get(key) or observed.get(key) != rule.get(key)
           for key in ('unit', 'nutrient_definition', 'method')):
        result['reason'] = 'Not assessed — incompatible or undocumented nutrient unit, definition or method.'
        return result
    result['requirement'] = deepcopy(rule)
    value = number(observed.get('value'))
    if value is None:
        result['reason'] = 'Not assessed — nutrient value unavailable.'
    elif within(value, rule['optimal']):
        result.update(status='Suitable', reason='Within documented preferred range.')
    elif rule.get('absolute') is not None and within(value, rule['absolute']):
        result.update(status='Limited', reason='Outside preferred range but within documented accepted range.')
    elif rule.get('absolute') is not None:
        result.update(status='Outside documented range', reason='Outside documented accepted range.')
    else:
        result['reason'] = 'Not assessed — no documented accepted range outside the preferred range.'
    return result


def screen_soil_nutrients(soil, requirements=None):
    """Consume only server-matched observations, keeping every source row intact."""
    requirements = NUTRIENT_REQUIREMENTS if requirements is None else requirements
    rows = soil.get('observations', []) if soil.get('status') == 'matched' else []
    # A saved/partial row without matching provenance cannot establish association.
    rows = [row for row in rows if row.get('match', {}).get('method') in
            ('mapped_locality_proximity', 'verified_locality_boundary')]
    output = {'schema_version': 1, 'assessment_type': TYPE,
              'status': 'matched' if rows else 'unavailable',
              'used_for_model_prediction': False, 'note': NOTE,
              'message': ('Multiple historical CAGRO observations are available for this locality.'
                          if len(rows) > 1 else NOTE if rows else 'CAGRO soil data unavailable for this farm.'),
              'crops': {}}
    for crop, rules in requirements.items():
        records = [{'record_id': row['id'], 'provenance': deepcopy(row),
                    'factors': [assess_nutrient(n, observation(row, n), rules.get(n)) for n in NUTRIENTS]}
                   for row in rows]
        output['crops'][crop] = {
            'records': records,
            'combined_status': 'Not assessed',
            'combined_reason': ('Multiple historical observations; no representative value selected or averaged.'
                                if len(rows) > 1 else 'No combined nutrient score is calculated.'),
        }
    return output
