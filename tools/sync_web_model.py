"""Copies the pinned onnxruntime-web build into app/web/vendor/ort/ (git-ignored).

The mic note model (app/web/mic_model_worker.js) runs on onnxruntime-web (MIT).
The 13 MB wasm is not committed; this fetches the exact npm release and
verifies its integrity hash. Run before `flutter build web` / `flutter run`,
like sync_content.py. The model itself (app/web/models/piano_net.onnx) is committed.
"""

import base64
import hashlib
import io
import tarfile
import urllib.request
from pathlib import Path

VERSION = "1.27.0"
URL = f"https://registry.npmjs.org/onnxruntime-web/-/onnxruntime-web-{VERSION}.tgz"
INTEGRITY = "sha512-ogDLsqIozHZwifPuN37OproAo0byX6t43/bP8GzeZWBWD6MOGExswFAx3up4NS/vvWBOg2u2PXomDt3rMmdQSg=="
FILES = ["ort.wasm.min.mjs", "ort-wasm-simd-threaded.mjs", "ort-wasm-simd-threaded.wasm"]
OUT = Path(__file__).resolve().parent.parent / "app" / "web" / "vendor" / "ort"


def main():
    stamp = OUT / "VERSION"
    if all((OUT / f).exists() for f in FILES) and stamp.exists() and stamp.read_text().strip() == VERSION:
        return
    data = urllib.request.urlopen(URL).read()
    got = "sha512-" + base64.b64encode(hashlib.sha512(data).digest()).decode()
    if got != INTEGRITY:
        raise SystemExit(f"onnxruntime-web {VERSION}: integrity {got} != pinned {INTEGRITY}")
    OUT.mkdir(parents=True, exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(data)) as t:
        for f in FILES:
            (OUT / f).write_bytes(t.extractfile(f"package/dist/{f}").read())
    (OUT / "VERSION").write_text(VERSION)
    print(f"onnxruntime-web {VERSION} -> {OUT}")


if __name__ == "__main__":
    main()
