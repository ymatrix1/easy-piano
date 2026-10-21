"""Copy content/ into app/assets/content and write an index, so the Flutter app
can load lessons as assets (Flutter cannot read files outside its package).
Run before `flutter run` / `flutter build`. The copy is git-ignored.

Usage: python tools/sync_content.py
"""
import json
import shutil
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
(DST / "index.json").write_text(json.dumps({"files": files}, indent=1) + "\n", encoding="utf-8")
print(f"synced {len(files)} files to {DST.relative_to(ROOT)}")
# One bundle of every file, so the web app loads content in one request
# instead of ~125 sequential fetches (docs/research/web-load-performance.md).
bundle = {f: (DST / f).read_text(encoding="utf-8") for f in files}
(DST / "bundle.json").write_text(
    json.dumps(bundle, ensure_ascii=False, separators=(",", ":")), encoding="utf-8"
)
