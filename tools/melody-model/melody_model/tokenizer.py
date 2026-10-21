"""Compound tokenizer: one step = (kind, pitch, dur, finger).

Sequence layout (docs/specs/melody-model.md):

    BOS SPEC <spec steps> SPEC_END [PLAN <plan steps> PLAN_END]
    BAR RH <events> [LH <events>] BAR ... END

A note is one step (NOTE, pitch, dur, finger). A chord is a NOTE step followed
by CHORD steps (pitch, finger; dur NONE) at the same onset. A rest is
(REST, -, dur, -). Fields that do not apply hold NONE (id 0).
"""

from __future__ import annotations

import json
from dataclasses import dataclass

from .notation import ACCIDENTALS, DURATIONS, LETTERS, OCTAVES, Event, Pitch, Unsupported, format_hand, parse_hand

NONE = "<none>"

TIME_SIGS = ("2/4", "3/4", "4/4", "3/8", "6/8", "9/8", "12/8", "2/2")
_TONICS = ("C", "G", "D", "A", "E", "B", "F#", "C#", "F", "Bb", "Eb", "Ab", "Db", "Gb", "Cb")
KEYS = tuple(_TONICS) + tuple(t + "m" for t in ("A", "E", "B", "F#", "C#", "G#", "D#", "A#", "D", "G", "C", "F", "Bb", "Eb", "Ab"))
MAX_BARS = 64
COURSES = ("none", "piano-basics", "essentials-1", "essentials-2", "essentials-3")
HANDS = ("RH", "LH", "BOTH")
STYLES = ("classical", "folk", "religious", "world", "children", "pop", "rock", "soundtrack", "game", "jazz", "electronic", "chinese")
SOURCES = ("own", "nottingham", "mutopia", "pdmx", "local")
# Required-pattern keys of docs/specs/skill-specs.md (content/skill-specs/*.json); a test checks every
# pattern there encodes. Values ride in the pitch/dur fields or in the kind itself.
PATTERN_KEYS = ("rhythm", "interval_min", "accidental", "pitch", "hand", "min_bar_share", "rest", "chord", "hands_together")
INTERVAL_NUMBERS = range(2, 9)  # second .. octave
SHARES = (25, 50, 75, 100)  # min_bar_share, rounded up to a quarter
SECTIONS = tuple("ABCDEFGH")

KINDS = (
    (NONE, "PAD", "BOS", "END", "BAR", "RH", "LH", "NOTE", "CHORD", "REST", "TIE")
    + ("SPEC", "SPEC_END", "RANGE_LO", "RANGE_HI", "DUR_ALLOW")
    + tuple(f"TIME_{t}" for t in TIME_SIGS)
    + tuple(f"KEY_{k}" for k in KEYS)
    + tuple(f"BARS_{n}" for n in range(1, MAX_BARS + 1))
    + tuple(f"COURSE_{c}" for c in COURSES)
    + tuple(f"HANDS_{h}" for h in HANDS)
    + tuple(f"STYLE_{x}" for x in STYLES)
    + tuple(f"SRC_{x}" for x in SOURCES)
    + tuple(f"LEVEL_{n}" for n in range(1, 6))
    + ("PAT", "PAT_rhythm", "PAT_accidental", "PAT_pitch", "PAT_hand_RH", "PAT_hand_LH", "PAT_rest", "PAT_chord", "PAT_hands_together")
    + tuple(f"PAT_interval_min_{n}" for n in INTERVAL_NUMBERS)
    + tuple(f"PAT_share_{x}" for x in SHARES)
    + ("PLAN", "PLAN_END", "CAD_STABLE", "CAD_OPEN", "CON_UP", "CON_DOWN", "CON_FLAT")
    + tuple(f"SEC_{s}" for s in SECTIONS)
    + ("FIM_PRE", "FIM_SUF", "FIM_MID")
)
PITCHES = (NONE,) + tuple(f"{l}{a}{o}" for o in OCTAVES for l in LETTERS for a in ACCIDENTALS)
DURS = (NONE,) + DURATIONS
FINGERS = (NONE, "1", "2", "3", "4", "5")

FIELDS = {"kind": KINDS, "pitch": PITCHES, "dur": DURS, "finger": FINGERS}
_IDS = {name: {v: i for i, v in enumerate(values)} for name, values in FIELDS.items()}

Step = tuple[int, int, int, int]


def step(kind: str, pitch: str = NONE, dur: str = NONE, finger: str = NONE) -> Step:
    try:
        return (_IDS["kind"][kind], _IDS["pitch"][pitch], _IDS["dur"][dur], _IDS["finger"][finger])
    except KeyError as e:
        raise Unsupported(f"no vocab entry for {e.args[0]!r}") from None


