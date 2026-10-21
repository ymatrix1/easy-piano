"""Training samples from dataset tunes (docs/specs/melody-model.md, "Left-to-right" and "Fill-in-the-middle").

make_sample(tune, rng) picks a phrase window, transposes it (spelled), builds the
spec (style tokens dropped at random), the bar plan for the window, and the bars,
left to right or as FIM. Returns (steps, loss_from): the loss covers steps from
loss_from on (the plan and bars after SPEC_END for left-to-right; the middle bars after FIM_MID for FIM, where the plan is given).
"""

from __future__ import annotations

import random

from . import tokenizer as tk
from .augment import transpose_song, windows
from .difficulty import level_of, patterns_of, pick_patterns
from .labels import encode_plan
from .notation import Unsupported
from .simplify import simplify
from .tokenizer import SECTIONS, SOURCES, Step

FIM_P = 0.25
STYLE_DROP_P = 0.2
MAX_FIM_BARS = 4
SIMPLIFY_P = 0.3  # share of samples that are an easier variant
LEVEL_DROP_P = 0.2
SOURCE_DROP_P = 0.5  # generation may omit SRC; base1 was trained without this dropout
SHIFTS = list(range(-6, 12))


def reletter(plan: list) -> list:
    """Section letters of a window, renamed in order of first appearance (A, B, ...)."""
    names: dict[str, str] = {}
    out = []
    for sec, cad, con in plan:
        if sec not in names:
            names[sec] = SECTIONS[min(len(names), len(SECTIONS) - 1)]
        out.append((names[sec], cad, con))
    return out


def _window(tune: dict, rng: random.Random) -> dict:
    a, b = rng.choice(windows(len(tune["bars"])))
    return {"time": tune["time"], "key": tune["key"], "bars": tune["bars"][a:b], "plan": reletter(tune["plan"][a:b])}


def _transpose(song: dict, rng: random.Random) -> dict:
    for shift in rng.sample(SHIFTS, len(SHIFTS)):
        try:
            out = transpose_song(song, shift)
            tk.encode_bars(out["bars"])  # every pitch must exist in the vocab
            return out
        except Unsupported:
            continue
    return song


def make_sample(tune: dict, rng: random.Random, ctx: int = 1024, fim_p: float = FIM_P,
                style_drop_p: float = STYLE_DROP_P, transpose: bool = True,
                simplify_p: float = SIMPLIFY_P) -> tuple[list[Step], int]:
    for _ in range(8):
        song = _window(tune, rng)
        if rng.random() < simplify_p:
            song = simplify(song, rng)
        if transpose:
            song = _transpose(song, rng)
        spec = tk.spec_from_song(song)
        spec.styles = [] if rng.random() < style_drop_p else list(tune.get("styles", []))
        spec.source = None if rng.random() < SOURCE_DROP_P else (tune["corpus"] if tune["corpus"] in SOURCES else "local")
        spec.level = None if rng.random() < LEVEL_DROP_P else level_of(song)
        spec.patterns = pick_patterns(patterns_of(song), rng)
        head = [tk.step("BOS")] + tk.encode_spec(spec)
        spec_len = len(head)  # left to right: the model writes the plan, then the bars
        head += encode_plan(song["plan"])
        n = len(song["bars"])
        if n >= 3 and rng.random() < fim_p:
            k = rng.randint(1, min(MAX_FIM_BARS, n - 2))
            i = rng.randint(1, n - 1 - k)
            pre, mid, suf = song["bars"][:i], song["bars"][i:i + k], song["bars"][i + k:]
            body = [tk.step("FIM_PRE")] + tk.encode_bars(pre) + [tk.step("FIM_SUF")] + tk.encode_bars(suf) + [tk.step("FIM_MID")]
            loss_from = len(head) + len(body)
            steps = head + body + tk.encode_bars(mid) + [tk.step("END")]
        else:
            loss_from = spec_len
            steps = head + tk.encode_bars(song["bars"]) + [tk.step("END")]
        if len(steps) <= ctx:
            return steps, loss_from
    raise Unsupported("no window fits the context")
