"""Stage melody model files for the app's practice mode (docs/specs/practice-mode.md).

    python tools/melody-model/web/stage_app_model.py --from <dir with decoder.int8.onnx and heads.int8.onnx>

Copies the runtime files into app/web/melody/model/ (git-ignored), served on the app's own origin, the default
MELODY_MODEL_URL. vocab.json comes from the repo with LF line endings (a Windows checkout has CRLF, which changes
its sha256). Every file is checked against the release manifest, the same check the app makes before use.
Until the melody-model-v1 release is published this is how a dev build gets a model.
"""

import hashlib
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
MANIFEST = HERE.parent / "releases" / "melody-model-v1.json"
DEST = ROOT / "app" / "web" / "melody" / "model"
FILES = ["decoder.int8.onnx", "heads.int8.onnx", "vocab.json"]


def main() -> int:
    if "--from" not in sys.argv:
        print(__doc__, file=sys.stderr)
        return 2
    src = Path(sys.argv[sys.argv.index("--from") + 1])
    want = json.loads(MANIFEST.read_text(encoding="utf-8"))["files"]
    DEST.mkdir(parents=True, exist_ok=True)
    for name in FILES:
        data = (
            (HERE.parent / "vocab.json").read_bytes().replace(b"\r\n", b"\n")
            if name == "vocab.json"
            else (src / name).read_bytes()
        )
        got = hashlib.sha256(data).hexdigest()
        if got != want[name]["sha256"]:
            print(f"{name}: sha256 {got} != manifest {want[name]['sha256']}", file=sys.stderr)
            return 1
        (DEST / name).write_bytes(data)
        print(f"{name}: ok ({len(data):,} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