def show(s: Step) -> str:
    """Readable form, for tests and debugging."""
    parts = [FIELDS[n][i] for n, i in zip(FIELDS, s)]
    return " ".join(p for p in parts if p != NONE)


@dataclass
class Spec:
    time: str
    key: str
    bars: int
    range_lo: str
    range_hi: str
    durs: list[str]
    hands: str
    course: str = "none"
    patterns: list[dict] | None = None  # skill-spec `required` patterns
    styles: list[str] | None = None  # STYLES; dropped at random in training
    source: str | None = None  # SOURCES; omitted at generation
    level: int | None = None  # 1-5 (difficulty.level_of)


def spec_from_song(song: dict) -> Spec:
    """Spec labels that a tune itself satisfies (training-time conditioning)."""
    pitches: list[Pitch] = []
    durs: set[str] = set()
    has_lh = False
    has_rh = False
    for bar in song["bars"]:
        for hand in ("RH", "LH"):
            if hand not in bar:
                continue
            events = parse_hand(bar[hand])
            if any(not e.is_rest for e in events):
                has_rh |= hand == "RH"
                has_lh |= hand == "LH"
            for e in events:
                pitches.extend(e.pitches)
                durs.add(e.dur)
    if not pitches:
        raise Unsupported("song has no notes")
    lo = min(pitches, key=lambda p: p.midi)
    hi = max(pitches, key=lambda p: p.midi)
    hands = "BOTH" if has_rh and has_lh else ("LH" if has_lh else "RH")
    return Spec(song["time"], song["key"], len(song["bars"]), lo.name, hi.name,
                sorted(durs, key=DURATIONS.index), hands)


def encode_spec(spec: Spec) -> list[Step]:
    if spec.bars > MAX_BARS:
        raise Unsupported(f"{spec.bars} bars > {MAX_BARS}")
    out = [step("SPEC")]
    out += [step(f"STYLE_{x}") for x in sorted(spec.styles or [])]
    if spec.source:
        out.append(step(f"SRC_{spec.source}"))
    if spec.level:
        out.append(step(f"LEVEL_{spec.level}"))
    out += [step(f"COURSE_{spec.course}"), step(f"TIME_{spec.time}"),
           step(f"KEY_{spec.key}"), step(f"BARS_{spec.bars}"),
           step("RANGE_LO", pitch=spec.range_lo), step("RANGE_HI", pitch=spec.range_hi)]
    out += [step("DUR_ALLOW", dur=d) for d in spec.durs]
    out.append(step(f"HANDS_{spec.hands}"))
    for pattern in spec.patterns or []:
        out += encode_pattern(pattern)
    out.append(step("SPEC_END"))
    return out


def encode_pattern(pattern: dict) -> list[Step]:
    """One skill-spec `required` pattern as PAT followed by one step per key."""
    unknown = set(pattern) - set(PATTERN_KEYS)
    if unknown:
        raise Unsupported(f"pattern keys {sorted(unknown)}")
    out = [step("PAT")]
    for k in PATTERN_KEYS:  # fixed order
        if k not in pattern:
            continue
        v = pattern[k]
        if k == "rhythm":
            out.append(step("PAT_rhythm", dur=v))
        elif k == "interval_min":
            out.append(step(f"PAT_interval_min_{v}"))
        elif k == "accidental":
            out.append(step("PAT_accidental", pitch=f"{v}4"))  # pitch class, carried at octave 4
        elif k == "pitch":
            out.append(step("PAT_pitch", pitch=v))
        elif k == "hand":
            out.append(step(f"PAT_hand_{v}"))
        elif k == "min_bar_share":
            share = next(x for x in SHARES if x >= round(float(v) * 100))
            out.append(step(f"PAT_share_{share}"))
        elif v is True:
            out.append(step(f"PAT_{k}"))
        else:
            raise Unsupported(f"pattern {k}={v!r}")
    return out


def encode_events(events: list[Event]) -> list[Step]:
    out = []
    for e in events:
        if e.is_rest:
            out.append(step("REST", dur=e.dur))
            continue
        for i, p in enumerate(e.pitches):
            f = str(e.fingers[i]) if e.fingers else NONE
            out.append(step("NOTE" if i == 0 else "CHORD", pitch=p.name, dur=e.dur if i == 0 else NONE, finger=f))
        if e.tie:
            out.append(step("TIE"))
    return out


def encode_bars(bars: list[dict]) -> list[Step]:
    out = []
    for bar in bars:
        out.append(step("BAR"))
        for hand in ("RH", "LH"):
            if hand in bar:
                out.append(step(hand))
                out += encode_events(parse_hand(bar[hand]))
    return out


