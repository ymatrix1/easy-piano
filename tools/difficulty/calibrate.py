"""Fit the song difficulty model (docs/specs/difficulty.md, D23).

Skill scores come from Rust (`content level`), so Python never re-implements
features. The fit is a cumulative-logit ordinal model with non-negative skill
weights, trained on:

1. course anchors: each course song's expected level from its journey position;
2. course order: songs at later nodes should score higher (pairwise logistic);
3. node envelopes: the most of each skill seen up to a node, at that node's level;
4. simplified variants: a song without its left hand and chords is easier;
5. PDMX `complexity` (0-3) as weak labels, only if the git-ignored PDMX data is
   present locally (`<data>/raw/pdmx/PDMX.csv`, `<data>/dataset/tunes.jsonl`).

Every 5th course song is held out for the reported Kendall tau, then the model
is refit on all songs and written to core/data/difficulty-weights.json.

    python tools/difficulty/calibrate.py [--data data/melody] [--pdmx-max 3000] [--dry-run]
"""

from __future__ import annotations

import argparse
import csv
import json
import random
import subprocess
import sys
import tempfile
from datetime import date
from pathlib import Path

import numpy as np
from scipy.optimize import minimize
from scipy.stats import kendalltau, spearmanr

ROOT = Path(__file__).resolve().parents[2]
WEIGHTS = ROOT / "core" / "data" / "difficulty-weights.json"
SKILLS = ["reading", "hand_position", "intervals", "rhythm", "key", "coordination", "texture", "speed"]
# PDMX complexity 0-3 read as these levels; weak labels, see the spec.
PDMX_LEVEL = {0: 3, 1: 5, 2: 7, 3: 9}
GRADED = ("RH", "LH")
# Every skill keeps some weight, so more of any difficulty raises the level.
MIN_WEIGHT = 0.25
# Thresholds without data (levels above the course) keep this spacing.
PRIOR_SPACING = 0.6


def content(*args: str) -> str:
    cmd = ["cargo", "run", "-q", "--release", "--manifest-path", str(ROOT / "tools/content-cli/Cargo.toml"), "--", "level", *args]
    return subprocess.run(cmd, check=True, capture_output=True, text=True, encoding="utf-8").stdout


def score_rows(rows: list[dict]) -> list[dict]:
    """Skills for tune rows, through `content level --jsonl`."""
    with tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False, encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")
        path = f.name
    try:
        return [json.loads(line) for line in content(str(ROOT / "content"), "--jsonl", path).splitlines() if line.strip()]
    finally:
        Path(path).unlink()


def simplify(song: dict) -> dict | None:
    """Right hand only, chords reduced to their top note. None if nothing changes."""
    bars = []
    changed = False
    for bar in song["bars"]:
        rh = bar.get("RH")
        changed |= any(h in bar for h in GRADED if h != "RH")
        if rh is None:
            durs = [t.split(":", 1)[1].split("@")[0] for t in bar.get("LH", "").split() if ":" in t]
            rh = " ".join(f"r:{d}" for d in durs) or "r:1"
        out = []
        for tok in rh.split():
            if ":" in tok and not tok.startswith("r:") and not tok.startswith("{"):
                head, rest = tok.split(":", 1)
                notes = split_chord(head)
                if len(notes) > 1:
                    changed = True
                    tok = f"{notes[-1]}:{rest.split('@')[0]}"
            out.append(tok)
        bars.append({"RH": " ".join(out)})
    if not changed:
        return None
    return {**song, "id": song["id"] + "~simple", "bars": bars}


def split_chord(head: str) -> list[str]:
    notes, cur = [], ""
    for ch in head:
        if ch.isalpha() and ch.upper() in "ABCDEFG" and cur and cur[-1].isdigit():
            notes.append(cur)
            cur = ""
        cur += ch
    return notes + ([cur] if cur else [])


