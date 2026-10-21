"""Convert MusicXML, ABC and MIDI (LilyPond via Mutopia's MIDI) to song JSON bars.

Output is {"time", "key", "bars": [{"RH": ..., "LH": ...}], "title", "composer"}:
the RH/LH subset of docs/specs/content-format.md. Tunes the format cannot hold
raise Unsupported (counted and skipped by the dataset builder):

- more than two parts (unless melody_only), hands with different bar counts
- meter changes (shorter bars before repeats excepted), key changes including
  same-signature mode changes (C -> Am), ambiguous keys
- tuplets and durations outside DURATIONS, double accidentals
- ties across a barline, or tied notes whose sum is not one duration
  (the format has no tie; a re-attack would change the music)
- parser failures

Hands: two parts are assigned by mean pitch (higher = RH); one part is LH
when it has a bass clef or sits below G3 on average. In multi-voice bars the
voice with the highest mean pitch is read. Chord pitches are written low to
high; chord fingering is kept only when stored per note (music21 loses the
note order of chord-level fingering, so that is dropped).

LilyPond: there is no .ly parser. Mutopia ships a MIDI rendered by LilyPond from
the same source under the same licence, read with quantizePost (pitch spelling
re-inferred, fingering lost).
"""

from __future__ import annotations

from fractions import Fraction
from pathlib import Path
from statistics import mean

import music21 as m21

from . import tokenizer as tk
from .notation import DURATIONS, Event, Pitch, Unsupported, dur_beats, format_hand

# quarterLength -> duration string
_QL_TO_DUR = {Fraction(dur_beats(d, 4)).limit_denominator(64): d for d in DURATIONS}
MIN_KEY_CONFIDENCE = 0.6  # music21 key-analysis correlation needed when the file states no mode
LH_MEAN_BELOW = 55  # G3


def convert_file(path: str | Path) -> list[dict]:
    """All tunes in a file (ABC files can hold many); raises on the first unsupported tune."""
    songs, errors = convert_file_lenient(path)
    if errors:
        raise Unsupported(errors[0])
    return songs


def convert_file_lenient(path: str | Path) -> tuple[list[dict], list[str]]:
    """Like convert_file but collects per-tune errors instead of raising."""
    path = Path(path)
    try:
        parsed = m21.converter.parse(str(path), forceSource=True, quantizePost=path.suffix.lower() in (".mid", ".midi"))
    except Exception as e:  # music21 raises many types on malformed input
        return [], [f"parse error: {type(e).__name__}"]
    scores = list(parsed.scores) if isinstance(parsed, m21.stream.Opus) else [parsed]
    songs, errors = [], []
    for s in scores:
        try:
            songs.append(convert_score(s))
        except Unsupported as e:
            errors.append(str(e))
        except Exception as e:
            errors.append(f"parse error: {type(e).__name__}")
    return songs, errors


def convert_score(score: m21.stream.Score, melody_only: bool = False) -> dict:
    """melody_only: read only the first part, as RH (voice + piano scores, MIDI)."""
    parts = list(score.parts)
    if not parts:
        raise Unsupported("no parts")
    if melody_only:
        parts = parts[:1]
    elif len(parts) > 2:
        raise Unsupported(f"{len(parts)} parts")
    time = _time_sig(score)
    bar_ql = Fraction(m21.meter.TimeSignature(time).barDuration.quarterLength).limit_denominator(64)
    hands = _assign_hands(parts, melody_only)
    per_hand = {h: _hand_bars(p, bar_ql) for h, p in hands.items()}
    counts = {len(b) for b in per_hand.values()}
    if len(counts) != 1:
        raise Unsupported("hands have different bar counts")
    bars = [{h: format_hand(per_hand[h][i]) for h in ("RH", "LH") if h in per_hand} for i in range(counts.pop())]
    md = score.metadata
    return {
        "title": (md.title if md else None) or "",
        "composer": (md.composer if md else None) or "",
        "time": time,
        "key": _key_name(score),
        "bars": bars,
    }


def _mean_pitch(part) -> float:
    ps = [p.midi for n in part.recurse().notes for p in n.pitches]
    return mean(ps) if ps else 60.0


def _assign_hands(parts, melody_only: bool) -> dict:
    if len(parts) == 2:
        hi, lo = sorted(parts, key=_mean_pitch, reverse=True)
        return {"RH": hi, "LH": lo}
    part = parts[0]
    if melody_only:
        return {"RH": part}
    clef = part.recurse().getElementsByClass(m21.clef.Clef).first()
    bass = isinstance(clef, m21.clef.BassClef) or _mean_pitch(part) < LH_MEAN_BELOW
    return {"LH" if bass else "RH": part}


