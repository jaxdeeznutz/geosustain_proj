"""Repository evidence only: do not infer climate periods from numeric ranges."""

TRAINING_SOURCES = {
    'Crop_recommendation.csv': {'rainfall': None, 'temperature': None, 'humidity': None},
    'LOCAL_CROP_PROFILES': {'rainfall': 'rolling_30_days', 'temperature': None, 'humidity': None},
}
INFERENCE_PERIODS = {'rainfall': 'rolling_30_days', 'temperature': 'annual_mean', 'humidity': 'current'}


def validate_training_periods(sources=TRAINING_SOURCES):
    """Block artifact replacement until every training source has compatible periods."""
    if not sources:
        raise ValueError('Climate training provenance is missing.')
    for source, periods in sources.items():
        for feature, expected in INFERENCE_PERIODS.items():
            if periods.get(feature) != expected:
                raise ValueError(
                    f'Climate training contract unresolved: {source} {feature} period '
                    f'{periods.get(feature)!r}; inference expects {expected}. '
                    'Supply documented compatible training data; do not relabel or rescale '
                    'the existing CSV/synthetic profiles. Existing model artifacts were not replaced.'
                )