def pdmx_rows(data: Path, limit: int, seed: int = 7) -> list[tuple[dict, int]]:
    csv_path, tunes = data / "raw" / "pdmx" / "PDMX.csv", data / "dataset" / "tunes.jsonl"
    if not (csv_path.exists() and tunes.exists()):
        return []
    csv.field_size_limit(1 << 30)
    complexity = {}
    with csv_path.open(encoding="utf-8", newline="") as f:
        for row in csv.DictReader(f):
            try:
                complexity[Path(row["path"]).stem] = int(float(row["complexity"]))
            except (KeyError, ValueError):
                pass
    by_c: dict[int, list[dict]] = {}
    with tunes.open(encoding="utf-8") as f:
        for line in f:
            t = json.loads(line)
            if t.get("corpus") != "pdmx":
                continue
            c = complexity.get(t["id"].split(":", 1)[1])
            if c in PDMX_LEVEL:
                by_c.setdefault(c, []).append(t)
    rng = random.Random(seed)
    out = []
    per = max(1, limit // max(1, len(by_c)))
    for c, ts in sorted(by_c.items()):
        rng.shuffle(ts)
        out += [(t, c) for t in ts[:per]]
    return out


class Fit:
    """Weights w >= 0 and ordered thresholds theta from weighted signals."""

    def __init__(self, reg: float = 0.05):
        self.reg = reg
        self.ord_x, self.ord_y, self.ord_w = [], [], []
        self.pair_hi, self.pair_lo, self.pair_w = [], [], []

    def ordinal(self, x, y, w):
        self.ord_x.append(x), self.ord_y.append(int(np.clip(round(y), 1, 10))), self.ord_w.append(w)

    def pair(self, hi, lo, w):
        self.pair_hi.append(hi), self.pair_lo.append(lo), self.pair_w.append(w)

    @staticmethod
    def unpack(p):
        w = p[:8]
        theta = p[8] + np.concatenate([[0.0], np.cumsum(p[9:])])
        return w, theta

    def loss(self, p):
        w, theta = self.unpack(p)
        total = self.reg * np.sum((w - 1.0) ** 2) + self.reg * np.sum((p[9:] - PRIOR_SPACING) ** 2)
        if self.ord_x:
            z = np.array(self.ord_x) @ w
            y = np.array(self.ord_y)
            t = np.concatenate([[-np.inf], theta, [np.inf]])
            sig = lambda a: 1.0 / (1.0 + np.exp(-a))
            prob = sig(t[y] - z) - sig(t[y - 1] - z)
            total += np.sum(np.array(self.ord_w) * -np.log(np.clip(prob, 1e-12, None)))
        if self.pair_hi:
            d = (np.array(self.pair_hi) - np.array(self.pair_lo)) @ w
            total += np.sum(np.array(self.pair_w) * np.logaddexp(0.0, -4.0 * (d - 0.1)))
        return total

    def run(self, start):
        p0 = np.concatenate([start["weights"], [start["thresholds"][0]], np.maximum(np.diff(start["thresholds"]), 0.05)])
        bounds = [(MIN_WEIGHT, 30.0)] * 8 + [(None, None)] + [(0.05, 3.0)] * 8
        r = minimize(self.loss, p0, method="L-BFGS-B", bounds=bounds)
        w, theta = self.unpack(r.x)
        return [round(float(v), 4) for v in w], [round(float(v), 4) for v in theta], float(r.fun)


def level_score(w, theta, x):
    z = np.asarray(x) @ np.asarray(w)
    return 1.0 + np.sum(1.0 / (1.0 + np.exp(np.asarray(theta)[None, :] - np.atleast_1d(z)[:, None])), axis=1)


def build(course, envelopes, simple, pdmx, held: set[str]):
    f = Fit()
    train = [c for c in course if c["id"] not in held]
    for c in train:
        f.ordinal(c["skills"], c["expected"], 1.0)
    for a in train:
        for b in train:
            if b["index"] > a["index"]:
                f.pair(b["skills"], a["skills"], 2.0 / len(train))
    for env, exp in envelopes:
        f.ordinal(env, exp, 0.3)
    for orig, s in simple:
        if orig["id"] not in held:
            f.pair(orig["skills"], s, 1.0)
    if pdmx:
        each = 0.3 * len(train) / len(pdmx)
        for x, c in pdmx:
            f.ordinal(x, PDMX_LEVEL[c], each)
    return f


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", type=Path, default=ROOT / "data" / "melody")
    ap.add_argument("--pdmx-max", type=int, default=3000)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    start = json.loads(WEIGHTS.read_text(encoding="utf-8"))
    report = json.loads(content(str(ROOT / "content"), "--course"))
    course = report["songs"]
    lo, hi = start["course_levels"]
    n_nodes = report["nodes"]
    env = np.zeros(8)
    envelopes = []
    for i in range(n_nodes):
        for c in (c for c in course if c["index"] == i):
            env = np.maximum(env, c["skills"])
        if env.any():
            envelopes.append((env.copy(), lo + (hi - lo) * i / max(1, n_nodes - 1)))

    songs = {p.stem: json.loads(p.read_text(encoding="utf-8")) for p in (ROOT / "content" / "songs").glob("*.json")}
    variants = [v for c in course if (v := simplify(songs[c["id"]]))]
    scored = {r["id"]: r for r in score_rows(variants)}
    simple = [(c, scored[c["id"] + "~simple"]["skills"]) for c in course if c["id"] + "~simple" in scored and "skills" in scored[c["id"] + "~simple"]]

    pdmx_raw = pdmx_rows(a.data, a.pdmx_max)
    pdmx = []
    if pdmx_raw:
        rows = score_rows([t for t, _ in pdmx_raw])
        pdmx = [(r["skills"], c) for r, (_, c) in zip(rows, pdmx_raw) if "skills" in r]
    print(f"course songs {len(course)}, nodes {n_nodes}, envelopes {len(envelopes)}, simplified pairs {len(simple)}, "
          f"pdmx {len(pdmx)} ({'present' if pdmx_raw else 'absent, skipped'})")

    held = {c["id"] for k, c in enumerate(course) if k % 5 == 2}
    w, theta, _ = build(course, envelopes, simple, pdmx, held).run(start)
    test = [c for c in course if c["id"] in held]
    ls = level_score(w, theta, [c["skills"] for c in test])
    tau_held = kendalltau(ls, [c["index"] for c in test]).statistic
    base = level_score(start["weights"], start["thresholds"], [c["skills"] for c in test])
    tau_base = kendalltau(base, [c["index"] for c in test]).statistic

    w, theta, loss = build(course, envelopes, simple, pdmx, set()).run(start)
    all_ls = level_score(w, theta, [c["skills"] for c in course])
    tau_all = kendalltau(all_ls, [c["index"] for c in course]).statistic
    mae = float(np.mean(np.abs(np.clip(np.round(all_ls), 1, 10) - [c["expected"] for c in course])))
    simple_ok = sum(level_score(w, theta, [o["skills"]])[0] >= level_score(w, theta, [s])[0] for o, s in simple)
    fit = {
        "date": date.today().isoformat(),
        "signals": ["course anchors", "course order pairs", "node envelopes", "simplified pairs"] + (["pdmx complexity"] if pdmx else []),
        "course_songs": len(course),
        "held_out": len(test),
        "kendall_tau_held_out": round(float(tau_held), 3),
        "kendall_tau_held_out_prior": round(float(tau_base), 3),
        "kendall_tau_all": round(float(tau_all), 3),
        "course_level_mae": round(mae, 3),
        "simplified_easier": f"{simple_ok}/{len(simple)}",
    }
    if pdmx:
        pl = level_score(w, theta, [x for x, _ in pdmx])
        cs = [c for _, c in pdmx]
        fit["pdmx_tunes"] = len(pdmx)
        fit["pdmx_spearman"] = round(float(spearmanr(pl, cs).statistic), 3)
        fit["pdmx_kendall_tau"] = round(float(kendalltau(pl, cs).statistic), 3)
        fit["pdmx_mean_level_by_complexity"] = {str(c): round(float(np.mean(pl[np.array(cs) == c])), 2) for c in sorted(set(cs))}
    out = {"weights": w, "thresholds": theta, "course_levels": start["course_levels"], "skills": SKILLS, "fit": fit}
    print(json.dumps(out, indent=2))
    if not a.dry_run:
        WEIGHTS.write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")
        print(f"wrote {WEIGHTS.relative_to(ROOT)}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