def _time_sig(score) -> str:
    # ABC headers can stack M: fields; the last one in a measure wins
    per_measure = {}
    for ts in score.parts[0].recurse().getElementsByClass(m21.meter.TimeSignature):
        per_measure[ts.measureNumber] = ts
    if not per_measure:
        raise Unsupported("no time signature")
    main = per_measure[min(per_measure)]
    for ts in per_measure.values():
        # a shorter bar (e.g. 3/8 or 2/4 before a repeat in 6/8) is a short bar, not a meter change
        if ts.barDuration.quarterLength >= main.barDuration.quarterLength and ts.ratioString != main.ratioString:
            raise Unsupported(f"time signatures {sorted({t.ratioString for t in per_measure.values()})}")
    t = main.ratioString
    if t not in tk.TIME_SIGS:
        raise Unsupported(f"time {t}")
    return t


def _key_name(score) -> str:
    sigs = list(score.parts[0].recurse().getElementsByClass(m21.key.KeySignature))
    stated = {(k.sharps, k.mode if isinstance(k, m21.key.Key) else None) for k in sigs}
    if len(stated) > 1:
        raise Unsupported("key changes")
    if sigs and isinstance(sigs[0], m21.key.Key):
        k = sigs[0]
    else:
        analyzed = score.analyze("key")
        if analyzed.correlationCoefficient < MIN_KEY_CONFIDENCE:
            raise Unsupported("ambiguous key")
        sharps = sigs[0].sharps if sigs else analyzed.sharps
        mode = analyzed.mode if analyzed.mode in ("major", "minor") else "major"
        k = m21.key.KeySignature(sharps).asKey(mode)
    tonic = k.tonic.name.replace("-", "b")
    name = tonic + ("m" if k.mode == "minor" else "")
    if name not in tk.KEYS:
        raise Unsupported(f"key {name}")
    return name


def _top_voice(m):
    if not m.voices:
        return m
    return max(m.voices, key=lambda v: mean([p.midi for n in v.notes for p in n.pitches] or [-1]))


def _hand_bars(part, bar_ql: Fraction) -> list[list[Event]]:
    measures = list(part.getElementsByClass(m21.stream.Measure))
    if not measures:
        measures = list(part.makeMeasures().getElementsByClass(m21.stream.Measure))
    raw: list[tuple[list[Event], Fraction]] = []
    for n, m in enumerate(measures):
        events: list[Event] = []
        pad_left = Fraction(m.paddingLeft).limit_denominator(64)
        if pad_left:
            events += _rests(pad_left)
        events += _bar_events(_top_voice(m), n + 1)
        raw.append((events, sum((Fraction(dur_beats(e.dur, 4)).limit_denominator(64) for e in events), Fraction(0))))
    bars: list[list[Event]] = []
    i = 0
    while i < len(raw):
        events, total = raw[i]
        if total > bar_ql:
            raise Unsupported(f"bar {i + 1} lasts {total} quarters, expected {bar_ql}")
        if total < bar_ql:
            # strain end + next strain's pickup written as two short measures: join them
            j, acc, merged = i, total, list(events)
            while acc < bar_ql and j + 1 < len(raw) and raw[j + 1][1] < bar_ql:
                j += 1
                acc += raw[j][1]
                merged += raw[j][0]
            if acc == bar_ql and j > i:
                bars.append(merged)
                i = j + 1
                continue
            if i == 0:
                events = _rests(bar_ql - total) + events  # opening pickup
            elif i == len(raw) - 1 or _at_section_end(measures[i], measures, i):
                events = events + _rests(bar_ql - total)
            else:
                raise Unsupported(f"bar {i + 1} lasts {total} quarters, expected {bar_ql}")
        bars.append(events)
        i += 1
    return bars


def _bar_events(voice, bar_no: int) -> list[Event]:
    """Notes and rests of one bar; tie chains inside the bar are merged into one note."""
    events: list[Event] = []
    tied = False  # previous element starts or continues a tie
    pending_ql = Fraction(0)
    for el in voice.notesAndRests:
        if el.duration.isGrace or isinstance(el, m21.harmony.ChordSymbol):
            continue
        tie = el.tie.type if el.tie is not None and not el.isRest else None
        ql = Fraction(el.duration.quarterLength).limit_denominator(64)
        if tie in ("stop", "continue") and not tied:
            raise Unsupported(f"tie across barline (bar {bar_no})")
        if tied:
            if tie not in ("stop", "continue"):
                raise Unsupported(f"broken tie (bar {bar_no})")
            prev = events[-1]
            if [p.midi for p in prev.pitches] != sorted(p.midi for p in el.pitches):
                raise Unsupported(f"tie between different pitches (bar {bar_no})")
            pending_ql += ql
            d = _QL_TO_DUR.get(pending_ql)
            if d is None and tie == "stop":
                raise Unsupported(f"tie sum {pending_ql} quarters (bar {bar_no})")
            prev.dur = d
        else:
            events.append(_event(el, allow_any_duration=tie == "start"))
            pending_ql = ql
        tied = tie in ("start", "continue")
    if tied:
        raise Unsupported(f"tie across barline (bar {bar_no})")
    return events


