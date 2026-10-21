"""Spelled transposition and phrase windows, applied at training time."""

from __future__ import annotations

from .notation import LETTERS, Pitch, Unsupported, format_hand, parse_hand
from .tokenizer import KEYS

_SEMI = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
_ACC = {-1: "b", 0: "", 1: "#"}


def transpose_pitch(p: Pitch, steps: int, semis: int) -> Pitch:
    li = LETTERS.index(p.letter) + steps
    letter = LETTERS[li % 7]
    octave = p.octave + li // 7
    target = p.midi + semis
    natural = 12 * (octave + 1) + _SEMI[letter]
    acc = _ACC.get(target - natural)
    if acc is None or not 0 <= octave <= 8 or not 21 <= target <= 108:
        raise Unsupported(f"cannot spell {p.name} +{steps}/{semis}")
    return Pitch(letter, acc, octave)


def transpose_key(key: str, steps: int, semis: int) -> str:
    minor = key.endswith("m")
    tonic = key[:-1] if minor else key
    p = transpose_pitch(Pitch(tonic[0], tonic[1:], 4), steps, semis)
    name = p.letter + p.acc + ("m" if minor else "")
    if name not in KEYS:
        raise Unsupported(f"key {name}")
    return name


# (letter steps, semitones) for each chromatic shift, using the common spelling
INTERVALS = {
    0: (0, 0),
    1: (1, 1),
    2: (1, 2),
    3: (2, 3),
    4: (2, 4),
    5: (3, 5),
    6: (4, 6),
    7: (4, 7),
    8: (5, 8),
    9: (5, 9),
    10: (6, 10),
    11: (6, 11),
    -1: (-1, -1),
    -2: (-1, -2),
    -3: (-2, -3),
    -4: (-2, -4),
    -5: (-3, -5),
    -6: (-3, -6),
}


def transpose_song(song: dict, shift: int) -> dict:
    """Shift by `shift` semitones (-6..11); raises Unsupported when spelling fails."""
    steps, semis = INTERVALS[shift]
    bars = []
    for bar in song["bars"]:
        nb = {}
        for hand in ("RH", "LH"):
            if hand in bar:
                events = parse_hand(bar[hand])
                for e in events:
                    e.pitches = [transpose_pitch(p, steps, semis) for p in e.pitches]
                nb[hand] = format_hand(events)
        bars.append(nb)
    return {**song, "key": transpose_key(song["key"], steps, semis), "bars": bars}


def windows(n_bars: int, sizes=(4, 8, 16), step: int = 4) -> list[tuple[int, int]]:
    """Phrase-aligned [start, end) windows, plus the whole tune."""
    out = {(0, n_bars)}
    for size in sizes:
        for start in range(0, n_bars - size + 1, step):
            out.add((start, start + size))
    return sorted(out)
