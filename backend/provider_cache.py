"""Bounded, exact-coordinate cache of successful environmental observations."""
from collections import OrderedDict
from copy import deepcopy
from threading import Lock
from time import monotonic, perf_counter
import logging

_values = OrderedDict()
_lock = Lock()
_log = logging.getLogger('uvicorn.error')


def retrieve(name, fn, lat, lon, ttl):
    key = (name, fn, float(lat), float(lon))
    now = monotonic()
    with _lock:
        entry = _values.get(key)
        if entry and now - entry[0] < ttl:
            _values.move_to_end(key)
            _log.info('Environmental source factor=%s cache=hit', name)
            return deepcopy(entry[1])
    started = perf_counter()
    try:
        value = fn(lat, lon)
        if name == 'climate':
            valid = bool(value) and all(v.get('value') is not None for v in value.values())
        elif name == 'slope':
            valid = value is not None
        elif name == 'weather':
            valid = value is not None and value[4] == 'measured'
        else:
            valid = value is not None and value[0] is not None and value[1] == 'measured'
        if valid:
            with _lock:
                _values[key] = (monotonic(), deepcopy(value))
                _values.move_to_end(key)
                while len(_values) > 2048:
                    _values.popitem(last=False)
        return value
    finally:
        _log.info('Environmental source factor=%s cache=miss seconds=%.2f', name, perf_counter()-started)
