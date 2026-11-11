"""Explicit operational periods; legacy training equivalence remains unverified."""
from copy import deepcopy

from suitability import number
from model_ranking import ModelRankingUnavailable

VERSION = 'climate-annual-five-year-v2'
PROTOTYPE_MODE = 'seven_crop_raw_annual_prototype_v1'
NO_NPK_PROTOTYPE_MODE = 'seven_crop_no_npk_raw_annual_prototype_v1'
PROTOTYPE_NOTICE = (
    'Experimental seven-crop model: annual inputs have not been validated against '
    'the training data. Scores and explanations describe this prototype, not verified farm suitability.'
)
FIELDS = {
    'rainfall_annual_mean_5y_mm': ('rainfall', 'mm/year', 'annual_mean_total', 'rainfall'),
    'temperature_mean_5y_c': ('temperature', 'C', 'annual_mean', 'temperature'),
    'humidity_current_pct': ('humidity_current', '%', 'current', 'humidity'),
}
WARNING = (
    'Legacy Random Forest climate training periods are undocumented for the base CSV. '
    'Synthetic local rainfall is described as 30-day rainfall; temperature and humidity '
    'aggregation periods are unspecified. New analyses use five-year mean annual '
    'rainfall and mean air temperature, with current humidity. An annual-compatible '
    'seven-crop model is required before model ranking can use these observations.'
)


def annual_model_ready(model, metadata):
    """A legacy forest cannot receive annual totals under a recent-rain label."""
    from crop_requirements import REQUIREMENTS
    from training.climate_training_contract import validate_training_periods
    if model is None or set(map(str, model.classes_)) != {name.lower() for name in REQUIREMENTS}:
        return False
    training = (metadata or {}).get('training') or {}
    sources = (training.get('provenance') or {}).get('climate_sources')
    if training.get('status') != 'recorded' or not sources:
        return False
    try:
        validate_training_periods(sources)
    except (TypeError, ValueError, AttributeError):
        return False
    return True


def annual_prototype_policy(metadata, classes):
    """An explicit owner-selected experiment, never training-period validation."""
    from crop_requirements import REQUIREMENTS
    if set(map(str, classes)) != {name.lower() for name in REQUIREMENTS}:
        return False
    training = (metadata or {}).get('training') or {}
    policy = (metadata or {}).get('runtime_input_policy') or {}
    from model_artifacts import ENVIRONMENTAL_FEATURES
    nutrient_policy = (
        policy.get('mode') == PROTOTYPE_MODE
        and policy.get('legacy_nutrients') == 'estimated_proxies_not_soil_tests'
    ) or (
        policy.get('mode') == NO_NPK_PROTOTYPE_MODE
        and metadata.get('feature_names') == ENVIRONMENTAL_FEATURES
        and policy.get('feature_order') == ENVIRONMENTAL_FEATURES
        and policy.get('npk_used') is False
    )
    return (training.get('status') == 'experimental_prototype'
            and nutrient_policy
            and policy.get('model_version') == metadata.get('model_version')
            and bool(policy.get('model_version'))
            and policy.get('climate_contract_version') == VERSION
            and policy.get('annual_input_compatibility') == 'unverified'
            and policy.get('use_raw_annual_values') is True
            and policy.get('validation_claim') == 'experimental_only')


def mark_annual_prototype(result):
    """Keep the unresolved interpretation visible on new saved results."""
    no_npk = result.get('model_input_features') == ['temperature', 'humidity', 'ph', 'rainfall', 'ndvi', 'elevation', 'slope']
    result.update(model_usage=NO_NPK_PROTOTYPE_MODE if no_npk else PROTOTYPE_MODE, model_validation_status='unvalidated',
                  model_ranking_status='experimental', prototype_model_notice=PROTOTYPE_NOTICE,
                  climate_training_compatibility='unverified', climate_model_warning=PROTOTYPE_NOTICE,
                  model_score_note=PROTOTYPE_NOTICE,
                  npk_assessment={'status': 'not_assessed', 'pending_source': 'farm_soil_test',
                      'used_for_prediction': not no_npk,
                      'note': ('NPK is excluded from this model. PAGRO measurements are pending.' if no_npk else
                               'The prototype uses estimated nitrogen from SoilGrids when available; phosphorus and potassium are calculated from NDVI, soil pH and elevation. These are not farm soil tests. Historical CAGRO records remain separate.')})
    if no_npk:
        result.update(model_npk_status='excluded', nutrient_display_basis='not_used_by_model',
                      nutrient_basis='NPK excluded from model training and prediction; PAGRO data pending.')
    warnings = result.setdefault('data_quality_warnings', [])
    if PROTOTYPE_NOTICE not in warnings:
        warnings.append(PROTOTYPE_NOTICE)
    for crop in result.get('crop_assessments', []):
        crop['model_validation_status'] = 'unvalidated'
        crop['classification'] = 'Experimental model score'
    return result


def compatible(observation, unit, period):
    return (observation.get('unit') == unit and observation.get('period') == period
            and observation.get('quality') in ('measured', 'modelled')
            and number(observation.get('value')) is not None)


def model_climate_inputs(measurements):
    values, records = {}, {}
    for field, (key, unit, period, feature) in FIELDS.items():
        if feature is None:
            continue
        observation = measurements.get(key) or {}
        if not compatible(observation, unit, period):
            raise ModelRankingUnavailable(f'Required climate input unavailable or incompatible unit/time period: {feature}.')
        values[feature] = number(observation['value'])
        records[feature] = {**deepcopy(observation), 'api_field': field,
                            'training_compatibility': 'unverified'}
    return values, records


def attach_climate_fields(result, measurements):
    """Add explicit names while preserving historical API aliases."""
    metadata = {}
    for field, (key, unit, period, feature) in FIELDS.items():
        observation = measurements.get(key) or {}
        result[field] = number(observation.get('value')) if compatible(observation, unit, period) else None
        metadata[field] = {
            'unit': unit, 'period': period, 'source': observation.get('source'),
            'quality': observation.get('quality', 'unavailable'),
            'start': observation.get('start'), 'end_exclusive': observation.get('end_exclusive'),
            'model_feature': feature, 'screening_factor': key if key in ('rainfall', 'temperature') else None,
            'baseline_years': 5 if key in ('rainfall', 'temperature') else None,
            'status': 'available' if result[field] is not None else 'unavailable_or_incompatible',
        }
    result.update(climate_contract_version=VERSION, climate_field_metadata=metadata,
                  climate_model_warning=WARNING, climate_training_compatibility='unverified')
    # Do not put an annual total in legacy aliases that meant recent rainfall.
    for key in ('rainfall_30d_mm', 'rainfall_monthly_mm', 'monthly_rainfall_mm'):
        result.pop(key, None)
    result['rainfall_mm'] = None
    for alias, canonical in [('annual_rainfall_mm', 'rainfall_annual_mean_5y_mm'),
                             ('temperature_c', 'temperature_mean_5y_c'),
                             ('live_humidity', 'humidity_current_pct')]:
        result[alias] = result[canonical]
    return result


def same_period(entries):
    """Do not average different units, periods or historical baseline windows."""
    signatures = {(e.get('unit'), e.get('period'), e.get('start'), e.get('end_exclusive')) for e in entries}
    return len(signatures) == 1
