"""Serve a Flutter web build with the COOP/COEP headers that wasm threads
(SharedArrayBuffer, flutter_rust_bridge) need. Dev use only.

Usage: python tools/serve_web.py [dir] [port]
"""
import functools
import http.server
import sys


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, ".wasm": "application/wasm"}

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


if __name__ == "__main__":
    directory = sys.argv[1] if len(sys.argv) > 1 else "app/build/web"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 8765
    handler = functools.partial(Handler, directory=directory)
    print(f"Serving {directory} on http://localhost:{port} (COOP/COEP on)")
    http.server.ThreadingHTTPServer(("localhost", port), handler).serve_forever()
