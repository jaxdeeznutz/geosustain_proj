"""Authentication transport safeguards and bounded per-process throttling."""
import os
import secrets
import time
from collections import OrderedDict
from threading import Lock
from urllib.parse import urlsplit

from starlette.responses import JSONResponse


def production_mode():
    return bool(os.getenv('RENDER')) or os.getenv('APP_ENV', '').lower() == 'production'


def signing_key():
    key = os.getenv('SECRET_KEY', '')
    placeholders = {'geosustain-secret-change-in-production', 'replace-with-a-long-random-secret'}
    if key in placeholders or len(key) < 32:
        if production_mode():
            raise RuntimeError('Set SECRET_KEY to a random secret of at least 32 characters.')
        return secrets.token_urlsafe(48)
    return key


class AuthSecurityMiddleware:
    # Per-process protection. Multi-worker deployments also need an edge/shared limiter.
    paths = {'/login', '/register', '/api/mobile/login', '/api/mobile/register',
             '/api/mobile/change-password'}

    def __init__(self, app):
        self.app = app
        self.attempts = OrderedDict()
        self.lock = Lock()

    async def __call__(self, scope, receive, send):
        if scope['type'] != 'http':
            return await self.app(scope, receive, send)
        path = scope.get('path', '')
        headers = dict(scope.get('headers', []))
        if scope['method'] == 'POST' and path in self.paths:
            # HTML forms are same-origin. Reject cross-site form submissions,
            # including login CSRF. Native JSON API clients do not use cookies.
            if path in {'/login', '/register'}:
                origin = headers.get(b'origin', b'').decode()
                host = headers.get(b'host', b'').decode()
                cross_site = headers.get(b'sec-fetch-site') == b'cross-site'
                if cross_site or (origin and urlsplit(origin).netloc != host):
                    return await JSONResponse({'error': 'Cross-site form submission rejected.'}, 403)(scope, receive, send)
            now = time.monotonic()
            key = (scope.get('client') or ('unknown',))[0]
            with self.lock:
                # Drop expired buckets, cap memory without evicting active limits.
                for old in list(self.attempts):
                    if now - self.attempts[old][0] >= 300:
                        del self.attempts[old]
                start, count = self.attempts.get(key, (now, 0))
                blocked = count >= 20 or (key not in self.attempts and len(self.attempts) >= 10000)
                if not blocked:
                    self.attempts[key] = (start, count + 1)
            if blocked:
                return await JSONResponse({'error': 'Too many attempts. Try again in five minutes.'}, 429,
                    headers={'Retry-After': '300', 'Cache-Control': 'no-store'})(scope, receive, send)

        async def secure_send(message):
            if message['type'] == 'http.response.start':
                message['headers'] = list(message.get('headers', []))
                message['headers'].append((b'x-content-type-options', b'nosniff'))
                if path in self.paths or path == '/api/mobile/me':
                    message['headers'].append((b'cache-control', b'no-store'))
            await send(message)
        await self.app(scope, receive, secure_send)
