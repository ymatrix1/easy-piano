"""What a tune asks of the player: skill-spec patterns it satisfies and a 1-5 level.

Training puts both into the spec, so the model learns "a tune with a rest",
"a tune at level 2"; generation puts the node's own patterns and level there.
Pattern semantics follow docs/specs/skill-specs.md.
"""

from __future__ import annotations

import random
from collections import Counter
from fractions import Fraction

from .notation import Event, dur_beats, parse_hand

BLACK = {1, 3, 6, 8, 10}
INTERVAL_NUMBER = {0: 1, 1: 2, 2: 2, 3: 3, 4: 3, 5: 4, 6: 4, 7: 5, 8: 6, 9: 6, 10: 7, 11: 7}
LEVELS = (1, 2, 3, 4, 5)


def _hands(song: dict) -> dict[str, list[list[Event]]]:
    return {
        h: [parse_hand(b[h]) if h in b else [] for b in song["bars"]]
        for h in ("RH", "LH")
        if any(h in b for b in song["bars"])
    }


def _onsets(bar: list[Event]) -> list[tuple[Fraction, Event]]:
    t, out = Fraction(0), []
    for e in bar:
        out.append((t, e))
        t += Fraction(dur_beats(e.dur, 4)).limit_denominator(64)
    return out


def interval_number(semitones: int) -> int:
    return 8 if semitones >= 12 else INTERVAL_NUMBER[semitones]


def patterns_of(song: dict) -> list[dict]:
    """Every skill-spec pattern the tune satisfies (one value per key: the strongest)."""
    hands = _hands(song)
    events = [e for bars in hands.values() for bar in bars for e in bar]
    out: list[dict] = []
    if any(e.is_rest for e in events):
        out.append({"rest": True})
    if any(len(e.pitches) > 1 for e in events):
        out.append({"chord": True})
    if "RH" in hands and "LH" in hands:
        for rb, lb in zip(hands["RH"], hands["LH"]):
            r = {t for t, e in _onsets(rb) if not e.is_rest}
            left = {t for t, e in _onsets(lb) if not e.is_rest}
            if r & left:
                out.append({"hands_together": True})
                break
    for hand, bars in hands.items():
        line = [
            max(p.midi for p in e.pitches) if hand == "RH" else min(p.midi for p in e.pitches)
            for bar in bars
            for e in bar
            if not e.is_rest
        ]
        leaps = [abs(a - b) for a, b in zip(line, line[1:])]
        if leaps and max(leaps) >= 3:
            out.append({"interval_min": interval_number(max(leaps)), "hand": hand})
        durs = Counter(e.dur for bar in bars for e in bar if not e.is_rest)
        if durs:
            d = min(durs, key=lambda x: dur_beats(x, 4))  # the fastest note value is what the level teaches
            share = sum(any(e.dur == d for e in bar) for bar in bars) / max(1, len(bars))
            p = {"rhythm": d, "hand": hand}
            if share >= 0.25:
                p["min_bar_share"] = int(share * 4) / 4
            out.append(p)
    acc = sorted({p.letter + p.acc for e in events for p in e.pitches if p.acc})
    if acc:
        out.append({"accidental": acc[0]})
    return out


def pick_patterns(patterns: list[dict], rng: random.Random, max_n: int = 3) -> list[dict]:
    """A random subset, like a node's `required` list (often 0-2 patterns)."""
    n = rng.choice([0, 1, 1, 2, 2, 3])
    return rng.sample(patterns, min(n, len(patterns), max_n))


def level_of(song: dict) -> int:
    """1 (first lessons) .. 5 (advanced for this format), from range, rhythm, accidentals, hands, chords, density."""
    hands = _hands(song)
    events = [e for bars in hands.values() for bar in bars for e in bar]
    notes = [e for e in events if not e.is_rest]
    if not notes:
        return 1
    score = 0
    for bars in hands.values():
        ps = [p.midi for bar in bars for e in bar for p in e.pitches]
        if ps:
            span = max(ps) - min(ps)
            score = max(score, 0 if span <= 7 else 1 if span <= 12 else 2 if span <= 19 else 3)
    shortest = min(dur_beats(e.dur, 4) for e in notes)
    score += 0 if shortest >= 1 else 1 if shortest >= 0.5 else 2 if shortest >= 0.25 else 3
    black = {p.midi % 12 for e in notes for p in e.pitches} & BLACK
    score += 0 if not black else 1 if len(black) <= 2 else 2
    score += len(hands) == 2
    score += any(len(e.pitches) > 1 for e in notes)
    per_bar = len(notes) / max(1, len(song["bars"]) * len(hands))
    score += 0 if per_bar < 4 else 1 if per_bar < 8 else 2
    return 1 if score <= 1 else 2 if score <= 3 else 3 if score <= 6 else 4 if score <= 9 else 5
