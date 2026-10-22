"""Downloads a subset of MAESTRO v3.0.0 (CC BY-NC-SA 4.0; real Disklavier piano
recordings with note labels) into git-ignored data/maestro/ as 16 kHz mono int16
`.npy` + `.json` note lists. Training/eval data only: nothing is shipped or
committed (docs/DECISIONS.md, license note). Audio comes from the 100 GB zip by
HTTP range requests, one file at a time.

Usage: uv run python fetch_maestro.py [--train 120] [--test 24]
"""

import argparse
import csv
import io
import json
import subprocess
import zipfile

import mido
import numpy as np
from remotezip import RemoteZip

from pianos import ROOT

BASE = "https://storage.googleapis.com/magentadata/datasets/maestro/v3.0.0/"
OUT = ROOT / "data" / "maestro"


def notes_of(midi_bytes):
    """[(onset_s, offset_s, pitch, velocity)] with the sustain pedal ignored."""
    mid = mido.MidiFile(file=io.BytesIO(midi_bytes))
    t = 0.0
    on = {}
    notes = []
    for msg in mid:  # iterates in seconds
        t += msg.time
        if msg.type == "note_on" and msg.velocity > 0:
            on[msg.note] = (t, msg.velocity)
        elif msg.type in ("note_off", "note_on") and msg.note in on:
            t0, v = on.pop(msg.note)
            notes.append((t0, t, msg.note, v))
    return notes


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--train", type=int, default=120)
    ap.add_argument("--test", type=int, default=24)
    args = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    with open(OUT / "maestro-v3.0.0.csv", encoding="utf8") as fh:
        rows = list(csv.DictReader(fh))
    rng = np.random.default_rng(0)
    pick = []
    for split, n in (("train", args.train), ("test", args.test)):
        pool = [r for r in rows if r["split"] == split]
        pick += [pool[i] for i in rng.permutation(len(pool))[:n]]
    midi_zip = zipfile.ZipFile(OUT / "maestro-v3.0.0-midi.zip")
    with RemoteZip(BASE + "maestro-v3.0.0.zip") as rz:
        for r in pick:
            stem = r["audio_filename"].rsplit("/", 1)[1][:-4]
            dst = OUT / r["split"] / stem
            dst.parent.mkdir(exist_ok=True)
            if dst.with_suffix(".npy").exists():
                continue
            wav = rz.read("maestro-v3.0.0/" + r["audio_filename"])
            pcm = subprocess.run(
                ["ffmpeg", "-v", "quiet", "-i", "-", "-ac", "1", "-ar", "16000", "-f", "s16le", "-"],
                input=wav,
                capture_output=True,
                check=True,
            ).stdout
            notes = notes_of(midi_zip.read("maestro-v3.0.0/" + r["midi_filename"]))
            np.save(dst.with_suffix(".npy"), np.frombuffer(pcm, dtype="<i2"))
            dst.with_suffix(".json").write_text(
                json.dumps({"composer": r["canonical_composer"], "year": r["year"], "notes": notes})
            )
            print(r["split"], stem[:60], round(len(pcm) / 32000), "s", flush=True)


if __name__ == "__main__":
    main()
