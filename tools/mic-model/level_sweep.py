"""Quiet-mic and strictness check for the shipped decoder (docs/research/mic-input.md, "Quiet mics").

Takes the held-out `room` single/chord/melody fixtures, scales each clip to a peak level, optionally runs
the same slow gain the web app puts in front of the model (target peak 0.3, capped), and scores it while
the lesson expects only C4 (the setup panel / calibration case: the student plays any key). Also sweeps
the threshold for unexpected notes against speech false notes.

Usage: uv run python level_sweep.py [runs/v2_16-16-24-24]
"""

import json
import sys
from dataclasses import replace
from pathlib import Path

import numpy as np

import eval_model as ev

ROOT = Path(__file__).resolve().parent.parent.parent
FIX = ROOT / "tools" / "mic-fixtures"


def agc(a, cap, chunk=170):
    """The app's slow gain: peak follower (decay 0.9995 per 512 samples at 48 kHz), floor 0.01, capped."""
    env, out = 0.01, np.empty_like(a)
    for i in range(0, len(a), chunk):
        c = a[i : i + chunk]
        env = max(float(np.abs(c).max()), env * 0.9995)
        out[i : i + chunk] = c * min(cap, 0.3 / max(env, 0.01))
    return out


def main(run):
    run = Path(run)
    model = ev.load_model(run / "model.pt").to("cuda")
    base = ev.Params(**json.loads((run / "params.json").read_text()))
    truth = json.loads((FIX / "truth.json").read_text())
    names = [
        n
        for n, v in truth.items()
        if v["split"] == "test" and v["kind"] in ("single", "melody", "chord") and v["condition"] == "room"
    ]
    audio = {n: ev.read_wav(FIX / n) for n in names}

    def score(prep, p, expected):
        tp = fp = fn = 0
        for n in names:
            on, fr = ev.predict(model, prep(audio[n]).astype(np.float32))
            notes = [(x["t"], x["pitch"]) for x in truth[n]["notes"]]
            a, b, c, *_ = ev.match(ev.decode(on, fr, lambda t: expected, p), notes, "score", 0)
            tp, fp, fn = tp + a, fp + b, fn + c
        return tp / (tp + fn), tp / max(tp + fp, 1)

    print("lesson expects C4, input scaled to a peak level, with and without the app's gain (cap 8x):")
    print("| Peak (dBFS) | No gain: recall / precision | Gain 8x: recall / precision |")
    print("|---|---|---|")
    for db in (-30, -40, -50, -60, -70):

        def level(a, db=db):
            return a / (np.abs(a).max() + 1e-9) * 10 ** (db / 20)

        r0 = score(level, base, {60})
        r8 = score(lambda a: agc(level(a), 8), base, {60})
        print(f"| {db} | {r0[0]:.2f} / {r0[1]:.2f} | {r8[0]:.2f} / {r8[1]:.2f} |")

    print(
        "\nthreshold for unexpected notes (lesson expects C4, normal level) vs speech false notes (C-major expected):"
    )
    print("| thr_unexp | recall / precision | speech false notes/min |")
    print("|---|---|---|")
    for thr in (0.9, 0.8, 0.7, 0.6):
        p = replace(base, thr_unexp=thr)
        r = score(lambda a: a, p, {60})
        g, _ = ev.run_eval(model, ROOT / "tools" / "mic-fixtures-noise", "score", p)
        s = g["test:speech"]
        print(f"| {thr} | {r[0]:.2f} / {r[1]:.2f} | {s.fp / s.seconds * 60:.1f} |")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "runs/v2_16-16-24-24")
