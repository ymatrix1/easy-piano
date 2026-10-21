"""Generate practice tunes for a course node with masked decoding, then rubric-check them.

    python -m melody_model.generate --run base1 --node essentials-1/rests -n 16 --out data/melody/gen/rests

Spec from the node: taught set from `content specs` (pitches per hand, durations,
rest durations, accidentals, max interval, polyphony, times) and the node's
skill spec (bars, bpm, hands, time, required patterns). Masks enforce at every
step: step grammar (plan triples, BAR, hands, events, END), taught pitches per
hand, max leap, taught durations that fit the bar, chord size; no ties, no
fingering (the arranger fingers later). Candidates are written as song JSON
(D17 fields), checked with `content check`, and ranked by mean log-probability
with a bonus for ending on the tonic. Similarity (`content similar`) runs on the kept ones.
"""

from __future__ import annotations

import argparse
import json
import math
import random
import subprocess
import sys
from pathlib import Path

from . import tokenizer as tk
from .difficulty import interval_number
from .download import ROOT
from .labels import tonic_pc
from .notation import DURATIONS, dur_beats, parse_hand, parse_pitch

K = tk.FIELDS["kind"]
KID = {k: i for i, k in enumerate(K)}
PID = {p: i for i, p in enumerate(tk.PITCHES)}
DID = {d: i for i, d in enumerate(tk.DURS)}
CONTENT = ROOT / "content"
CLI = ROOT / "tools" / "content-cli" / "target" / "debug" / "content.exe"
# skill-spec interval numbers -> largest leap in semitones (rubric.interval_semitones)
INTERVAL_SEMITONES = {2: 2, 3: 4, 4: 5, 5: 7, 6: 9, 7: 11, 8: 12}


def node_spec(node: str, specs_json: Path) -> dict:
    course, name = node.split("/")
    report = json.loads(specs_json.read_text(encoding="utf-8"))
    taught = next(n for n in report if n["course"] == course and n["node"] == name)["taught"]
    skill = json.loads((CONTENT / "skill-specs" / f"{course}.json").read_text(encoding="utf-8"))
    spec = next(n for n in skill["nodes"] if n["node"] == name)
    return {"course": course, "node": name, "taught": taught, "spec": spec}


def level_for(taught: dict) -> int:
    """Same scale as difficulty.level_of, from the taught set instead of a tune."""
    score = 0
    for ps in taught["pitches"].values():
        m = [parse_pitch(p).midi for p in ps]
        span = max(m) - min(m)
        score = max(score, 0 if span <= 7 else 1 if span <= 12 else 2 if span <= 19 else 3)
    shortest = min(dur_beats(d, 4) for d in taught["durations"])
    score += 0 if shortest >= 1 else 1 if shortest >= 0.5 else 2 if shortest >= 0.25 else 3
    acc = len(taught["accidentals"])
    score += 0 if not acc else 1 if acc <= 2 else 2
    score += len(taught["pitches"]) == 2
    score += max(taught["polyphony"].values()) > 1
    return 1 if score <= 1 else 2 if score <= 3 else 3 if score <= 6 else 4 if score <= 9 else 5


