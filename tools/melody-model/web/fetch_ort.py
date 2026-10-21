"""Download onnxruntime-web into web/vendor/ (git-ignored) and check each file's sha256.

    python tools/melody-model/web/fetch_ort.py [--dest <dir>]

`--dest app/web/melody/vendor --wasm-only` stages the app's practice-mode runtime: the WebGPU build is left
out (the app uses the wasm backend, and its 25.5 MiB asyncify wasm exceeds Cloudflare Pages' 25 MiB file limit).

The demo imports only these vendored files and points `ort.env.wasm.wasmPaths` at vendor/, so nothing
executable comes from a CDN at run time. Keep VERSION equal to the onnxruntime pin in pyproject.toml (`export` extra)
(the Python parity check and the browser then run the same kernels).
"""

import hashlib
import sys
import urllib.request
from pathlib import Path

VERSION = "1.30.0"
URL = f"https://cdn.jsdelivr.net/npm/onnxruntime-web@{VERSION}/dist/"
FILES = {
    "ort.wasm.min.mjs": "219e6a1fc8a9938268d18efca3c91d310bd2f4a59bbd13744df5b2b7fc6cee3b",
    "ort-wasm-simd-threaded.mjs": "e13f7f94fc51b4ca72b12faeb1ee95f4ace6dfbc8939bc718aabdc0a27c4299b",
    "ort-wasm-simd-threaded.wasm": "3398c10d07d229bd91b364548e130e0e51a8e5704b88c7c083ebbeb78842dee2",
    # WebGPU build (loaded only when the page picks the WebGPU backend)
    "ort.webgpu.min.mjs": "3dffff71811bc13a3a3d9591c57ca5ee5735b8f5f3eaf789510b02bb040ae3a0",
    "ort-wasm-simd-threaded.asyncify.mjs": "3d1c85995364bb643302fc6fd877a0c3ba5ae72401815e0f24828a53d9191e28",
    "ort-wasm-simd-threaded.asyncify.wasm": "39f9f0894d478800487ed9f7dbe92618498db320cf55c8e3d89adff8dce658da",
}
WEBGPU = {"ort.webgpu.min.mjs", "ort-wasm-simd-threaded.asyncify.mjs", "ort-wasm-simd-threaded.asyncify.wasm"}
VENDOR = Path(__file__).resolve().parent / "vendor"


def main() -> int:
    dest = Path(sys.argv[sys.argv.index("--dest") + 1]) if "--dest" in sys.argv else VENDOR
    dest.mkdir(parents=True, exist_ok=True)
    files = {k: v for k, v in FILES.items() if "--wasm-only" not in sys.argv or k not in WEBGPU}
    for name, want in files.items():
        path = dest / name
        data = path.read_bytes() if path.exists() else urllib.request.urlopen(URL + name, timeout=60).read()
        got = hashlib.sha256(data).hexdigest()
        if got != want:
            print(f"{name}: sha256 {got} != pinned {want}", file=sys.stderr)
            path.unlink(missing_ok=True)
            return 1
        path.write_bytes(data)
        print(f"{name}: ok ({len(data):,} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
