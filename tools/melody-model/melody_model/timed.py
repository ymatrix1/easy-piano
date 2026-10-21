"""Performed (seconds-timed) MIDI melodies to song JSON.

For MIDI without a usable tempo map (live recordings, game rips): beats come
from a beat file or are estimated from onsets. Notes are placed on a
16th-note grid of the given (or estimated) beats, monophonized (highest
note wins), split at barlines. Notes whose grid length has no single
duration are split into re-attacked pieces (the format has no ties).
"""

from __future__ import annotations

import bisect
from pathlib import Path

import mido

from .notation import Event, Pitch, Unsupported, format_hand
from .tokenizer import KEYS

GRID = 4  # 16ths per beat
_LEN_TO_DUR = {1: "16", 2: "8", 3: "8.", 4: "4", 6: "4.", 7: "4..", 8: "2", 12: "2.", 14: "2..", 16: "1"}
_SHARP = ("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B")
_FLAT = ("C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B")
_FLAT_KEYS = {"F", "Bb", "Eb", "Ab", "Db", "Gb", "Cb", "Dm", "Gm", "Cm", "Fm", "Bbm", "Ebm", "Abm"}


def midi_notes(path: str | Path, track: str | int) -> list[tuple[float, float, int]]:
    """(onset s, offset s, pitch) for one track, by name or index; tempo map honoured."""
    mf = mido.MidiFile(str(path))
    tempo_map = []  # (tick, tempo) from all tracks
    for t in mf.tracks:
        tick = 0
        for msg in t:
            tick += msg.time
            if msg.type == "set_tempo":
                tempo_map.append((tick, msg.tempo))
    tempo_map.sort()
    tracks = [t for t in mf.tracks if t.name == track] if isinstance(track, str) else [mf.tracks[track]]
    if not tracks:
        raise Unsupported(f"no track {track}")

    def seconds(tick: int) -> float:
        s, last_tick, tempo = 0.0, 0, 500000
        for t_tick, t_tempo in tempo_map:
            if t_tick >= tick:
                break
            s += (t_tick - last_tick) * tempo / 1e6 / mf.ticks_per_beat
            last_tick, tempo = t_tick, t_tempo
        return s + (tick - last_tick) * tempo / 1e6 / mf.ticks_per_beat

    notes, open_ = [], {}
    tick = 0
    for msg in tracks[0]:
        tick += msg.time
        if msg.type == "note_on" and msg.velocity > 0:
            open_[msg.note] = tick
        elif msg.type in ("note_off", "note_on") and msg.note in open_:
            on = open_.pop(msg.note)
            notes.append((seconds(on), seconds(tick), msg.note))
    notes.sort()
    return notes


def estimate_beats(notes, lo_bpm=70, hi_bpm=180, min_fit=0.9):
    """Beat times from onsets alone.

    Among tempos whose 16th grid fits min_fit of onsets, prefer the one that puts
    most onsets on 8th positions, then the one closest to 120 bpm.
    """
    onsets = [n[0] for n in notes]
    if len(onsets) < 16:
        raise Unsupported("too few notes to estimate tempo")
    t0, end = onsets[0], notes[-1][1]

    def share_on(step):
        return sum(abs((o - t0) / step - round((o - t0) / step)) < 0.15 for o in onsets) / len(onsets)

    best = None
    for bpm10 in range(lo_bpm * 10, hi_bpm * 10 + 1, 5):
        period = 600 / bpm10
        if share_on(period / GRID) < min_fit:
            continue
        score = (round(share_on(period / 2) * 20), -abs(bpm10 - 1200))
        if best is None or score > best[0]:
            best = (score, period)
    if best is None:
        raise Unsupported("no tempo fits the onsets")
    period = best[1]
    n = int((end - t0) / period) + 2
    return [t0 + i * period for i in range(n)]


