"""Informational cultivar profiles, separate from trained crop classes and scoring."""
from copy import deepcopy
from functools import lru_cache
import json
from pathlib import Path


@lru_cache(maxsize=1)
def _banana_reference():
    path = Path(__file__).resolve().parents[1] / 'assets' / 'data' / 'banana_varieties.json'
    return json.loads(path.read_text(encoding='utf-8'))


def with_variety_reference(row):
    """Enrich the parent catalogue row without adding separate model classes."""
    result = dict(row)
    if result.get('crop_key') == 'banana':
        reference = _banana_reference()
        result['varieties'] = deepcopy(reference['profiles'])
        result['variety_reference_version'] = reference['version']
        result['variety_prediction_scope'] = reference['prediction_scope']
        result['variety_reference_note'] = reference['note']
        result['variety_guidance_scope_note'] = reference.get('guidance_scope_note')
    return result
