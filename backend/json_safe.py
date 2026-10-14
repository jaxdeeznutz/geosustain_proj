"""Normalize saved analysis snapshots without inventing missing measurements."""
import math
from datetime import date, datetime
from decimal import Decimal

import numpy as np
import pandas as pd


def json_safe(value):
    """Return JSON primitives; non-finite/missing scientific values become null.

    Unknown objects raise rather than silently persisting their string repr.
    A new structure is returned, preserving the caller's analysis object.
    """
    if value is None or value is pd.NA or value is pd.NaT:
        return None
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if isinstance(value, np.datetime64):
        return None if np.isnat(value) else str(value)
    if isinstance(value, np.ndarray):
        return json_safe(value.tolist())
    if isinstance(value, np.generic):
        return json_safe(value.item())
    if isinstance(value, (str, bool, int)):
        return value
    if isinstance(value, (float, Decimal)):
        number = float(value)
        return number if math.isfinite(number) else None
    if isinstance(value, dict):
        return {key: json_safe(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [json_safe(item) for item in value]
    raise TypeError(f'Unsupported analysis JSON type: {type(value).__name__}')
