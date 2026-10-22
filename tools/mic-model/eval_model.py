"""Scores a trained PianoNet on a fixture dir (tools/mic_fixtures.py or export_real.py)
with the same rules as app/tool/mic_eval.dart, so the tables compare directly.

A detected note-on matches a truth note with the same pitch and an onset within
+-50 ms; each truth note matches at most once. Modes: blind (no expected notes),
score (notes due from 0.3 s ago to 0.6 s ahead are expected; noise clips expect
C major), wrong (expects a whole tone higher: a detected expected pitch is a
phantom pass).

Usage: uv run python eval_model.py runs/v1/model.pt [--fixtures ../mic-fixtures]
         [--mode score] [--sweep] [--params thr_exp=.4,thr_unexp=.8,...]
"""

import argparse
import json
import wave
from bisect import bisect_right
from dataclasses import dataclass, replace
from pathlib import Path

import numpy as np
import torch
from scipy.signal import resample_poly

from features import HOP, MIDI_LO, SR, WIN, log_bands
from model import LOOKAHEAD, PianoNet

TOL = 0.05
HERE = Path(__file__).parent


@dataclass(frozen=True)
class Params:
    thr_exp: float = 0.4  # onset prob needed for an expected key
    thr_unexp: float = 0.8  # ... for any other key (the reference app's value; a sweep on synthetic clips preferred 0.9, but quiet real mics need this)
    frame_thr: float = 0.5  # frame prob an unexpected start must sustain
    hold: int = 3  # frames an unexpected start is held (persistence)
    thr_blind: float = 0.6  # onset prob when nothing is expected (free play, calibration)
    hold_blind: int = 2  # persistence frames in that case
    octave_guard: bool = True  # when notes are expected: drop an unexpected onset an octave below a key that fired / is expected
    guard_frames: int = 6  # how far back (frames) a firing key above counts
    refractory: int = 6  # frames before a key may retrigger
    calib: float = 0.0  # seconds added to the frame time to estimate the onset


def load_model(path):
    ck = torch.load(path, map_location="cpu")
    m = PianoNet(*ck["c"])
    m.load_state_dict(ck["model"])
    return m.eval()


