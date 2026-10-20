"""Build a blind listening-test site from a manifest.

Usage: python build.py manifest.json [--out out] [--seed N]

Manifest: {"items": [{"path": "../../content/songs/x.json", "method": "control"}, ...]}
Paths are relative to the manifest file. Writes:
  <out>/site/      the only folder to serve: page files, piano samples, playlist.json
  <out>/key.json   id -> method and path; outside site/ so the page can't fetch it
"""
import argparse
import json
import random
import re
import secrets
import shutil
from pathlib import Path

HERE = Path(__file__).parent
PAGE_FILES = ("index.html", "app.js", "notation.js", "synth.js")
SAMPLES = HERE.parent.parent / "app" / "assets" / "piano"
PARTS = ("RH", "LH", "ACC", "BASS", "DRUMS")
# Fingering, annotations and directives don't change the sound but could tell
# hand-written songs from generated ones.
STRIP = re.compile(r"@\d+|\([^)]*\)|\{[^}]*\}")


def normalise(bar: dict) -> dict:
    return {p: " ".join(STRIP.sub("", bar[p]).split()) for p in PARTS if p in bar}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("manifest")
    ap.add_argument("--out", default=str(HERE / "out"))
    ap.add_argument("--seed", type=int, default=None, help="shuffle seed (default: random)")
    args = ap.parse_args()

    manifest_path = Path(args.manifest)
    items = json.loads(manifest_path.read_text(encoding="utf-8"))["items"]
    random.Random(args.seed).shuffle(items)

    playlist, key = [], {}
    for item in items:
        song_path = (manifest_path.parent / item["path"]).resolve()
        song = json.loads(song_path.read_text(encoding="utf-8"))
        missing = [f for f in ("bpm", "time", "bars") if f not in song]
        if missing:
            raise SystemExit(f"{song_path}: missing {missing}")
        tune_id = secrets.token_hex(4)
        bars = [normalise(b) for b in song["bars"]]
        playlist.append({"id": tune_id, "bpm": song["bpm"], "time": song["time"], "bars": bars})
        key[tune_id] = {"method": item["method"], "path": item["path"]}

    out = Path(args.out)
    site = out / "site"
    if site.exists():
        shutil.rmtree(site)
    site.mkdir(parents=True)
    for f in PAGE_FILES:
        shutil.copy2(HERE / f, site / f)
    shutil.copytree(SAMPLES, site / "piano", ignore=shutil.ignore_patterns("*.md"))
    (site / "playlist.json").write_text(json.dumps({"tunes": playlist}), encoding="utf-8")
    (out / "key.json").write_text(json.dumps(key, indent=2), encoding="utf-8")
    methods = sorted({v["method"] for v in key.values()})
    print(f"{len(playlist)} tunes, methods: {', '.join(methods)}")
    print(f"serve: python -m http.server 8770 --bind 127.0.0.1 --directory {site}")


if __name__ == "__main__":
    main()
