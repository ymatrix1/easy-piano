"""Convert MusicXML, ABC and MIDI (LilyPond via Mutopia's MIDI) to song JSON bars.

Output is {"time", "key", "bars": [{"RH": ..., "LH": ...}], "title", "composer"}:
the RH/LH subset of docs/specs/content-format.md. Tunes the format cannot hold
raise Unsupported (counted and skipped by the dataset builder):

- more than two parts (unless melody_only), hands with different bar counts
- meter changes (shorter bars before repeats excepted), key changes including
  same-signature mode changes (C -> Am), ambiguous keys
- tuplets and durations outside DURATIONS, double accidentals
- ties are kept as `{tie}` (content grammar): across barlines, and inside a bar
  when the tied sum is not one duration; otherwise merged into one note;
  a tie into a different pitch is rejected
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
        raise errors[0]
    return songs


def convert_file_lenient(path: str | Path) -> tuple[list[dict], list[Unsupported]]:
    """Like convert_file but collects per-tune errors (always Unsupported) instead of raising."""
    path = Path(path)
    try:
        parsed = m21.converter.parse(
            str(path), forceSource=True, quantizePost=path.suffix.lower() in (".mid", ".midi")
        )
    except Exception as e:  # music21 raises many types on malformed input
        return [], [Unsupported(f"parse error: {type(e).__name__}")]
    scores = list(parsed.scores) if isinstance(parsed, m21.stream.Opus) else [parsed]
    songs, errors = [], []
    for s in scores:
        try:
            songs.append(convert_score(s))
        except Unsupported as e:
            errors.append(e)
        except Exception as e:
            errors.append(Unsupported(f"parse error: {type(e).__name__}"))
    return songs, errors


def convert_score(
    score: m21.stream.Score, melody_only: bool = False, part: int | str = 0, key: str | None = None
) -> dict:
    """melody_only: read only one part (index or name, default the first), as RH (voice + piano scores, MIDI).
    key: use this key name instead of reading it from the score."""
    parts = list(score.parts)
    if not parts:
        raise Unsupported("no parts")
    if melody_only:
        if isinstance(part, str):
            named = [p for p in parts if p.partName == part]
            if not named:
                raise Unsupported(f"no part named {part!r}")
            parts = named[:1]
        elif not 0 <= part < len(parts):
            raise Unsupported(f"no part {part}")
        else:
            parts = [parts[part]]
    elif len(parts) > 2:
        raise Unsupported(f"{len(parts)} parts")
    time = _time_sig(score)
    bar_ql = Fraction(m21.meter.TimeSignature(time).barDuration.quarterLength).limit_denominator(64)
    hands = _assign_hands(parts, melody_only)
    per_hand = {h: _hand_bars(p, bar_ql, return_voices=True) for h, p in hands.items()}
    counts = {len(b[0]) for b in per_hand.values()}
    if len(counts) != 1:
        raise Unsupported("hands have different bar counts")
    num_bars = counts.pop()
    bars = []
    for i in range(num_bars):
        b = {}
        for h in ("RH", "LH"):
            if h in per_hand:
                v1_bars, v2_bars = per_hand[h]
                b[h] = format_hand(v1_bars[i])
                if v2_bars[i] is not None:
                    b[f"{h}2"] = format_hand(v2_bars[i])
        bars.append(b)
    md = score.metadata
    return {
        "title": (md.title if md else None) or "",
        "composer": (md.composer if md else None) or "",
        "time": time,
        "key": key or _key_name(score),
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
        per_measure[ts.measureNumber or 0] = ts
    if not per_measure:
        raise Unsupported("no time signature")
    main = per_measure[min(per_measure)]
    for ts in per_measure.values():
        # a shorter bar (e.g. 3/8 or 2/4 before a repeat in 6/8) is a short bar, not a meter change
        if (
            ts.barDuration.quarterLength >= main.barDuration.quarterLength
            and ts.ratioString != main.ratioString
        ):
            raise Unsupported(f"time signatures {sorted({t.ratioString for t in per_measure.values()})}")
    t = main.ratioString
    if t not in tk.TIME_SIGS:
        raise Unsupported(f"time {t}")
    return t


def _key_name(score) -> str:
    sigs = list(score.parts[0].recurse().getElementsByClass(m21.key.KeySignature))
    # a bare KeySignature says nothing about mode, so it agrees with a Key of the same sharps
    sharps = {k.sharps for k in sigs}
    modes = {k.mode for k in sigs if isinstance(k, m21.key.Key)}
    if len(sharps) > 1 or len(modes) > 1:
        raise Unsupported("key changes")
    stated = next((k for k in sigs if isinstance(k, m21.key.Key)), None)
    if stated is not None:
        k = stated
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


def _spacers(ql: Fraction) -> list[Event]:
    """Fill a gap with the fewest spacers, longest first."""
    out = []
    for q, d in sorted(_QL_TO_DUR.items(), reverse=True):
        while ql >= q:
            out.append(Event([], d, is_spacer=True))
            ql -= q
    if ql:
        raise Unsupported(f"gap of {ql} quarters")
    return out


def _hand_bars(part, bar_ql: Fraction, return_voices: bool = False):
    measures = list(part.getElementsByClass(m21.stream.Measure))
    if not measures:
        measures = list(part.makeMeasures().getElementsByClass(m21.stream.Measure))
    raw1: list[tuple[list[Event], Fraction]] = []
    raw2: list[tuple[list[Event] | None, Fraction]] = []
    for n, m in enumerate(measures):
        voices = list(m.voices)
        active = [v for v in voices if list(v.notesAndRests)]
        if len(active) > 2:
            raise Unsupported(f"three or more voices in bar {m.number}")
        v1 = active[0] if active else m
        v2 = active[1] if len(active) == 2 else None

        events1: list[Event] = []
        pad_left = Fraction(m.paddingLeft).limit_denominator(64)
        if pad_left:
            events1 += _rests(pad_left)
        events1 += _bar_events(v1, n + 1, is_voice2=False)
        raw1.append(
            (
                events1,
                sum((Fraction(dur_beats(e.dur, 4)).limit_denominator(64) for e in events1), Fraction(0)),
            )
        )

        if v2 is not None:
            events2: list[Event] = []
            if pad_left:
                events2 += _spacers(pad_left)
            events2 += _bar_events(v2, n + 1, is_voice2=True)
            tot2 = sum((Fraction(dur_beats(e.dur, 4)).limit_denominator(64) for e in events2), Fraction(0))
            if tot2 < bar_ql:
                events2 += _spacers(bar_ql - tot2)
                tot2 = bar_ql
            raw2.append((events2, tot2))
        else:
            raw2.append((None, Fraction(0)))

    bars1: list[list[Event]] = []
    bars2: list[list[Event] | None] = []
    i = 0
    while i < len(raw1):
        events, total = raw1[i]
        if total > bar_ql:
            raise Unsupported(f"bar {i + 1} lasts {total} quarters, expected {bar_ql}")
        if total < bar_ql:
            # strain end + next strain's pickup written as two short measures: join them
            j, acc, merged = i, total, list(events)
            while acc < bar_ql and j + 1 < len(raw1) and raw1[j + 1][1] < bar_ql:
                j += 1
                acc += raw1[j][1]
                merged += raw1[j][0]
            if acc == bar_ql and j > i:
                bars1.append(merged)
                bars2.append(raw2[i][0])
                i = j + 1
                continue
            if i == 0:
                events = _rests(bar_ql - total) + events  # opening pickup
            elif i == len(raw1) - 1 or _at_section_end(measures[i], measures, i):
                events = events + _rests(bar_ql - total)
            else:
                raise Unsupported(f"bar {i + 1} lasts {total} quarters, expected {bar_ql}")
        bars1.append(events)
        ev2, tot2 = raw2[i]
        if ev2 is not None and tot2 > bar_ql:
            raise Unsupported(f"bar {i + 1} voice 2 lasts {tot2} quarters, expected {bar_ql}")
        bars2.append(ev2)
        i += 1
    _check_ties(bars1)
    _check_ties([b for b in bars2 if b is not None])
    if return_voices:
        return bars1, bars2
    return bars1


def _bar_events(voice, bar_no: int, is_voice2: bool = False) -> list[Event]:
    """Notes and rests of one bar. Ties become `Event.tie`; a tie chain inside the bar
    whose sum is one duration is merged into one note."""
    events: list[Event] = []
    cur_offset = Fraction(0)
    for el in voice.notesAndRests:
        if el.duration.isGrace or isinstance(el, m21.harmony.ChordSymbol):
            continue
        el_offset = Fraction(el.offset).limit_denominator(64)
        if el_offset > cur_offset:
            gap = el_offset - cur_offset
            events += _spacers(gap) if is_voice2 else _rests(gap)
            cur_offset = el_offset
        e = _event(el)
        e.tie = el.tie is not None and not el.isRest and el.tie.type in ("start", "continue")
        prev = events[-1] if events else None
        if prev is not None and prev.tie and prev.pitches == e.pitches:
            ql = Fraction(dur_beats(prev.dur, 4) + dur_beats(e.dur, 4)).limit_denominator(64)
            d = _QL_TO_DUR.get(ql)
            if d is not None:
                prev.dur, prev.tie = d, e.tie
                cur_offset += Fraction(dur_beats(e.dur, 4)).limit_denominator(64)
                continue
        events.append(e)
        cur_offset += Fraction(dur_beats(e.dur, 4)).limit_denominator(64)
    return events


def _check_ties(bars: list[list[Event]]) -> None:
    """A tie must lead into a note of the same pitches. A tie on the very last note
    (dangling, common in exports) is dropped; a tie into another pitch is an error."""
    flat = [e for bar in bars for e in bar]
    for e, nxt in zip(flat, flat[1:] + [None]):
        if not e.tie:
            continue
        if nxt is None:
            e.tie = False
        elif nxt.pitches != e.pitches:
            raise Unsupported("tie into a different pitch")


def _at_section_end(m, measures, n) -> bool:
    """Short bars before a repeat or double bar (pickup tunes) are padded too."""
    right = m.rightBarline
    nxt = measures[n + 1].leftBarline if n + 1 < len(measures) else None
    ends = isinstance(right, m21.bar.Repeat) or (
        right is not None and right.type in ("final", "light-heavy", "double", "heavy-light")
    )
    return ends or isinstance(nxt, m21.bar.Repeat)


def _event(el) -> Event:
    ql = Fraction(el.duration.quarterLength).limit_denominator(64)
    dur = _QL_TO_DUR.get(ql)
    if dur is None:
        raise Unsupported(f"duration {ql} quarters")
    if el.isRest:
        is_spacer = getattr(el.style, "hideObjectOnPrint", False)
        return Event([], dur, is_spacer=is_spacer)
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
    """Song JSON (RH/LH/RH2/LH2) to a music21 score; used by tests and listening exports."""
    from .notation import parse_hand

    score = m21.stream.Score()
    for hand, clef in (("RH", m21.clef.TrebleClef()), ("LH", m21.clef.BassClef())):
        hand2 = f"{hand}2"
        if not any(hand in b or hand2 in b for b in song["bars"]):
            continue
        part = m21.stream.Part(id=hand)
        tied_in = False
        tied_in2 = False
        for i, bar in enumerate(song["bars"]):
            m = m21.stream.Measure(number=i + 1)
            if i == 0:
                m.append([clef, m21.meter.TimeSignature(song["time"]), _m21_key(song["key"])])
            has_v2 = hand2 in bar
            if not has_v2:
                for e in parse_hand(bar.get(hand, "")):
                    ql = dur_beats(e.dur, 4)
                    if e.is_rest or e.is_spacer:
                        el = m21.note.Rest(quarterLength=ql)
                        if e.is_spacer:
                            el.style.hideObjectOnPrint = True
                    else:
                        names = [p.letter + p.acc.replace("b", "-") + str(p.octave) for p in e.pitches]
                        el = (
                            m21.note.Note(names[0], quarterLength=ql)
                            if len(names) == 1
                            else m21.chord.Chord(names, quarterLength=ql)
                        )
                        for f in e.fingers:
                            el.articulations.append(m21.articulations.Fingering(f))
                        if e.tie or tied_in:
                            el.tie = m21.tie.Tie(
                                "continue" if e.tie and tied_in else "start" if e.tie else "stop"
                            )
                    tied_in = e.tie
                    m.append(el)
            else:
                v1 = m21.stream.Voice(id="1")
                for e in parse_hand(bar.get(hand, "")):
                    ql = dur_beats(e.dur, 4)
                    if e.is_rest or e.is_spacer:
                        el = m21.note.Rest(quarterLength=ql)
                        if e.is_spacer:
                            el.style.hideObjectOnPrint = True
                    else:
                        names = [p.letter + p.acc.replace("b", "-") + str(p.octave) for p in e.pitches]
                        el = (
                            m21.note.Note(names[0], quarterLength=ql)
                            if len(names) == 1
                            else m21.chord.Chord(names, quarterLength=ql)
                        )
                        for f in e.fingers:
                            el.articulations.append(m21.articulations.Fingering(f))
                        if e.tie or tied_in:
                            el.tie = m21.tie.Tie(
                                "continue" if e.tie and tied_in else "start" if e.tie else "stop"
                            )
                    tied_in = e.tie
                    v1.append(el)

                v2 = m21.stream.Voice(id="2")
                for e in parse_hand(bar.get(hand2, "")):
                    ql = dur_beats(e.dur, 4)
                    if e.is_rest or e.is_spacer:
                        el = m21.note.Rest(quarterLength=ql)
                        if e.is_spacer:
                            el.style.hideObjectOnPrint = True
                    else:
                        names = [p.letter + p.acc.replace("b", "-") + str(p.octave) for p in e.pitches]
                        el = (
                            m21.note.Note(names[0], quarterLength=ql)
                            if len(names) == 1
                            else m21.chord.Chord(names, quarterLength=ql)
                        )
                        for f in e.fingers:
                            el.articulations.append(m21.articulations.Fingering(f))
                        if e.tie or tied_in2:
                            el.tie = m21.tie.Tie(
                                "continue" if e.tie and tied_in2 else "start" if e.tie else "stop"
                            )
                    tied_in2 = e.tie
                    v2.append(el)

                m.insert(0, v1)
                m.insert(0, v2)
            part.append(m)
        score.append(part)
    return score


def _m21_key(name: str) -> m21.key.Key:
    minor = name.endswith("m")
    tonic = (name[:-1] if minor else name).replace("b", "-")
    return m21.key.Key(tonic.lower() if minor else tonic)