class Masker:
    """Tracks where decoding is and which ids are allowed next, per field."""

    def __init__(self, ns: dict, bars: int, time: str):
        t, s = ns["taught"], ns["spec"]
        self.hands = ["RH", "LH"] if s["hands"] == "both" else [s["hands"]]
        self.pitches = {h: [p for p in t["pitches"].get(h, [])] for h in self.hands}
        self.durs = [d for d in DURATIONS if d in t["durations"]]
        self.rest_durs = [d for d in DURATIONS if d in t.get("rest_durations", [])] if t["rests"] else []
        self.max_leap = INTERVAL_SEMITONES.get(t["max_interval"], 12)
        self.poly = {h: t["polyphony"].get(h, 1) for h in self.hands}
        num, den = (int(x) for x in time.split("/"))
        self.bar_beats = num * 4 / den  # in quarters
        self.bars = bars
        self.phase = "plan"
        self.plan_left = 3 * bars
        self.bar_no = 0
        self.hand_i = -1
        self.left = 0.0
        self.chord_n = 0
        self.prev = {h: None for h in self.hands}

    def kinds(self) -> list[str]:
        if self.phase == "plan":
            if self.plan_left == 0:
                return ["PLAN_END"]
            return [k for k in K if k.startswith(("SEC_", "CAD_", "CON_")[(3 * self.bars - self.plan_left) % 3])]
        if self.phase == "bar":
            return ["BAR"] if self.bar_no < self.bars else ["END"]
        if self.phase == "hand":
            return [self.hands[self.hand_i]]
        # events
        out = []
        if self.left > 1e-9:
            out.append("NOTE")
            if self.rest_durs:
                out.append("REST")
        elif self.hand_i + 1 < len(self.hands):
            out.append(self.hands[self.hand_i + 1])
        else:
            out.append("BAR" if self.bar_no < self.bars else "END")
        hand = self.hands[self.hand_i]
        if self.chord_n and self.chord_n < self.poly[hand]:
            out.append("CHORD")
        return out

    def pitches_for(self, kind: str) -> list[str]:
        hand = self.hands[self.hand_i]
        ps = self.pitches[hand]
        if kind == "CHORD":
            low = parse_pitch(self.chord_top).midi
            return [p for p in ps if low < parse_pitch(p).midi <= self.chord_low + 12]
        prev = self.prev[hand]
        if prev is None:
            return ps
        near = [p for p in ps if abs(parse_pitch(p).midi - prev) <= self.max_leap]
        return near or [min(ps, key=lambda p: abs(parse_pitch(p).midi - prev))]  # never a leap the level has not taught

    def durs_for(self, kind: str) -> list[str]:
        pool = self.rest_durs if kind == "REST" else self.durs
        return [d for d in pool if dur_beats(d, 4) <= self.left + 1e-9]

    def advance(self, kind: str, pitch: str, dur: str):
        if self.phase == "plan":
            if kind == "PLAN_END":
                self.phase = "bar"
            else:
                self.plan_left -= 1
            return
        if kind == "BAR":
            self.bar_no += 1
            self.hand_i = 0
            self.phase = "hand"
            return
        if kind in ("RH", "LH"):
            self.hand_i = self.hands.index(kind)
            self.phase = "events"
            self.left = self.bar_beats
            self.chord_n = 0
            return
        hand = self.hands[self.hand_i]
        if kind == "NOTE":
            m = parse_pitch(pitch).midi
            self.left -= dur_beats(dur, 4)
            self.chord_n, self.chord_top, self.chord_low = 1, pitch, m
            self.prev[hand] = m
        elif kind == "CHORD":
            self.chord_n += 1
            self.chord_top = pitch
        elif kind == "REST":
            self.left -= dur_beats(dur, 4)
            self.chord_n = 0


def build_prefix(ns: dict, key: str, bars: int, time: str, styles: list[str], level: int | None) -> list:
    t, s = ns["taught"], ns["spec"]
    allp = [p for h in ns["taught"]["pitches"].values() for p in h]
    lo = min(allp, key=lambda p: parse_pitch(p).midi)
    hi = max(allp, key=lambda p: parse_pitch(p).midi)
    spec = tk.Spec(time=time, key=key, bars=bars, range_lo=lo, range_hi=hi,
                   durs=[d for d in DURATIONS if d in t["durations"]],
                   hands={"RH": "RH", "LH": "LH", "both": "BOTH"}[s["hands"]],
                   course=ns["course"] if ns["course"] in tk.COURSES else "none",
                   patterns=s.get("required", []), styles=styles, level=level)
    return [tk.step("BOS")] + tk.encode_spec(spec)


def sample_tune(model, prefix: list, masker: Masker, rng: random.Random, temperature: float, torch, device) -> tuple[list, float]:
    steps = list(prefix) + [tk.step("PLAN")]
    logp = 0.0
    n = 0
    while True:
        x = torch.tensor([steps], dtype=torch.long, device=device)
        with torch.no_grad():
            h = model.hidden(x)[:, -1:]
            kinds = masker.kinds()
            z = h
            lg = model.heads[0](z)[0, 0].float()
            kind, lp = _pick(lg, [KID[k] for k in kinds], rng, temperature, torch)
            logp += lp
            kname = K[kind]
            pitch = dur = tk.NONE
            z = z + model.cond[0](torch.tensor([[kind]], device=device))
            if kname in ("NOTE", "CHORD"):
                pid, lp = _pick(model.heads[1](z)[0, 0].float(), [PID[p] for p in masker.pitches_for(kname)], rng, temperature, torch)
                logp += lp
                pitch = tk.PITCHES[pid]
                z = z + model.cond[1](torch.tensor([[pid]], device=device))
            if kname in ("NOTE", "REST"):
                allowed = masker.durs_for(kname)
                if not allowed:
                    raise RuntimeError("no duration fits")
                did, lp = _pick(model.heads[2](z)[0, 0].float(), [DID[d] for d in allowed], rng, temperature, torch)
                logp += lp
                dur = tk.DURS[did]
        steps.append(tk.step(kname, pitch=pitch, dur=dur))
        n += 1
        masker.advance(kname, pitch, dur)
        if kname == "END" or len(steps) >= model.c.ctx:
            return steps, logp / max(1, n)


