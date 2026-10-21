"""Explicit operational periods; legacy training equivalence remains unverified."""
from copy import deepcopy

from suitability import number
from model_ranking import ModelRankingUnavailable

VERSION = 'climate-periods-v1'
FIELDS = {
    'rainfall_30d_mm': ('rainfall_recent', 'mm', 'rolling_30_days', 'rainfall'),
    'rainfall_annual_mean_5y_mm': ('rainfall', 'mm/year', 'annual_mean_total', None),
    'temperature_mean_5y_c': ('temperature', 'C', 'annual_mean', 'temperature'),
    'humidity_current_pct': ('humidity_current', '%', 'current', 'humidity'),
}
WARNING = (
    'Legacy Random Forest climate training periods are undocumented for the base CSV. '
    'Synthetic local rainfall is described as 30-day rainfall; temperature and humidity '
    'aggregation periods are unspecified. Inference uses 30-day rainfall, five-year '
    'mean air temperature and current humidity. Training equivalence is unverified; '
    'validated period-labelled training data is required before retraining.'
)


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
    for alias, canonical in [('rainfall_mm', 'rainfall_30d_mm'),
                             ('annual_rainfall_mm', 'rainfall_annual_mean_5y_mm'),
                             ('temperature_c', 'temperature_mean_5y_c'),
                             ('live_humidity', 'humidity_current_pct')]:
        result[alias] = result[canonical]
    return result


def same_period(entries):
    """Do not average different units, periods or historical baseline windows."""
    signatures = {(e.get('unit'), e.get('period'), e.get('start'), e.get('end_exclusive')) for e in entries}
    return len(signatures) == 1
