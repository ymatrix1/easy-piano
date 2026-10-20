"""Convert MusicXML, ABC and MIDI (LilyPond via Mutopia's MIDI) to song JSON bars.

Output is {"time", "key", "bars": [{"RH": ..., "LH": ...}], "title", "composer"}:
the RH/LH subset of docs/specs/content-format.md. Tunes the format cannot hold
(tuplets, double accidentals, meter changes, durations outside DURATIONS)
raise Unsupported; the dataset builder counts and skips them.

LilyPond: we do not parse .ly. Mutopia ships a MIDI rendered by LilyPond from
the same source under the same licence, so `convert_file` reads that instead
(pitch spelling is re-inferred and fingering is lost).
"""

from __future__ import annotations

from fractions import Fraction
from pathlib import Path

import music21 as m21

from . import tokenizer as tk
from .notation import DURATIONS, Event, Pitch, Unsupported, dur_beats, format_hand

# quarterLength -> duration string
_QL_TO_DUR = {Fraction(dur_beats(d, 4)).limit_denominator(64): d for d in DURATIONS}


def convert_file(path: str | Path) -> list[dict]:
    """All tunes in a file (ABC files can hold many); raises on the first unsupported tune."""
    songs, errors = convert_file_lenient(path)
    if errors:
        raise Unsupported(errors[0])
    return songs


def convert_file_lenient(path: str | Path) -> tuple[list[dict], list[str]]:
    """Like convert_file but collects per-tune errors instead of raising."""
    path = Path(path)
    parsed = m21.converter.parse(str(path), forceSource=True, quantizePost=path.suffix.lower() in (".mid", ".midi"))
    scores = list(parsed.scores) if isinstance(parsed, m21.stream.Opus) else [parsed]
    songs, errors = [], []
    for s in scores:
        try:
            songs.append(convert_score(s))
        except Unsupported as e:
            errors.append(str(e))
    return songs, errors


def convert_score(score: m21.stream.Score, melody_only: bool = False) -> dict:
    """melody_only: keep the first part as RH and drop the rest (voice + piano scores, MIDI)."""
    parts = list(score.parts)
    if not parts:
        raise Unsupported("no parts")
    rh = parts[0]
    lh = parts[1] if len(parts) > 1 and not melody_only else None
    time = _time_sig(score)
    bar_ql = Fraction(m21.meter.TimeSignature(time).barDuration.quarterLength).limit_denominator(64)
    rh_bars = _hand_bars(rh, bar_ql)
    lh_bars = _hand_bars(lh, bar_ql) if lh is not None else None
    if lh_bars is not None and len(lh_bars) != len(rh_bars):
        raise Unsupported("hands have different bar counts")
    bars = []
    # a lone bass-clef part is a left-hand piece
    first_hand = "LH" if lh is None and isinstance(rh.recurse().getElementsByClass(m21.clef.Clef).first(), m21.clef.BassClef) else "RH"
    for i, r in enumerate(rh_bars):
        bar = {first_hand: format_hand(r)}
        if lh_bars is not None:
            bar["LH"] = format_hand(lh_bars[i])
        bars.append(bar)
    md = score.metadata
    return {
        "title": (md.title if md else None) or "",
        "composer": (md.composer if md else None) or "",
        "time": time,
        "key": _key_name(score),
        "bars": bars,
    }


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
    keys = list(score.recurse().getElementsByClass(m21.key.KeySignature))
    if len({k.sharps for k in keys}) > 1:
        raise Unsupported("key changes")
    if keys and isinstance(keys[0], m21.key.Key):
        k = keys[0]
    else:
        sharps = keys[0].sharps if keys else score.analyze("key").sharps
        analyzed = score.analyze("key")
        k = m21.key.KeySignature(sharps).asKey(analyzed.mode if analyzed.mode in ("major", "minor") else "major")
    tonic = k.tonic.name.replace("-", "b")
    name = tonic + ("m" if k.mode == "minor" else "")
    if name not in tk.KEYS:
        raise Unsupported(f"key {name}")
    return name


def _hand_bars(part, bar_ql: Fraction) -> list[list[Event]]:
    measures = list(part.getElementsByClass(m21.stream.Measure))
    if not measures:
        measures = list(part.makeMeasures().getElementsByClass(m21.stream.Measure))
    raw: list[tuple[list[Event], Fraction]] = []
    for m in measures:
        voice = m.voices[0] if m.voices else m
        events: list[Event] = []
        pad_left = Fraction(m.paddingLeft).limit_denominator(64)
        if pad_left:
            events += _rests(pad_left)
        for el in voice.notesAndRests:
            if el.duration.isGrace or isinstance(el, m21.harmony.ChordSymbol):
                continue
            events.append(_event(el))
        _merge_ties(events, voice)
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


def _at_section_end(m, measures, n) -> bool:
    """Short bars before a repeat or double bar (pickup tunes) are padded too."""
    right = m.rightBarline
    nxt = measures[n + 1].leftBarline if n + 1 < len(measures) else None
    ends = isinstance(right, m21.bar.Repeat) or (right is not None and right.type in ("final", "light-heavy", "double", "heavy-light"))
    return ends or isinstance(nxt, m21.bar.Repeat)


def _event(el) -> Event:
    ql = Fraction(el.duration.quarterLength).limit_denominator(64)
    dur = _QL_TO_DUR.get(ql)
    if dur is None:
        raise Unsupported(f"duration {ql} quarters")
    if el.isRest:
        return Event([], dur)
    notes = list(el.notes) if el.isChord else [el]
    pitches = [_pitch(n.pitch) for n in notes]
    fingers = _fingers(el, len(pitches))
    return Event(pitches, dur, fingers)


def _pitch(p: m21.pitch.Pitch) -> Pitch:
    alter = p.accidental.alter if p.accidental else 0
    acc = {0: "", 1: "#", -1: "b"}.get(int(alter)) if alter == int(alter) else None
    if acc is None:
        raise Unsupported(f"accidental {p.nameWithOctave}")
    if not 0 <= p.octave <= 8:
        raise Unsupported(f"octave {p.nameWithOctave}")
    return Pitch(p.step, acc, p.octave)


def _fingers(el, count: int) -> list[int]:
    fs = [a.fingerNumber for a in el.articulations if isinstance(a, m21.articulations.Fingering)]
    fs = [f for f in fs if isinstance(f, int) and 1 <= f <= 5]
    return fs if len(fs) == count else []


def _merge_ties(events: list[Event], voice) -> None:
    """Merge a tie start/stop pair inside a bar when the sum is one duration."""
    els = [el for el in voice.notesAndRests if not el.duration.isGrace and not isinstance(el, m21.harmony.ChordSymbol)]
    offset = len(events) - len(els)
    i = len(els) - 2
    while i >= 0:
        a, b = els[i], els[i + 1]
        if a.tie is not None and a.tie.type in ("start", "continue") and not a.isRest:
            ea, eb = events[offset + i], events[offset + i + 1]
            if ea.pitches == eb.pitches:
                ql = Fraction(dur_beats(ea.dur, 4) + dur_beats(eb.dur, 4)).limit_denominator(64)
                d = _QL_TO_DUR.get(ql)
                if d is not None:
                    ea.dur = d
                    del events[offset + i + 1]
        i -= 1


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
                    for f in e.fingers:
                        el.articulations.append(m21.articulations.Fingering(f))
                m.append(el)
            part.append(m)
        score.append(part)
    return score


def _m21_key(name: str) -> m21.key.Key:
    minor = name.endswith("m")
    tonic = (name[:-1] if minor else name).replace("b", "-")
    return m21.key.Key(tonic.lower() if minor else tonic)