def _pick(logits, allowed: list[int], rng: random.Random, temperature: float, torch) -> tuple[int, float]:
    mask = torch.full_like(logits, float("-inf"))
    mask[allowed] = 0
    lp = torch.log_softmax(logits / temperature + mask, dim=-1)
    probs = lp.exp().cpu().tolist()
    r, acc = rng.random(), 0.0
    for i in allowed:
        acc += probs[i]
        if r <= acc:
            return i, lp[i].item()
    return allowed[-1], lp[allowed[-1]].item()


def ends_on_tonic(song: dict) -> bool:
    pc, _ = tonic_pc(song["key"])
    last = song["bars"][-1].get("RH") or song["bars"][-1].get("LH") or ""
    notes = [e for e in parse_hand(last) if not e.is_rest]
    return bool(notes) and max(p.midi for p in notes[-1].pitches) % 12 == pc


def to_song(decoded: dict, ns: dict, idx: int, run: str, seed: int, bpm: float) -> dict:
    return {"id": f"gen-{ns['course']}-{ns['node']}-{seed}-{idx:02d}", "title": f"Generated {ns['node']} {idx}",
            "composer": "Easy Piano melody model", "arranger": "Easy Piano melody model", "source": "generated",
            "source_url": None, "license": "CC0-1.0", "composition_license": "CC0-1.0",
            "generator": {"method": "melody-model", "tool": "tools/melody-model", "model": run, "seed": seed},
            "spec_node": f"{ns['course']}/{ns['node']}", "bpm": bpm, "time": decoded["time"], "key": decoded["key"],
            "bars": decoded["bars"]}


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--run", required=True, help="data/melody/runs/<run>/ckpt.pt")
    ap.add_argument("--node", required=True, help="course/node")
    ap.add_argument("-n", type=int, default=16)
    ap.add_argument("--key", default="C")
    ap.add_argument("--bars", type=int, default=None)
    ap.add_argument("--style", action="append", default=[])
    ap.add_argument("--level", type=int, default=None, help="default: from the taught set")
    ap.add_argument("--temperature", type=float, default=0.9)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--keep", type=int, default=4)
    ap.add_argument("--device", default="cpu")
    ap.add_argument("--out", required=True)
    args = ap.parse_args(argv)

    import torch

    from .model import CompoundGPT, Config

    ck = torch.load(ROOT / "data" / "melody" / "runs" / args.run / "ckpt.pt", map_location=args.device, weights_only=False)
    model = CompoundGPT(Config(**ck["config"])).to(args.device).eval()
    model.load_state_dict(ck["model"])
    specs_json = ROOT / "data" / "melody" / "specs.json"
    subprocess.run([str(CLI), "specs", str(CONTENT), "--out", str(specs_json)], check=False, capture_output=True)
    ns = node_spec(args.node, specs_json)
    s = ns["spec"]
    time = s.get("time") or ns["taught"]["times"][0]
    bars = args.bars or s["bars"][1]
    level = args.level or level_for(ns["taught"])
    prefix = build_prefix(ns, args.key, bars, time, args.style, level)
    rng = random.Random(args.seed)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    cands = []
    for i in range(args.n):
        try:
            steps, score = sample_tune(model, prefix, Masker(ns, bars, time), rng, args.temperature, torch, args.device)
            decoded = tk.decode(steps)
        except (RuntimeError, tk.InvalidSequence) as e:
            print(f"candidate {i}: {e}")
            continue
        song = to_song(decoded, ns, i, args.run, args.seed, round(sum(s["bpm"]) / 2))
        f = out / f"{song['id']}.json"
        f.write_text(json.dumps(song, indent=1), encoding="utf-8")
        cands.append((f, song, score))
    res = subprocess.run([str(CLI), "check", str(CONTENT), args.node, *map(str, (c[0] for c in cands))], capture_output=True, text=True)
    errors = json.loads(res.stdout or "{}")
    passing = [(f, s_, sc + (0.5 if ends_on_tonic(s_) else 0)) for f, s_, sc in cands if not errors.get(str(f))]
    passing.sort(key=lambda x: -x[2])
    report = {"node": args.node, "run": args.run, "candidates": len(cands), "rubric_pass": len(passing),
              "kept": [str(f.name) for f, _, _ in passing[:args.keep]],
              "errors": {Path(k).name: v for k, v in errors.items() if v}}
    (out / "report.json").write_text(json.dumps(report, indent=1), encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k != "errors"}, indent=1))


if __name__ == "__main__":
    main(sys.argv[1:])
