"""Full evaluation of one checkpoint -> runs/<tag>/report.md (+ params.json).

Decoder parameters are swept on the synthetic fixtures' *tune* split in score
mode only; every other set (test split, real MAESTRO excerpts, eSpeak noise)
is held out from that sweep.

Usage: uv run python report.py runs/v2_16-24-32-32/model.pt
"""

import io
import json
import sys
from contextlib import redirect_stdout
from dataclasses import asdict, replace
from itertools import product
from pathlib import Path

import numpy as np

import eval_model as ev

ROOT = Path(__file__).resolve().parent.parent.parent
SETS = {
    "synthetic fixtures (3 pianos)": ROOT / "tools" / "mic-fixtures",
    "real piano (MAESTRO test excerpts)": ROOT / "tools" / "mic-fixtures-real",
    "independent noise (eSpeak speech, alone and over piano)": ROOT / "tools" / "mic-fixtures-noise",
}


def table(groups, split):
    buf = io.StringIO()
    with redirect_stdout(buf):
        ev.print_tables(groups, (split,))
    return buf.getvalue()


def main(ckpt):
    ckpt = Path(ckpt)
    model = ev.load_model(ckpt).to("cuda")
    base = ev.Params()
    syn = SETS["synthetic fixtures (3 pianos)"]
    groups, cache = ev.run_eval(model, syn, "score", base)
    best = (ev.objective(groups), base)
    grid = product((0.25, 0.35, 0.5), (0.6, 0.75, 0.9), (2, 3, 4), (0.15, 0.3, 0.5))
    for thr_exp, thr_unexp, hold, frame_thr in grid:
        q = replace(base, thr_exp=thr_exp, thr_unexp=thr_unexp, hold=hold, frame_thr=frame_thr)
        g, _ = ev.run_eval(model, syn, "score", q, cache)
        best = max(best, (ev.objective(g), q), key=lambda x: x[0])
    p = best[1]
    # Blind mode (nothing expected): its own threshold and persistence, swept on blind tune F1.
    bg, _ = ev.run_eval(model, syn, "blind", p, cache)
    bbest = (ev.objective(bg), p)
    for thr_blind, hold_blind in product((0.3, 0.4, 0.5, 0.6, 0.75), (1, 2, 3)):
        q = replace(p, thr_blind=thr_blind, hold_blind=hold_blind)
        g, _ = ev.run_eval(model, syn, "blind", q, cache)
        bbest = max(bbest, (ev.objective(g), q), key=lambda x: x[0])
    p = bbest[1]
    # Onset-time calibration: remove the mean onset error on the tune split (F1 itself ignores it).
    g, _ = ev.run_eval(model, syn, "score", p, cache)
    p = replace(p, calib=round(p.calib - float(np.mean(g["tune:all"].errs)) / 1000, 3))
    out = [f"# {ckpt.parent.name}\n", f"Decoder parameters (swept on tune split): `{asdict(p)}`\n"]
    for name, d in SETS.items():
        for mode in ("score", "blind", "wrong") if d == syn else ("score", "blind"):
            g, _ = ev.run_eval(model, d, mode, p, cache if d == syn else None)
            out.append(f"\n## {name}, {mode} mode\n")
            out.append(table(g, "test"))
            if d == syn and mode == "score":
                out.append("\nTune split (swept on):\n" + table(g, "tune"))
    (ckpt.parent / "report.md").write_text("\n".join(out))
    (ckpt.parent / "params.json").write_text(json.dumps(asdict(p)))
    print("\n".join(out))


if __name__ == "__main__":
    main(sys.argv[1])
