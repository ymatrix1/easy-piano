"""Fetch the approved corpora (docs/research/melody-corpora.md) into data/melody/raw.

    python -m melody_model.download nottingham pdmx mutopia

Raw files never enter git (/data/ is ignored). Each corpus writes
data/melody/raw/<corpus>/manifest.json with url, licence and sha256 per file.
Mutopia is fetched one piece at a time with a delay (robots.txt allows all).
OpenScore Lieder ships .mscx only and needs the MuseScore CLI; it is skipped
when `mscore`/`MuseScore4` is not on PATH (PDMX already holds many Lieder uploads).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import sys
import tarfile
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
RAW = ROOT / "data" / "melody" / "raw"
UA = {"User-Agent": "easy-piano-melody-model/0.1 (+https://github.com/ymatrix1/easy-piano)"}

NMD_FILES = ("jigs", "hpps", "morris", "playford", "reelsa-c", "reelsd-g", "reelsh-l",
             "reelsm-q", "reelsr-t", "reelsu-z", "slip", "waltzes", "xmas")  # Ashover excluded (user, 2026-10-20)
PDMX_RECORD = "https://zenodo.org/records/15571083/files"
MUTOPIA_TREE = "https://api.github.com/repos/MutopiaProject/MutopiaProject/git/trees/master?recursive=1"
MUTOPIA_RAW = "https://raw.githubusercontent.com/MutopiaProject/MutopiaProject/master/"
MUTOPIA_SITE = "https://www.mutopiaproject.org/"
MUTOPIA_LICENSES = {
    "Public Domain": "public-domain",
    "Creative Commons Attribution 3.0": "CC-BY-3.0",
    "Creative Commons Attribution 4.0": "CC-BY-4.0",
    "Creative Commons Attribution-ShareAlike 3.0": "CC-BY-SA-3.0",
    "Creative Commons Attribution-ShareAlike 4.0": "CC-BY-SA-4.0",
    "Creative Commons Attribution 2.5": "CC-BY-2.5",
    "Creative Commons Attribution-ShareAlike 2.5": "CC-BY-SA-2.5",
}
MUTOPIA_STYLES = {"Folk", "Song", "Hymn", "Children", "Traditional"}


def fetch(url: str, dest: Path) -> str:
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    h = hashlib.sha256()
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120) as r, open(tmp, "wb") as f:
        while chunk := r.read(1 << 20):
            h.update(chunk)
            f.write(chunk)
    tmp.replace(dest)
    return h.hexdigest()


def get_text(url: str) -> str:
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
        return r.read().decode("utf-8", "replace")


def write_manifest(corpus: str, entries: list[dict], note: str) -> None:
    out = RAW / corpus / "manifest.json"
    out.write_text(json.dumps({"corpus": corpus, "fetched": time.strftime("%Y-%m-%d"), "note": note,
                               "files": entries}, indent=1), encoding="utf-8")
    print(f"{corpus}: {len(entries)} files -> {out}")


def nottingham() -> None:
    entries = []
    for name in NMD_FILES:
        url = f"https://abc.sourceforge.net/NMD/nmd/{name}.txt"
        sha = fetch(url, RAW / "nottingham" / f"{name}.abc")
        entries.append({"path": f"{name}.abc", "url": url, "license": "traditional; no licence stated", "sha256": sha})
        time.sleep(1)
    write_manifest("nottingham", entries, "Nottingham Music Database, original ABC; Ashover collection excluded")


def pdmx() -> None:
    d = RAW / "pdmx"
    entries = []
    for name in ("PDMX.csv", "mxl.tar.gz"):
        dest = d / name
        if not dest.exists():
            print(f"downloading {name} ...", flush=True)
            sha = fetch(f"{PDMX_RECORD}/{name}?download=1", dest)
        else:
            sha = hashlib.sha256(dest.read_bytes()).hexdigest() if dest.stat().st_size < 1 << 30 else "skipped-large"
        entries.append({"path": name, "url": f"{PDMX_RECORD}/{name}", "license": "dataset CC-BY-4.0; files PD/CC0", "sha256": sha})
    if not (d / "mxl").exists():
        print("extracting mxl.tar.gz ...", flush=True)
        with tarfile.open(d / "mxl.tar.gz") as t:
            t.extractall(d, filter="data")
    write_manifest("pdmx", entries, "PDMX (Long et al. 2024), Zenodo 15571083; use no_license_conflict subset")


def _ly_header(text: str) -> dict:
    return dict(re.findall(r'^\s*(\w+)\s*=\s*"([^"]*)"', text, re.M))


def mutopia(delay: float = 1.0) -> None:
    tree = json.loads(get_text(MUTOPIA_TREE))["tree"]
    pieces: dict[str, list[str]] = {}
    for x in tree:
        p = x["path"]
        if p.startswith("ftp/") and p.endswith(".ly"):
            pieces.setdefault(p.rsplit("/", 1)[0], []).append(p)
    d = RAW / "mutopia"
    entries, skipped = [], {}
    for piece, files in sorted(pieces.items()):
        main = min(files, key=lambda f: (f.count("/"), len(f)))
        try:
            head = _ly_header(get_text(MUTOPIA_RAW + main))
        except OSError:
            skipped["header fetch"] = skipped.get("header fetch", 0) + 1
            continue
        time.sleep(delay)
        lic = MUTOPIA_LICENSES.get(head.get("license", ""))
        style = head.get("mutopiastyle") or head.get("style", "")
        if lic is None or style not in MUTOPIA_STYLES:
            reason = "licence" if lic is None else "style"
            skipped[reason] = skipped.get(reason, 0) + 1
            continue
        listing = get_text(MUTOPIA_SITE + piece + "/")
        time.sleep(delay)
        mids = sorted(set(re.findall(r'href="([^"]+\.midi?)"', listing)))
        if not mids:
            skipped["no midi"] = skipped.get("no midi", 0) + 1
            continue
        name = mids[0]
        url = MUTOPIA_SITE + piece + "/" + name
        rel = piece.removeprefix("ftp/").replace("/", "__") + ".mid"
        sha = fetch(url, d / rel)
        time.sleep(delay)
        entries.append({"path": rel, "url": url, "license": lic, "title": head.get("mutopiatitle", ""),
                        "composer": head.get("mutopiacomposer", ""), "style": style, "sha256": sha})
        print(f"  {rel} ({lic})", flush=True)
    write_manifest("mutopia", entries, f"Mutopia, styles {sorted(MUTOPIA_STYLES)}; skipped {skipped}")


def lieder() -> None:
    exe = shutil.which("mscore") or shutil.which("MuseScore4") or shutil.which("mscore4portable")
    if not exe:
        print("lieder: MuseScore CLI not found; skipped (install MuseScore 4 to convert .mscx)")
        return
    raise SystemExit("lieder: conversion not implemented yet")


def main(argv: list[str]) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("corpora", nargs="+", choices=["nottingham", "pdmx", "mutopia", "lieder"])
    args = ap.parse_args(argv)
    for c in args.corpora:
        globals()[c]()


if __name__ == "__main__":
    main(sys.argv[1:])
