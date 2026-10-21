"""Downloads the extra piano sample sets into git-ignored data/pianos/ and
verifies their sha256 (pinned: a changed upstream file fails loudly).

Usage: uv run python fetch_pianos.py   then   uv run python pianos.py extract
Licenses and sources: docs/research/mic-input.md. Never commit the audio.
"""

import hashlib
import subprocess
import tarfile
import urllib.request

from pianos import DATA

SETS = {
    "kw.7z": (
        "https://freepats.zenvoid.org/Piano/UprightPianoKW/UprightPianoKW-SFZ+FLAC-20220221.7z",
        "3a66da3b25a2fd9499d90bcf09f1aee4431825796e249361b48af59b1201e703",
    ),
    "ydp.tar.bz2": (
        "https://freepats.zenvoid.org/Piano/YDP-GrandPiano/YDP-GrandPiano-SF2-20160804.tar.bz2",
        "d243dc3e182a60df2a16e92828c1821cf3eb5748b45e2e2bdcfa9cf7af056026",
    ),
}


def main():
    DATA.mkdir(parents=True, exist_ok=True)
    for name, (url, sha) in SETS.items():
        path = DATA / name
        if not path.exists():
            print("downloading", url)
            urllib.request.urlretrieve(url, path)
        got = hashlib.sha256(path.read_bytes()).hexdigest()
        if got != sha:
            raise SystemExit(f"{name}: sha256 {got} != pinned {sha}")
    subprocess.run(
        ["7z", "x", "-y", f"-o{DATA / 'kw'}", str(DATA / "kw.7z")], check=True, capture_output=True
    )
    with tarfile.open(DATA / "ydp.tar.bz2") as t:
        t.extractall(DATA / "ydp")
    print("ok")


if __name__ == "__main__":
    main()
