"""Exports held-out MAESTRO test excerpts (real piano recordings) as fixtures in
tools/mic-fixtures-real/ (git-ignored) so app/tool/mic_eval.dart and eval_model.py
score the same clips. `clean` is the recording as is; `room` adds a fixed-seed
room/EQ/noise chain (gen.room_chain). Truth = MAESTRO MIDI onsets.

Usage: uv run python export_real.py [--seconds 30]
"""

import argparse
import json
import wave

import numpy as np
from scipy.signal import resample_poly

import gen
from pianos import ROOT

OUT = ROOT / "tools" / "mic-fixtures-real"


def write_wav(path, y, sr=24000):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes((np.clip(y, -1, 1) * 32767).astype("<i2").tobytes())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seconds", type=int, default=30)
    a = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(5)
    truth = {}
    n = a.seconds * gen.SR
    for i, f in enumerate(gen.load_maestro("test")):
        audio = f["audio"]
        # Skip the first minute: applause and silence; pick a stretch with notes.
        start = int(rng.integers(60 * gen.SR, max(60 * gen.SR + 1, len(audio) - n)))
        y = np.asarray(audio[start : start + n], dtype=np.float32) / 32768
        t0 = start / gen.SR
        notes = [(on - t0, int(p)) for on, off, p, _ in f["notes"] if t0 <= on < t0 + a.seconds]
        for cond in ("clean", "room"):
            yy = y if cond == "clean" else gen.room_chain(np.random.default_rng(100 + i), y)
            yy = yy / (np.abs(yy).max() + 1e-9) * 0.5
            name = f"maestro__{cond}__{i:02d}.wav"
            write_wav(OUT / name, resample_poly(yy, 3, 2))
            truth[name] = {
                "split": "test",
                "condition": cond,
                "kind": "real",
                "piano": "maestro",
                "variant": "plain",
                "notes": [{"t": round(t, 4), "pitch": p} for t, p in sorted(notes)],
            }
    (OUT / "truth.json").write_text(json.dumps(truth, indent=1))
    print(len(truth), "clips,", sum(len(v["notes"]) for v in truth.values()), "notes")


if __name__ == "__main__":
    main()
