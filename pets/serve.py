"""Local dev server for the pet pages. Like `python -m http.server`, but tells the browser not to
cache anything (as the live site's _headers file does), so edited scripts show up on a normal refresh.

    python pets/serve.py            # serves the repo root at http://localhost:8080
    python pets/serve.py 9000       # another port
"""
import functools
import http.server
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
        super().end_headers()


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    handler = functools.partial(NoCacheHandler, directory=str(ROOT))
    with http.server.ThreadingHTTPServer(('', port), handler) as server:
        print(f'Serving {ROOT} at http://localhost:{port}/pets/sandbox.html (Ctrl+C to stop)')
        server.serve_forever()


if __name__ == '__main__':
    main()
