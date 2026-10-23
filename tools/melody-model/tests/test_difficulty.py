import json
import random
from pathlib import Path

from melody_model import tokenizer as tk
from melody_model.difficulty import level_of, patterns_of, pick_patterns
from melody_model.labels import plan
from melody_model.notation import Unsupported, parse_hand
from melody_model.samples import make_sample
from melody_model.simplify import coarsen, simplify

ROOT = Path(__file__).resolve().parents[3]


def song(name):
    s = json.loads((ROOT / "content" / "songs" / f"{name}.json").read_text(encoding="utf-8"))
    t = {
        "corpus": "own",
        "time": s["time"],
        "key": s["key"],
        "styles": [],
        "bars": [{h: b[h] for h in ("RH", "LH") if h in b} for b in s["bars"]],
    }
    t["plan"] = plan(t)
    return t


def test_levels_order_course_songs():
    assert level_of(song("cde-drill")) == 1
    assert level_of(song("minuet-in-g")) >= 3
    assert level_of(song("cde-drill")) < level_of(song("minuet-in-g"))


def test_patterns_found():
    p = patterns_of(song("e1-rest-drill"))
    assert {"rest": True} in p
    chord = patterns_of(song("e1-lh-chord-drill"))
    assert {"chord": True} in chord and {"hands_together": True} in chord


def test_every_found_pattern_encodes():
    for f in (ROOT / "content" / "songs").glob("*.json"):
        try:
            tk.encode_song(song(f.stem))
        except Unsupported:
            continue  # outside the model's vocabulary (triplets, 6/4, > 64 bars)
        for p in patterns_of(song(f.stem)):
            tk.encode_pattern(p)


def test_pick_patterns_is_a_subset():
    p = patterns_of(song("minuet-in-g"))
    for s in range(20):
        sub = pick_patterns(p, random.Random(s))
        assert len(sub) <= 3 and all(x in p for x in sub)


def test_coarsen_keeps_bar_length():
    events = parse_hand("C4:8 D4:8 E4:16 F4:16 G4:8 A4:4 B4:4")
    out = coarsen(events, __import__("fractions").Fraction(1), __import__("fractions").Fraction(4))
    assert [e.dur for e in out] == ["4", "4", "4", "4"] and out[0].pitches[0].name == "C4"


def test_simplified_variant_is_easier_and_valid():
    t = song("minuet-in-g")
    t = {**t, "bars": t["bars"][:8], "plan": t["plan"][:8]}
    levels = [level_of(simplify(t, random.Random(s))) for s in range(10)]
    assert min(levels) < level_of(t)
    for s in range(10):
        v = simplify(t, random.Random(s))
        tk.encode_bars(v["bars"])  # parses and tokenizes
        assert all(b["RH"] for b in v["bars"])


def test_sample_carries_level_and_patterns():
    t = song("e1-rest-drill")
    seen_level = seen_pat = False
    for s in range(40):
        k = [tk.FIELDS["kind"][x[0]] for x in make_sample(t, random.Random(s))[0]]
        seen_level |= any(x.startswith("LEVEL_") for x in k)
        seen_pat |= "PAT" in k
    assert seen_level and seen_pat
