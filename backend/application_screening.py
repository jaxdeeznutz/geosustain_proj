"""Saved humidity/vegetation checks, separate from model and reference scores."""
from copy import deepcopy
import math

VERSION = 'application-screening-v1'
SOURCE = 'Existing application heuristic: rainfallDatasets.CROP_ENV_PROFILES'
LIMITATION = ('Application screening only; these legacy heuristic ranges are not '
              'validated agronomic criteria and do not change crop rankings. ')
FACTORS = {
    'humidity': ('humidity_current', '%', 'current', 0, 100),
    'ndvi': ('ndvi', 'index', 'latest_scene', -1, 1),
}


def finite_number(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return float(value) if math.isfinite(value) else None


def attach_application_screening(result):
    """Attach only to new analyses; never change model snapshots or crop objects."""
    from rainfallDatasets import CROP_ENV_PROFILES

    crops = result.get('crop_assessments') or []
    if not crops:
        return result
    measurements = result.get('environmental_measurements') or {}
    saved = []
    for crop in crops:
        name = crop['crop']
        # Reuse the original catalog's explicit Banana -> Cavendish/Lakatan
        # mapping. Do not substitute another species for missing profiles.
        profile_key = str(name).strip().lower()
        if profile_key == 'banana':
            profile_key = 'banana (cavendish/lakatan)'
        profile = CROP_ENV_PROFILES.get(profile_key, {})
        factors = {}
        for key, (measurement_key, unit, period, lower, upper) in FACTORS.items():
            observation = deepcopy(measurements.get(measurement_key) or {})
            value = finite_number(observation.get('value'))
            bounds = profile.get(key)
            status = 'unassessed'
            reason = 'No legacy application range is available for this crop.'
            compatible = (value is not None and lower <= value <= upper
                          and observation.get('quality') in ('measured', 'modelled')
                          and observation.get('unit') == unit
                          and observation.get('period') == period)
            if not compatible:
                reason = 'A compatible observation is unavailable; this factor is not assessed.'
            elif bounds:
                preferred_min, preferred_max, accepted_min, accepted_max = bounds
                if preferred_min <= value <= preferred_max:
                    status, reason = 'suitable', 'Within the preferred application range.'
                elif accepted_min <= value <= accepted_max:
                    status, reason = 'limited', 'Within the accepted application range, with limitations.'
                else:
                    status, reason = 'not_suitable', 'Outside the accepted application range.'
            scope = ('Current humidity check; not a climate average. ' if key == 'humidity'
                     else 'Vegetation condition check; not proof of crop suitability. ')
            if bounds:
                reason += f' Accepted range: {bounds[2]} to {bounds[3]} {unit}.'
            factors[key] = {
                'measurement_key': measurement_key, 'measurement': observation,
                'value': value if compatible else None, 'unit': unit, 'period': period,
                'preferred': list(bounds[:2]) if bounds else None,
                'accepted': list(bounds[2:]) if bounds else None,
                'status': status, 'interpretation': LIMITATION + scope + reason,
            }
        saved.append({'crop': name, 'profile_key': profile_key if profile else None,
                      'source': SOURCE, 'factors': factors})
    result['application_screening'] = {'version': VERSION, 'label': 'Application screening',
                                       'used_for_ranking': False, 'crops': saved}
    return result