def read_wav(path):
    with wave.open(str(path), "rb") as w:
        sr = w.getframerate()
        x = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float32) / 32768
    if sr != SR:
        x = resample_poly(x, SR // np.gcd(SR, sr), sr // np.gcd(SR, sr)).astype(np.float32)
    return x


@torch.no_grad()
def predict(model, audio, dev="cuda"):
    """-> onset, frame probabilities [T, 88]."""
    x = log_bands(torch.from_numpy(audio)[None].to(dev))
    lo, lf = model.forward_seq(x)
    return torch.sigmoid(lo)[0].cpu().numpy(), torch.sigmoid(lf)[0].cpu().numpy()


def avail(g):
    """Time (s) frame g's output exists when streaming: its window ends at g*HOP+WIN/2, plus look-ahead."""
    return ((g + LOOKAHEAD) * HOP + WIN // 2) / SR


def decode(on, fr, expected_at, p: Params):
    """Streaming decoder -> [(onset_time, pitch, detected_at)]. expected_at(t) -> set of MIDI pitches.
    Same logic as Decoder in app/web/mic_model_core.js."""
    T = len(on)
    out = []
    armed = np.ones(88, bool)
    last = np.full(88, -999)
    pending = []  # (g, key)
    fired = np.full(88, -999)  # last frame each key's onset crossed its threshold
    lo_thr = min(p.thr_exp, p.thr_unexp, p.thr_blind)
    any_hi = (on >= lo_thr).any(axis=1)  # frames where some key could fire
    low = on < 0.5 * p.thr_exp
    for g in range(T - LOOKAHEAD):
        armed |= low[g]
        if not any_hi[g] and not pending:
            continue
        t = avail(g)
        if any_hi[g]:
            exp = expected_at(t)
            ek = np.zeros(88, bool)
            for pitch in exp:
                if 0 <= pitch - MIDI_LO < 88:
                    ek[pitch - MIDI_LO] = True
            blind = not exp
            thr = np.where(ek, p.thr_exp, p.thr_blind if blind else p.thr_unexp)
            fire = armed & (on[g] >= thr) & (g - last >= p.refractory)
            fired[fire] = g  # before the loop: a ghost and its real note fire in the same frame
            for k in np.flatnonzero(fire):
                armed[k] = False
                last[k] = g
                if (
                    p.octave_guard
                    and not blind
                    and not ek[k]
                    and k + 12 < 88
                    and (ek[k + 12] or g - fired[k + 12] <= p.guard_frames)
                ):
                    continue  # ghost: the octave above is sounding
                if ek[k]:
                    out.append((g * HOP / SR + p.calib, k + MIDI_LO, t))
                else:
                    pending.append((g, k, p.hold_blind if blind else p.hold))
        keep = []
        for g0, k, hold in pending:
            if g - g0 >= hold:
                if fr[max(g - 1, 0) : g + 1, k].min() >= p.frame_thr:  # still sounding at the end of the hold
                    out.append((g0 * HOP / SR + p.calib, k + MIDI_LO, t))
            else:
                keep.append((g0, k, hold))
        pending = keep
    return out


def expected_fn(notes, mode):
    if mode == "blind":
        return lambda t: ()
    if not notes:
        return lambda t: (60, 64, 67)
    sh = 2 if mode == "wrong" else 0
    ordered = sorted(notes)
    ons = [on for on, _ in ordered]
    pitches = [p + sh for _, p in ordered]
    return lambda t: set(pitches[bisect_right(ons, t - 0.3) : bisect_right(ons, t + 0.6)])


class Score:
    def __init__(self):
        self.tp = self.fp = self.fn = self.phantom = self.expected = 0
        self.seconds = 0.0
        self.errs, self.delays = [], []

    def add(self, other_fields):
        pass

    def row(self, name):
        if self.tp + self.fn == 0 and self.seconds > 0:
            return f"| {name} | 0 | false notes: {self.fp} in {self.seconds:.0f} s = {self.fp / self.seconds * 60:.1f}/min | | | | |"
        p = self.tp / max(self.tp + self.fp, 1)
        r = self.tp / max(self.tp + self.fn, 1)
        f = 2 * p * r / (p + r) if p + r else 0
        ab = np.sort(np.abs(self.errs)) if self.errs else np.array([0.0])
        dl = np.sort(self.delays) if self.delays else np.array([0.0])
        q = lambda a, x: f"{a[min(int(len(a) * x), len(a) - 1)]:.0f}"
        mean = np.mean(self.errs) if self.errs else 0
        ph = f" phantom {self.phantom}/{self.expected} |" if self.expected else ""
        return f"| {name} | {self.tp + self.fn} | {p:.3f} | {r:.3f} | {f:.3f} | {mean:.1f} / {q(ab, 0.95)} | {q(dl, 0.5)} / {q(dl, 0.95)} |{ph}"


def match(dets, notes, mode, secs):
    used = [False] * len(notes)
    tp, phantom = 0, 0
    errs, delays = [], []
    for t, pitch, at in dets:
        hit = next(
            (
                i
                for i, (nt, npitch) in enumerate(notes)
                if not used[i] and npitch == pitch and abs(nt - t) <= TOL
            ),
            -1,
        )
        if hit >= 0:
            used[hit] = True
            tp += 1
            errs.append((t - notes[hit][0]) * 1000)
            delays.append((at - notes[hit][0]) * 1000)
        elif mode == "wrong" and any(npitch + 2 == pitch and abs(nt - t) < 0.7 for nt, npitch in notes):
            phantom += 1
    return tp, len(dets) - tp, len(notes) - tp, phantom, errs, delays


GROUPS = [
    "all",
    "clean",
    "room",
    "noisy",
    "single",
    "chord",
    "doubled",
    "noise",
    "melody",
    "two-hands",
    "real",
    "speech",
    "mixed",
    "piano=salamander",
    "piano=kw",
    "piano=ydp",
    "variant=plain",
    "variant=detune",
    "variant=inharm",
    "variant=speaker",
]


def load_fixtures(dirpath):
    truth = json.loads((Path(dirpath) / "truth.json").read_text())
    return truth


def run_eval(model, dirpath, mode, p, cache=None, splits=("test", "tune"), dev="cuda"):
    truth = load_fixtures(dirpath)
    cache = {} if cache is None else cache
    groups = {}
    for name, info in truth.items():
        if name not in cache:
            audio = read_wav(Path(dirpath) / name)
            cache[name] = (predict(model, audio, dev), len(audio) / SR)
        (on, fr), secs = cache[name]
        notes = [(n["t"], n["pitch"]) for n in info["notes"]]
        dets = decode(on, fr, expected_fn(notes, mode), p)
        tp, fp, fn, ph, errs, delays = match(dets, notes, mode, secs)
        piano = info.get("piano")
        gs = ["all", info["condition"], info["kind"]]
        if piano and piano != "none":
            gs += [f"piano={piano}", f"variant={info['variant']}"]
        for g in gs:
            s = groups.setdefault(f"{info.get('split', 'tune')}:{g}", Score())
            s.tp += tp
            s.fp += fp
            s.fn += fn
            s.phantom += ph
            s.errs += errs
            s.delays += delays
            s.seconds += secs if not notes else 0
            s.expected += len(notes) if mode == "wrong" else 0
    return groups, cache


def print_tables(groups, splits=("test", "tune")):
    for split in splits:
        print(f"\n{split} set{' (held out)' if split == 'test' else ''}:")
        print(
            "| Group | Notes | P | R | F1 | Onset error mean / p95 (ms) | Computed report delay p50 / p95 (ms) |"
        )
        print("|---|---|---|---|---|---|---|")
        for g in GROUPS:
            s = groups.get(f"{split}:{g}")
            if s:
                print(s.row(g))


def objective(groups, split="tune"):
    """Sweep target: tune-split F1 minus a false-note penalty."""
    a = groups[f"{split}:all"]
    p = a.tp / max(a.tp + a.fp, 1)
    r = a.tp / max(a.tp + a.fn, 1)
    f1 = 2 * p * r / (p + r) if p + r else 0
    nz = groups.get(f"{split}:noise")
    fpm = nz.fp / nz.seconds * 60 if nz and nz.seconds else 0
    return f1 - 0.002 * fpm


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ckpt")
    ap.add_argument("--fixtures", default=str(HERE.parent.parent / "tools" / "mic-fixtures"))
    ap.add_argument("--mode", default="score")
    ap.add_argument("--sweep", action="store_true")
    ap.add_argument("--params", default="")
    ap.add_argument("--cpu", action="store_true")
    a = ap.parse_args()
    dev = "cpu" if a.cpu else "cuda"
    model = load_model(a.ckpt).to(dev)
    p = Params()
    if a.params:
        p = replace(
            p, **{k: type(getattr(p, k))(v) for k, v in (kv.split("=") for kv in a.params.split(","))}
        )
    groups, cache = run_eval(model, a.fixtures, a.mode, p, dev=dev)
    if a.sweep:
        best = (objective(groups), p)
        for thr_exp in (0.25, 0.35, 0.5):
            for thr_unexp in (0.6, 0.75, 0.9):
                for hold in (2, 3, 4):
                    for calib in (0.0, 0.016, 0.032):
                        q = replace(p, thr_exp=thr_exp, thr_unexp=thr_unexp, hold=hold, calib=calib)
                        g, _ = run_eval(model, a.fixtures, a.mode, q, cache, dev=dev)
                        best = max(best, (objective(g), q), key=lambda x: x[0])
        p = best[1]
        print("best params (tune split):", p)
        groups, _ = run_eval(model, a.fixtures, a.mode, p, cache, dev=dev)
    print_tables(groups)


if __name__ == "__main__":
    main()
