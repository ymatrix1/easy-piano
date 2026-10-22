"""Easier variants of a tune, so beginner specs are not rare in training.

A Python cut of the level-variant ideas in core/src/arrange.rs, applied to a
phrase window at training time:
- right hand only (drop LH), or LH reduced to one note per bar
- rhythm on a coarser grid: keep notes starting on the grid, extend them to the
  next kept onset (re-split into single durations, ties where needed)
- range folded into one octave around the melody's median
- fingering dropped (most sources have none)
The spec is then computed from the variant, so it is always true.
"""

from __future__ import annotations

import random
from fractions import Fraction
from statistics import median

from .notation import Event, Pitch, dur_beats, format_hand, parse_hand

_DUR_QL = sorted(
    ((Fraction(dur_beats(d, 4)).limit_denominator(64), d) for d in ("1", "2.", "2", "4.", "4", "8.", "8")),
    reverse=True,
)


def _split(ql: Fraction, pitches: list[Pitch]) -> list[Event]:
    out = []
    for q, d in _DUR_QL:
        while ql >= q:
            out.append(Event(list(pitches), d))
            ql -= q
    if ql:
        out.append(Event(list(pitches), "16"))
    if pitches:
        for e in out[:-1]:
            e.tie = True
    return out


def coarsen(events: list[Event], grid: Fraction, bar_ql: Fraction) -> list[Event]:
    """Keep notes whose onset is on `grid` (quarters); each lasts to the next kept onset or bar end."""
    t, kept = Fraction(0), []
    for e in events:
        if t % grid == 0:
            kept.append((t, e))
        t += Fraction(dur_beats(e.dur, 4)).limit_denominator(64)
    out: list[Event] = []
    if not kept or kept[0][0] > 0:
        out += _split((kept[0][0] if kept else bar_ql), [])
    for i, (t0, e) in enumerate(kept):
        end = kept[i + 1][0] if i + 1 < len(kept) else bar_ql
        out += _split(end - t0, [] if e.is_rest else e.pitches[:1])
    return out


def _fold(p: Pitch, centre: int) -> Pitch:
    shift = 0
    while p.midi + shift > centre + 6:
        shift -= 12
    while p.midi + shift < centre - 6:
        shift += 12
    return Pitch(p.letter, p.acc, p.octave + shift // 12)


def simplify(song: dict, rng: random.Random) -> dict:
    """One random easier variant of a window ({time, key, bars, plan})."""
    num, den = (int(x) for x in song["time"].split("/"))
    bar_ql = Fraction(num * 4, den)
    grid = rng.choice([Fraction(1), Fraction(1, 2)]) if den == 4 else Fraction(3, 2)
    rh = [parse_hand(b.get("RH", "")) if b.get("RH") else [Event([], _DUR_QL[0][1])] for b in song["bars"]]
    line = [p.midi for bar in rh for e in bar for p in e.pitches]
    centre = int(median(line)) if line else 67
    bars = []
    keep_lh = rng.random() < 0.3 and any("LH" in b for b in song["bars"])
    for b, events in zip(song["bars"], rh):
        new = coarsen(events, grid, bar_ql)
        for e in new:
            e.pitches = [_fold(p, centre) for p in e.pitches]
        bar = {"RH": format_hand(new)}
        if keep_lh and b.get("LH"):
            lh = parse_hand(b["LH"])
            first = next((e for e in lh if not e.is_rest), None)
            bar["LH"] = format_hand(
                _split(bar_ql, [min(first.pitches, key=lambda p: p.midi)] if first else [])
            )
        bars.append(bar)
    _fix_ties(bars)
    return {**song, "bars": bars}


def _fix_ties(bars: list[dict]) -> None:
    """Folding can split a tie between octaves; drop ties that do not lead into the same pitch."""
    for hand in ("RH", "LH"):
        flat = [(i, e) for i, b in enumerate(bars) if hand in b for e in parse_hand(b[hand])]
        by_bar: dict[int, list[Event]] = {}
        for k, (i, e) in enumerate(flat):
            nxt = flat[k + 1][1] if k + 1 < len(flat) else None
            if e.tie and (nxt is None or nxt.pitches != e.pitches):
                e.tie = False
            by_bar.setdefault(i, []).append(e)
        for i, events in by_bar.items():
            bars[i][hand] = format_hand(events)
