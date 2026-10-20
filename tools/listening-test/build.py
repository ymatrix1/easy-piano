"""Build a blind listening-test playlist from a manifest.

Usage: python build.py manifest.json [--out out] [--seed N]

Manifest: {"items": [{"path": "../../content/songs/x.json", "method": "control"}, ...]}
Paths are relative to the manifest file. Writes:
  <out>/playlist.json  shuffled songs with opaque ids; titles and paths stripped
  <out>/key.json       id -> method and path (keep it closed until you finish)
"""
import argparse
import json
import random
import secrets
from pathlib import Path

# Only what playback needs; titles, composers and ids would give the method away.
PLAY_FIELDS = ("bpm", "time", "bars")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("manifest")
    ap.add_argument("--out", default=str(Path(__file__).parent / "out"))
    ap.add_argument("--seed", type=int, default=None, help="shuffle seed (default: random)")
    args = ap.parse_args()

    manifest_path = Path(args.manifest)
    items = json.loads(manifest_path.read_text(encoding="utf-8"))["items"]
    rng = random.Random(args.seed)
    rng.shuffle(items)

    playlist, key = [], {}
    for item in items:
        song_path = (manifest_path.parent / item["path"]).resolve()
        song = json.loads(song_path.read_text(encoding="utf-8"))
        missing = [f for f in PLAY_FIELDS if f not in song]
        if missing:
            raise SystemExit(f"{song_path}: missing {missing}")
        tune_id = secrets.token_hex(4)
        playlist.append({"id": tune_id, **{f: song[f] for f in PLAY_FIELDS}})
        key[tune_id] = {"method": item["method"], "path": item["path"]}

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "playlist.json").write_text(json.dumps({"tunes": playlist}), encoding="utf-8")
    (out / "key.json").write_text(json.dumps(key, indent=2), encoding="utf-8")
    methods = sorted({v["method"] for v in key.values()})
    print(f"{len(playlist)} tunes, methods: {', '.join(methods)} -> {out}")


if __name__ == "__main__":
    main()
