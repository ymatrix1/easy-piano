"""Serves app/web plus a test page that pushes a fixture WAV through the real
mic model worker (onnxruntime-web) in real time, so the browser path can be
compared with eval_model.py. COOP/COEP as in app/web/_headers.

Usage: uv run python browser_check.py [port]   then open /check.html?clip=<fixture name>
"""

import http.server
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
PAGE = Path(__file__).with_name("browser_check.html")
FIX = ROOT / "tools" / "mic-fixtures"


class H(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=str(ROOT / "app" / "web"), **k)

    def translate_path(self, path):
        p = path.split("?")[0]
        if p == "/check.html":
            return str(PAGE)
        if p.startswith("/arch/"):
            return str(Path(__file__).parent / "runs" / "arch" / p[6:])
        if p.startswith("/fx/"):
            return str(FIX / p[4:])
        return super().translate_path(path)

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


if __name__ == "__main__":
    http.server.ThreadingHTTPServer(
        ("127.0.0.1", int(sys.argv[1]) if len(sys.argv) > 1 else 8765), H
    ).serve_forever()
