"""Serve a compiled public-only QA artifact with hosted deep-link behavior."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit


class Preview(SimpleHTTPRequestHandler):
    def do_GET(self):
        path = urlsplit(self.path).path
        if path.startswith(('/operator/', '/admin/')):
            self.path = '/index.html'
        super().do_GET()

    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('directory', type=Path)
    parser.add_argument('--port', type=int, default=18080)
    args = parser.parse_args()
    directory = args.directory.resolve(strict=True)
    if not (directory / 'main.dart.js').is_file():
        raise SystemExit('Supply the public compiled web directory only.')
    ThreadingHTTPServer(('127.0.0.1', args.port), partial(Preview, directory=str(directory))).serve_forever()
