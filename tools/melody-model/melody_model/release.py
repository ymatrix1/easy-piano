"""Model weights live in a GitHub Release, not in git (docs/models/melody-v1.md).

    python -m melody_model.release verify data/melody/release/melody-model-v1      # local files vs manifest
    python -m melody_model.release fetch --out data/melody/models/melody-model-v1    # download + verify

The manifest (`releases/<tag>.json`, committed) records each file's size and sha256;
nothing is used unless its hash matches.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import urllib.request
from pathlib import Path

RELEASES = Path(__file__).resolve().parents[1] / "releases"


def manifest(tag: str = "melody-model-v1") -> dict:
    return json.loads((RELEASES / f"{tag}.json").read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(1 << 20):
            h.update(chunk)
    return h.hexdigest()


def verify(folder: Path, man: dict, files: list[str] | None = None) -> list[str]:
    """Problems found (empty = every listed file is present with the recorded size and hash)."""
    problems = []
    for name in files or list(man["files"]):
        rec = man["files"][name]
        p = folder / name
        if not p.exists():
            problems.append(f"{name}: missing")
        elif p.stat().st_size != rec["bytes"]:
            problems.append(f"{name}: {p.stat().st_size} bytes, expected {rec['bytes']}")
        elif sha256(p) != rec["sha256"]:
            problems.append(f"{name}: sha256 mismatch")
    return problems


def fetch(out: Path, man: dict, files: list[str] | None = None) -> None:
    out.mkdir(parents=True, exist_ok=True)
    for name in files or list(man["files"]):
        dest = out / name
        if dest.exists() and not verify(out, man, [name]):
            continue
        tmp = dest.with_suffix(dest.suffix + ".part")
        urllib.request.urlretrieve(man["url"].format(file=name), tmp)
        tmp.replace(dest)
    problems = verify(out, man, files)
    if problems:
        for p in problems:
            (out / p.split(":")[0]).unlink(missing_ok=True)
        raise SystemExit("downloaded files failed verification: " + "; ".join(problems))


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["verify", "fetch"])
    ap.add_argument("folder", nargs="?")
    ap.add_argument("--tag", default="melody-model-v1")
    ap.add_argument("--out")
    ap.add_argument("--files", nargs="*", help="default: all files in the manifest")
    args = ap.parse_args(argv)
    man = manifest(args.tag)
    if args.cmd == "verify":
        problems = verify(Path(args.folder), man, args.files)
        print("\n".join(problems) or f"ok: {len(args.files or man['files'])} files match {args.tag}")
        raise SystemExit(1 if problems else 0)
    fetch(Path(args.out), man, args.files)
    print(f"ok: {args.out}")


if __name__ == "__main__":
    main(sys.argv[1:])
