#!/usr/bin/env python3
"""Serve the web export for local browser checks, without isolation headers."""
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import argparse
import functools

class PreviewHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path.split("?", 1)[0] == "/__test__/host":
            fixture = Path(__file__).resolve().parents[1] / "web/tests/host.html"
            content = fixture.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(content)))
            self.end_headers()
            self.wfile.write(content)
        else:
            super().do_GET()

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8176)
    parser.add_argument("--directory", type=Path, default=Path(__file__).resolve().parents[1] / ".artifacts/web")
    args = parser.parse_args()
    handler = functools.partial(PreviewHandler, directory=str(args.directory))
    ThreadingHTTPServer(("127.0.0.1", args.port), handler).serve_forever()
