"""Bounded Open-Meteo traffic; respect provider throttling without retry storms.

This changes request scheduling only. It supplies no weather observations and
never substitutes stale, forecast or invented values for a missing measurement.
"""
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
import logging
import math
from threading import BoundedSemaphore, Lock
from time import monotonic
from urllib.parse import urlsplit

import requests

_lock = Lock()
_slots = BoundedSemaphore(2)
_blocked_until = 0.0
_failures = 0
_log = logging.getLogger('uvicorn.error')
HOSTS = {'api.open-meteo.com', 'archive-api.open-meteo.com'}


class ProviderCooldown(requests.RequestException):
    """No request was sent because this provider asked us to wait."""


def reset_state():
    """Reset process-local throttle state for isolated tests."""
    global _blocked_until, _failures
    with _lock:
        _blocked_until = 0.0
        _failures = 0


def _check_cooldown():
    with _lock:
        if monotonic() < _blocked_until:
            raise ProviderCooldown('Weather provider is temporarily rate-limited.')


def _delay(response, failures):
    value = response.headers.get('Retry-After')
    if isinstance(value, str):
        try:
            seconds = float(value)
        except ValueError:
            try:
                date = parsedate_to_datetime(value)
                if date.tzinfo is None:
                    date = date.replace(tzinfo=timezone.utc)
                seconds = (date - datetime.now(timezone.utc)).total_seconds()
            except (TypeError, ValueError, OverflowError):
                seconds = None
        if seconds is not None and math.isfinite(seconds):
            return min(86400.0, max(1.0, seconds))
    return min(3600.0, 60.0 * 2 ** min(failures - 1, 6))


def get(url, **kwargs):
    """No automatic HTTP retries; one 429 cools down all owned endpoints."""
    global _blocked_until, _failures
    if urlsplit(url).hostname not in HOSTS:
        raise ValueError('Only the configured Open-Meteo endpoints are supported.')
    _check_cooldown()
    with _slots:
        # Other sample workers may have received a 429 while this one waited.
        _check_cooldown()
        response = requests.get(url, **kwargs)
        if response.status_code == 429:
            with _lock:
                _failures += 1
                delay = _delay(response, _failures)
                _blocked_until = max(_blocked_until, monotonic() + delay)
            _log.warning('Open-Meteo rate-limited; provider requests paused seconds=%.0f', delay)
        elif isinstance(response.status_code, int) and response.status_code < 400:
            with _lock:
                _failures = 0
        return response
