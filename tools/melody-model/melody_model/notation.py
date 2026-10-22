"""Parse and format hand strings of the song note grammar (docs/specs/content-format.md).

Covers the subset the model handles: spelled pitches with '', '#' or 'b',
rests, chords, denominator durations with dots, per-pitch fingering.
The `{tie}` directive (zero length, after a note: tied into the next note) is
supported; `{chord:"X"}` symbols are display-only and dropped; other directives, annotations, 'n' naturals and n/d durations raise Unsupported.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

LETTERS = "CDEFGAB"
ACCIDENTALS = ("", "#", "b")
OCTAVES = range(0, 9)
# Allowed durations, shortest-first is not required; order fixes vocab ids.
DURATIONS = ("1", "1.", "2", "2.", "2..", "4", "4.", "4..", "8", "8.", "16", "16.", "32")

_STEP_SEMITONES = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
_PITCH_RE = re.compile(r"([A-G])(#|b)?(\d)")
_CHORD_SYMBOL_RE = re.compile(r'^\{chord:"[^"\s]+"\}$')
_TOKEN_RE = re.compile(r"^(?P<pitches>(?:[A-G](?:#|b)?\d)+|r):(?P<dur>\d+\.*)(?:@(?P<fingers>[1-5]+))?$")


class Unsupported(ValueError):
    """Input uses notation the model does not cover."""


@dataclass(frozen=True)
class Pitch:
    letter: str
    acc: str
    octave: int

    @property
    def name(self) -> str:
        return f"{self.letter}{self.acc}{self.octave}"

    @property
    def midi(self) -> int:
        alter = {"": 0, "#": 1, "b": -1}[self.acc]
        return 12 * (self.octave + 1) + _STEP_SEMITONES[self.letter] + alter


@dataclass
class Event:
    """One note, chord or rest."""

    pitches: list[Pitch]  # empty = rest
    dur: str
    fingers: list[int] = field(default_factory=list)  # empty = no fingering
    tie: bool = False  # tied into the next note (written as a following `{tie}` token)

    @property
    def is_rest(self) -> bool:
        return not self.pitches


def dur_beats(dur: str, denom: int) -> float:
    """Length in beats of the time signature's denominator."""
    base = int(dur.rstrip("."))
    dots = len(dur) - len(dur.rstrip("."))
    length = 1.0 / base
    add = length
    for _ in range(dots):
        add /= 2
        length += add
    return length * denom


def parse_pitch(text: str) -> Pitch:
    m = _PITCH_RE.fullmatch(text)
    if not m:
        raise Unsupported(f"pitch {text!r}")
    return Pitch(m.group(1), m.group(2) or "", int(m.group(3)))


def parse_hand(text: str) -> list[Event]:
    events = []
    for tok in text.split():
        if _CHORD_SYMBOL_RE.match(tok):
            continue  # display-only label; no notes
        if tok == "{tie}":
            if not events or events[-1].is_rest or events[-1].tie:
                raise Unsupported("{tie} must follow a note")
            events[-1].tie = True
            continue
        m = _TOKEN_RE.match(tok)
        if not m:
            raise Unsupported(f"token {tok!r}")
        dur = m.group("dur")
        if dur not in DURATIONS:
            raise Unsupported(f"duration {dur!r}")
        raw = m.group("pitches")
        pitches = [] if raw == "r" else [parse_pitch(p.group(0)) for p in _PITCH_RE.finditer(raw)]
        fingers = [int(c) for c in m.group("fingers") or ""]
        if fingers and len(fingers) != len(pitches):
            raise Unsupported(f"finger count in {tok!r}")
        events.append(Event(pitches, dur, fingers))
    return events


def format_hand(events: list[Event]) -> str:
    out = []
    for e in events:
        head = "r" if e.is_rest else "".join(p.name for p in e.pitches)
        fing = "@" + "".join(str(f) for f in e.fingers) if e.fingers else ""
        out.append(f"{head}:{e.dur}{fing}")
        if e.tie:
            out.append("{tie}")
    return " ".join(out)
