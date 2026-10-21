"""Bar-level form plan derived from a tune (design choice 2, docs/specs/melody-model.md).

Per bar: section letter (A..H, same letter = same or near-same bar),
cadence (STABLE when the bar's last melody note is a tonic-triad degree,
else OPEN) and contour (UP / DOWN / FLAT from first to last melody pitch).
"""

from __future__ import annotations

from .notation import Event, parse_hand
from .tokenizer import SECTIONS, step

_TONIC_PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
FLAT_SEMITONES = 2  # |last - first| <= this is FLAT


def tonic_pc(key: str) -> tuple[int, bool]:
    minor = key.endswith("m")
    name = key[:-1] if minor else key
    pc = _TONIC_PC[name[0]] + {"#": 1, "b": -1}.get(name[1:], 0)
    return pc % 12, minor


def melody(bar: dict) -> list[Event]:
    """Melody line of a bar: RH, else LH; chords reduced to their top note."""
    hand = bar.get("RH") or bar.get("LH") or ""
    return parse_hand(hand)


def signature(events: list[Event]) -> tuple:
    """Rhythm plus interval pattern; transposition-invariant."""
    notes = [max(e.pitches, key=lambda p: p.midi).midi if e.pitches else None for e in events]
    first = next((n for n in notes if n is not None), 0)
    return tuple((e.dur, None if n is None else n - first) for e, n in zip(events, notes))


def similar(a: tuple, b: tuple) -> bool:
    if a == b:
        return True
    if len(a) != len(b) or [x[0] for x in a] != [x[0] for x in b]:
        return False
    same = sum(x == y for x, y in zip(a, b))
    return same * 2 >= len(a)


def plan(song: dict) -> list[tuple[str, str, str]]:
    pc, minor = tonic_pc(song["key"])
    triad = {pc, (pc + (3 if minor else 4)) % 12, (pc + 7) % 12}
    reps: list[tuple] = []  # signature of each section letter's first bar
    out = []
    for bar in song["bars"]:
        ev = melody(bar)
        sig = signature(ev)
        idx = next((i for i, r in enumerate(reps) if similar(sig, r)), None)
        if idx is None:
            reps.append(sig)
            idx = len(reps) - 1
        letter = SECTIONS[min(idx, len(SECTIONS) - 1)]
        pitches = [max(e.pitches, key=lambda p: p.midi).midi for e in ev if e.pitches]
        if not pitches:
            out.append((letter, "OPEN", "FLAT"))
            continue
        cad = "STABLE" if pitches[-1] % 12 in triad else "OPEN"
        d = pitches[-1] - pitches[0]
        con = "FLAT" if abs(d) <= FLAT_SEMITONES else ("UP" if d > 0 else "DOWN")
        out.append((letter, cad, con))
    return out


def encode_plan(labels: list[tuple[str, str, str]]):
    steps = [step("PLAN")]
    for sec, cad, con in labels:
        steps += [step(f"SEC_{sec}"), step(f"CAD_{cad}"), step(f"CON_{con}")]
    steps.append(step("PLAN_END"))
    return steps