def _at_section_end(m, measures, n) -> bool:
    """Short bars before a repeat or double bar (pickup tunes) are padded too."""
    right = m.rightBarline
    nxt = measures[n + 1].leftBarline if n + 1 < len(measures) else None
    ends = isinstance(right, m21.bar.Repeat) or (right is not None and right.type in ("final", "light-heavy", "double", "heavy-light"))
    return ends or isinstance(nxt, m21.bar.Repeat)


def _event(el, allow_any_duration: bool = False) -> Event:
    """allow_any_duration: first note of a tie chain; the chain's sum is checked instead."""
    ql = Fraction(el.duration.quarterLength).limit_denominator(64)
    dur = _QL_TO_DUR.get(ql)
    if dur is None and not allow_any_duration:
        raise Unsupported(f"duration {ql} quarters")
    if el.isRest:
        return Event([], dur)
    if not el.isChord:
        f = _finger_of(el)
        return Event([_pitch(el.pitch)], dur, [f] if f else [])
    pairs = sorted(zip(el.notes, _chord_fingers(el)), key=lambda nf: nf[0].pitch.midi)
    fingers = [f for _, f in pairs]
    return Event([_pitch(n.pitch) for n, _ in pairs], dur, fingers if all(fingers) else [])


def _pitch(p: m21.pitch.Pitch) -> Pitch:
    alter = p.accidental.alter if p.accidental else 0
    acc = {0: "", 1: "#", -1: "b"}.get(int(alter)) if alter == int(alter) else None
    if acc is None:
        raise Unsupported(f"accidental {p.nameWithOctave}")
    if not 0 <= p.octave <= 8:
        raise Unsupported(f"octave {p.nameWithOctave}")
    return Pitch(p.step, acc, p.octave)


def _finger_of(obj) -> int | None:
    fs = [a.fingerNumber for a in obj.articulations if isinstance(a, m21.articulations.Fingering)]
    fs = [f for f in fs if isinstance(f, int) and 1 <= f <= 5]
    return fs[0] if len(fs) == 1 else None


def _chord_fingers(el) -> list[int | None]:
    """Finger per chord note, or Nones.

    Only fingering stored on the note objects is trusted. music21 sorts chord notes
    on import but keeps chord-level fingering in written order, so that list cannot
    be matched to pitches: it is dropped (the arranger re-fingers chords anyway).
    """
    return [_finger_of(n) for n in el.notes]


def _rests(ql: Fraction) -> list[Event]:
    """Fill a gap with the fewest rests, longest first."""
    out = []
    for q, d in sorted(_QL_TO_DUR.items(), reverse=True):
        while ql >= q:
            out.append(Event([], d))
            ql -= q
    if ql:
        raise Unsupported(f"gap of {ql} quarters")
    return out


def song_to_score(song: dict) -> m21.stream.Score:
    """Song JSON (RH/LH) to a music21 score; used by tests and listening exports."""
    from .notation import parse_hand

    score = m21.stream.Score()
    for hand, clef in (("RH", m21.clef.TrebleClef()), ("LH", m21.clef.BassClef())):
        if not any(hand in b for b in song["bars"]):
            continue
        part = m21.stream.Part(id=hand)
        for i, bar in enumerate(song["bars"]):
            m = m21.stream.Measure(number=i + 1)
            if i == 0:
                m.append([clef, m21.meter.TimeSignature(song["time"]), _m21_key(song["key"])])
            for e in parse_hand(bar.get(hand, "")):
                ql = dur_beats(e.dur, 4)
                if e.is_rest:
                    el = m21.note.Rest(quarterLength=ql)
                else:
                    names = [p.letter + p.acc.replace("b", "-") + str(p.octave) for p in e.pitches]
                    el = m21.note.Note(names[0], quarterLength=ql) if len(names) == 1 else m21.chord.Chord(names, quarterLength=ql)
                    for f in e.fingers:  # music21 writes chord fingerings to the notes in this order
                        el.articulations.append(m21.articulations.Fingering(f))
                m.append(el)
            part.append(m)
        score.append(part)
    return score


def _m21_key(name: str) -> m21.key.Key:
    minor = name.endswith("m")
    tonic = (name[:-1] if minor else name).replace("b", "-")
    return m21.key.Key(tonic.lower() if minor else tonic)
