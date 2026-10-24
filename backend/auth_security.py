"""Authentication transport safeguards and bounded per-process throttling."""
import os
import secrets
import time
from collections import OrderedDict
from threading import Lock
from urllib.parse import urlsplit

from starlette.responses import JSONResponse
from starlette.concurrency import run_in_threadpool


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
             '/api/mobile/change-password', '/api/mobile/recover-password',
             '/verify-email', '/resend-verification', '/api/mobile/verify-email',
             '/api/mobile/verify-code', '/api/mobile/send-verification', '/api/mobile/resend-verification'}
    paths |= {'/api/mobile/auth/google', '/api/mobile/auth/link-google',
              '/api/mobile/phone-verification/start', '/api/mobile/phone-verification/complete',
              '/api/mobile/password-reset/start', '/api/mobile/password-reset/complete'}

    def __init__(self, app):
        self.app = app
        self.attempts = OrderedDict()
        self.lock = Lock()

    async def __call__(self, scope, receive, send):
        if scope['type'] != 'http':
            return await self.app(scope, receive, send)
        path = scope.get('path', '')
        headers = dict(scope.get('headers', []))
        if scope['method'] in {'POST','PUT','PATCH'}:
            # Bound chunked bodies as well as Content-Length before parsing.
            chunks = []
            size = 0
            while True:
                event = await receive()
                if event['type'] == 'http.disconnect':
                    return
                chunk = event.get('body', b'')
                size += len(chunk)
                if size > 3_000_000:
                    return await JSONResponse({'error':'Request is too large. Maximum upload body is 3 MB.'},413)(scope,receive,send)
                chunks.append(chunk)
                if not event.get('more_body',False):
                    break
            body = b''.join(chunks)
            if b'application/json' in headers.get(b'content-type',b''):
                depth = 0
                quoted = escaped = False
                for char in body:
                    if quoted:
                        if escaped:
                            escaped=False
                        elif char==92:
                            escaped=True
                        elif char==34:
                            quoted=False
                    elif char==34:
                        quoted=True
                    elif char in (91,123):
                        depth+=1
                        if depth>64:
                            return await JSONResponse({'error':'JSON nesting exceeds the supported limit.'},413)(scope,receive,send)
                    elif char in (93,125):
                        depth-=1
            original_receive = receive
            delivered = False
            async def bounded_receive():
                nonlocal delivered
                if not delivered:
                    delivered = True
                    return {'type':'http.request','body':body,'more_body':False}
                return await original_receive()
            receive = bounded_receive
        if scope['method'] == 'POST' and path in self.paths:
            # HTML forms are same-origin. Reject cross-site form submissions,
            # including login CSRF. Native JSON API clients do not use cookies.
            if path in {'/login', '/register', '/verify-email', '/resend-verification'}:
                origin = headers.get(b'origin', b'').decode()
                host = headers.get(b'host', b'').decode()
                cross_site = headers.get(b'sec-fetch-site') == b'cross-site'
                if cross_site or (origin and urlsplit(origin).netloc != host):
                    return await JSONResponse({'error': 'Cross-site form submission rejected.'}, 403)(scope, receive, send)
            now = time.monotonic()
            key = (scope.get('client') or ('unknown',))[0]
            from qa_closure import consume_quota
            try:
                retry = await run_in_threadpool(consume_quota, key, 'authentication', 20)
            except Exception:
                return await JSONResponse({'error': 'Sign-in service temporarily unavailable. Try again.'}, 503,
                    headers={'Cache-Control': 'no-store'})(scope, receive, send)
            if retry:
                return await JSONResponse({'error': 'Too many attempts. Try again later.'}, 429,
                    headers={'Retry-After': str(retry), 'Cache-Control': 'no-store'})(scope, receive, send)
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
                message['headers'].extend([(b'x-frame-options', b'DENY'),
                    (b'referrer-policy', b'strict-origin-when-cross-origin'),
                    (b'content-security-policy', b"frame-ancestors 'none'; base-uri 'self'; object-src 'none'")])
                if scope.get('scheme') == 'https':
                    message['headers'].append((b'strict-transport-security', b'max-age=31536000'))
                if path in self.paths or path.startswith('/api/'):
                    message['headers'] = [(k,v) for k,v in message['headers'] if k.lower() != b'cache-control']
                    message['headers'].append((b'cache-control', b'no-store'))
            await send(message)
        await self.app(scope, receive, secure_send)