def encode_song(song: dict, spec: Spec | None = None) -> list[Step]:
    """Song JSON (RH/LH only; backing parts are ignored) to steps."""
    spec = spec or spec_from_song(song)
    return [step("BOS")] + encode_spec(spec) + encode_bars(song["bars"]) + [step("END")]


class InvalidSequence(ValueError):
    """Steps that do not form a valid song (model output is decoded through this)."""


_PREFIX_KINDS = ("PAD", "BOS", "PAT", "SPEC", "SPEC_END", "RANGE_LO", "RANGE_HI", "DUR_ALLOW", "PLAN", "PLAN_END",
                 "CAD_STABLE", "CAD_OPEN", "CON_UP", "CON_DOWN", "CON_FLAT", "FIM_PRE", "FIM_SUF", "FIM_MID")
_PREFIX_GROUPS = ("COURSE_", "BARS_", "HANDS_", "PAT_", "SEC_", "STYLE_", "SRC_", "LEVEL_")


def decode(steps: list[Step]) -> dict:
    """Steps to {"time", "key", "bars"}; inverse of encode_song for RH/LH.

    Raises InvalidSequence on anything encode_song cannot produce: out-of-range
    ids, notes outside a hand, missing or extra fields, a CHORD without a NOTE,
    a hand twice in a bar, no time or key, no bars. Bar lengths are not checked
    here (the rubric and lint do that).
    """
    kinds = FIELDS["kind"]
    time = key = None
    bars: list[dict] = []
    events: list[Event] | None = None
    hand = None

    def bad(msg):
        raise InvalidSequence(msg)

    def flush():
        if events is not None:
            if not events:
                bad(f"empty {hand} in bar {len(bars)}")
            bars[-1][hand] = format_hand(events)

    for i, s in enumerate(steps):
        if len(s) != 4 or not all(0 <= v < len(FIELDS[f]) for v, f in zip(s, FIELDS)):
            bad(f"step {i}: ids out of range {s}")
        kind = kinds[s[0]]
        pitch, dur, finger = PITCHES[s[1]], DURS[s[2]], FINGERS[s[3]]
        if kind == NONE:
            bad(f"step {i}: no kind")
        if kind.startswith("TIME_"):
            time = kind[5:]
        elif kind.startswith("KEY_"):
            key = kind[4:]
        elif kind == "BAR":
            flush()
            events, hand = None, None
            bars.append({})
        elif kind in ("RH", "LH"):
            if not bars:
                bad(f"step {i}: {kind} before BAR")
            if kind in bars[-1] or kind == hand:
                bad(f"step {i}: {kind} twice in bar {len(bars)}")
            flush()
            events, hand = [], kind
        elif kind in ("NOTE", "REST", "CHORD"):
            if events is None:
                bad(f"step {i}: {kind} outside a hand")
            if kind == "NOTE" and (pitch == NONE or dur == NONE):
                bad(f"step {i}: NOTE needs pitch and dur")
            if kind == "REST" and (dur == NONE or pitch != NONE or finger != NONE):
                bad(f"step {i}: REST takes only dur")
            if kind == "CHORD":
                if pitch == NONE or dur != NONE:
                    bad(f"step {i}: CHORD takes pitch (and finger), no dur")
                if not events or events[-1].is_rest:
                    bad(f"step {i}: CHORD without a preceding NOTE")
                prev = events[-1]
                if bool(prev.fingers) != (finger != NONE):
                    bad(f"step {i}: fingering on some chord notes only")
                prev.pitches.append(_pitch(pitch))
                if finger != NONE:
                    prev.fingers.append(int(finger))
                continue
            p = [] if kind == "REST" else [_pitch(pitch)]
            f = [int(finger)] if finger != NONE else []
            events.append(Event(p, dur, f))
        elif kind == "TIE":
            if events is None or not events or events[-1].is_rest or events[-1].tie or (pitch, dur, finger) != (NONE, NONE, NONE):
                bad(f"step {i}: TIE must follow a note and carry no fields")
            events[-1].tie = True
        elif kind == "END":
            break
        elif kind in _PREFIX_KINDS or kind.startswith(_PREFIX_GROUPS):
            if bars:
                bad(f"step {i}: {kind} after the first BAR")
        else:
            bad(f"step {i}: unexpected {kind}")
    flush()
    if time is None or key is None:
        bad("no TIME or KEY")
    if not bars or any(not b for b in bars):
        bad("no bars, or an empty bar")
    return {"time": time, "key": key, "bars": bars}


def _pitch(name: str) -> Pitch:
    from .notation import parse_pitch
    return parse_pitch(name)


def vocab_json() -> str:
    """Field vocabularies, for the browser decoder."""
    return json.dumps({n: list(v) for n, v in FIELDS.items()}, indent=1) + "\n"