def notes_to_song(notes, beats: list[float], downbeats: list[int], beats_per_bar: int, key: str) -> dict:
    """Place notes on the beat grid. downbeats: indices into beats where bars start."""
    if key not in KEYS:
        raise Unsupported(f"key {key}")
    if beats_per_bar not in (2, 3, 4):
        raise Unsupported(f"{beats_per_bar} beats per bar")
    names = _FLAT if key in _FLAT_KEYS else _SHARP

    def grid(t: float) -> int:
        i = bisect.bisect_right(beats, t) - 1
        i = min(max(i, 0), len(beats) - 2)
        span = beats[i + 1] - beats[i]
        return round((i + (t - beats[i]) / span) * GRID)

    first_bar = downbeats[0] * GRID
    slots: dict[int, tuple[int, int]] = {}  # onset slot -> (pitch, end slot); highest pitch wins
    for on, off, pitch in notes:
        a, b = grid(on), max(grid(off), grid(on) + 1)
        if a not in slots or pitch > slots[a][0]:
            slots[a] = (pitch, b)
    if not slots:
        raise Unsupported("no notes")
    starts = sorted(slots)
    bar_len = beats_per_bar * GRID
    origin = first_bar - ((first_bar - starts[0]) // bar_len + 1) * bar_len if starts[0] < first_bar else first_bar
    last = max(b for _, b in slots.values())
    n_bars = (last - origin + bar_len - 1) // bar_len
    line: list[tuple[int, int, int | None]] = []  # (start, end, pitch|None)
    pos = origin
    for i, a in enumerate(starts):
        pitch, b = slots[a]
        nxt = starts[i + 1] if i + 1 < len(starts) else origin + n_bars * bar_len
        # performed MIDI is detached; a gap up to one beat is articulation, not a rest
        b = nxt if nxt - b <= GRID else min(b, nxt)
        if a > pos:
            line.append((pos, a, None))
        line.append((a, b, pitch))
        pos = b
    if pos < origin + n_bars * bar_len:
        line.append((pos, origin + n_bars * bar_len, None))
    bars = []
    for k in range(n_bars):
        lo, hi = origin + k * bar_len, origin + (k + 1) * bar_len
        events = []
        for a, b, pitch in line:
            a, b = max(a, lo), min(b, hi)
            if a < b:
                events += _events(b - a, pitch, names)
        bars.append({"RH": format_hand(events)})
    # drop leading/trailing empty bars
    while bars and bars[0]["RH"].replace("r:1", "").strip() == "":
        bars.pop(0)
    while bars and bars[-1]["RH"].replace("r:1", "").strip() == "":
        bars.pop()
    return {"time": f"{beats_per_bar}/4", "key": key, "bars": bars}


def _events(length: int, pitch: int | None, names) -> list[Event]:
    """Greedy longest-first split of a grid length into single durations."""
    out = []
    for size in sorted(_LEN_TO_DUR, reverse=True):
        while length >= size:
            out.append(Event([] if pitch is None else [_pitch(pitch, names)], _LEN_TO_DUR[size]))
            length -= size
    return out


def _pitch(midi: int, names) -> Pitch:
    name = names[midi % 12]
    octave = midi // 12 - 1
    if not 0 <= octave <= 8:
        raise Unsupported(f"octave {octave}")
    return Pitch(name[0], name[1:], octave)


def performed_song(path: str | Path, track: str | int = 0, key: str | None = None, meter: str = "4/4") -> dict:
    """One melody track of a performed MIDI file, tempo estimated from its onsets.

    meter: the dataset's stated meter ("2/4", "3/4" or "4/4"); bar 1 starts at the
    first onset. Performed MIDI carries no reliable meter, so it is given, not guessed.
    """
    beats_per_bar, unit = (int(x) for x in meter.split("/"))
    if unit != 4:
        raise Unsupported(f"performed meter {meter}")
    notes = midi_notes(path, track)
    beats = estimate_beats(notes)
    song = notes_to_song(notes, beats, [0], beats_per_bar, key or guess_key(notes))
    song.update(title=Path(path).stem, composer="")
    return song


def guess_key(notes) -> str:
    """Major key whose scale covers most note time."""
    weight = [0.0] * 12
    for on, off, p in notes:
        weight[p % 12] += off - on
    scale = (0, 2, 4, 5, 7, 9, 11)
    best = max(range(12), key=lambda t: (sum(weight[(t + s) % 12] for s in scale), weight[t]))
    return _FLAT[best] if _FLAT[best] in ("F", "Bb", "Eb", "Ab", "Db", "Gb") else _SHARP[best]
