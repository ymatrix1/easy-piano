"""Copy content/ into app/assets/content and write an index, so the Flutter app
can load lessons as assets (Flutter cannot read files outside its package).
Also writes the practice-mode pack (`content practice-pack`, needs cargo) and
copies the melody model's decoding module into app/web/melody/
(docs/specs/practice-mode.md). Run before `flutter run` / `flutter build`.
The copies are git-ignored.

Usage: python tools/sync_content.py
"""
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC, DST = ROOT / "content", ROOT / "app" / "assets" / "content"

if DST.exists():
    shutil.rmtree(DST)
files = []
for p in sorted(SRC.rglob("*.json")):
    rel = p.relative_to(SRC)
    if rel.parts[0] in ("schema", "skill-specs"):  # pipeline-only (D17)
        continue
    out = DST / rel
    out.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(p, out)
    files.append(rel.as_posix())
pack = DST / "practice.json"
cli = ["cargo", "run", "-q", "--manifest-path", str(ROOT / "tools" / "content-cli" / "Cargo.toml"), "--"]
res = subprocess.run([*cli, "practice-pack", str(SRC), "--out", str(pack)], capture_output=True, text=True)
if res.returncode != 0:
    sys.exit(f"content practice-pack failed ({res.returncode}): {res.stderr.strip()[-800:]}")
files.append("practice.json")
web = ROOT / "app" / "web" / "melody"
web.mkdir(parents=True, exist_ok=True)
shutil.copy2(ROOT / "tools" / "melody-model" / "web" / "melody.js", web / "melody.js")
(DST / "index.json").write_text(json.dumps({"files": files}, indent=1) + "\n", encoding="utf-8")
print(f"synced {len(files)} files to {DST.relative_to(ROOT)}")
