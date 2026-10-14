"""CORS outside FastAPI's error handler, including unexpected HTTP 500s."""
import os
from urllib.parse import urlsplit

from fastapi import FastAPI
from starlette.middleware.cors import CORSMiddleware


def frontend_origins():
    raw = os.getenv('FRONTEND_ORIGINS', ','.join([
        'https://geosustain.vercel.app',
        'http://localhost:3000', 'http://localhost:5173', 'http://localhost:8080',
    ]))
    origins = []
    for item in raw.split(','):
        origin = item.strip().rstrip('/')
        if not origin:
            continue
        parsed = urlsplit(origin)
        if (parsed.scheme not in ('http', 'https') or not parsed.hostname
                or parsed.path or parsed.query or parsed.fragment
                or parsed.username or parsed.password or '*' in origin):
            raise ValueError('FRONTEND_ORIGINS must contain explicit HTTP(S) origins, without paths or wildcards')
        # Accessing port validates malformed port strings too.
        _ = parsed.port
        origins.append(origin)
    if not origins:
        raise ValueError('FRONTEND_ORIGINS must contain at least one trusted origin')
    return list(dict.fromkeys(origins))


class CorsFastAPI(FastAPI):
    def build_middleware_stack(self):
        # Preserve the FastAPI instance (routes, dependencies, lifespan) while
        # wrapping its entire stack, including ServerErrorMiddleware.
        return CORSMiddleware(
            super().build_middleware_stack(),
            allow_origins=frontend_origins(),
            allow_credentials=True,
            allow_methods=['*'],
            allow_headers=['*'],
        )
