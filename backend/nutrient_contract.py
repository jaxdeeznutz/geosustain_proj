"""Legacy adapter admission contract; not a claim of scientific equivalence."""
from copy import deepcopy
import math

from model_ranking import ModelRankingUnavailable

VERSION = 'legacy-nutrient-adapter-v1'
UNIT = 'legacy_model_scale_unknown_physical_unit'
WARNING = (
    'Production N/P/K are legacy proxies or defaults, not laboratory measurements. '
    'Their physical-unit and analytical-method compatibility with training data is unverified. '
    'CAGRO historical observations are evidence-only and are not used for prediction. '
    'No scientifically validated CAGRO-to-model conversion is available in this repository.'
)


def legacy_inputs(n, p, k, nitrogen_quality, nitrogen_source):
    """Record the existing adapter output without converting or substituting values."""
    source = nitrogen_source or 'Unavailable'
    if 'SoilGrids' in source:
        method = 'Existing adapter: clamp(round((raw / 100.0) * 6), 20, 120)'
    elif 'OpenLandMap' in source:
        method = 'Existing adapter: clamp(round(raw * 0.7), 20, 120)'
    elif nitrogen_quality == 'fallback_default':
        method = 'Existing PANABO_CONFIG nitrogen default'
    else:
        method = 'Legacy nitrogen provider output; upstream method undocumented'
    result = {}
    for name, value in [('N', n), ('P', p), ('K', k)]:
        valid = isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)
        if name == 'N' and nitrogen_quality not in ('measured', 'estimated_proxy', 'fallback_default'):
            valid = False
        result[name] = {
            'value': value if valid else None, 'unit': UNIT,
            'source': source if name == 'N' else 'rainfallDatasets.estimate_phosphorus_potassium',
            'quality': ('unavailable' if not valid else
                        'fallback_default' if name == 'N' and nitrogen_quality == 'fallback_default' else 'estimated_proxy'),
            'method': method if name == 'N' else 'Existing NDVI/pH/elevation piecewise heuristic and clamping',
            'date': None,
            'compatible': valid,
            'compatibility_scope': 'legacy_adapter_representation_only',
            'scientific_compatibility': 'unverified',
            'contract_version': VERSION,
        }
    return result


def model_values(nutrients):
    """Reject missing, foreign-unit or explicitly incompatible inputs before inference."""
    values = {}
    for name in ('N', 'P', 'K'):
        item = nutrients.get(name, {})
        value = item.get('value')
        if (item.get('unit') != UNIT or item.get('contract_version') != VERSION
                or item.get('compatible') is not True
                or item.get('compatibility_scope') != 'legacy_adapter_representation_only'
                or item.get('scientific_compatibility') != 'unverified'
                or item.get('quality') not in ('estimated_proxy', 'fallback_default')
                or not item.get('source') or not item.get('method') or 'date' not in item
                or isinstance(value, bool) or not isinstance(value, (int, float))
                or not math.isfinite(value)):
            raise ModelRankingUnavailable(f'Invalid or incompatible nutrient input: {name}.')
        values[name] = float(value)
    return values


def recorded_inputs(samples, model_version=None):
    """Expose only contracts actually recorded at inference; never backfill history."""
    return {
        'schema_version': 1, 'contract_version': VERSION, 'model_version': model_version,
        'compatibility_scope': 'legacy_adapter_representation_only',
        'scientific_compatibility': 'unverified', 'compatible_with_cagro': False,
        'samples': [{'sample_index': i, 'location': deepcopy(s.get('location')),
                     'nutrients': deepcopy(s['model_nutrient_inputs'])}
                    for i, s in enumerate(samples) if 'model_nutrient_inputs' in s],
        'status': 'recorded' if samples and all('model_nutrient_inputs' in s for s in samples) else 'not_recorded',
    }
