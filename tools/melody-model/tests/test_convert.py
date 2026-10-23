import json
import re
from pathlib import Path

import pytest

from melody_model import convert
from melody_model.notation import Unsupported, dur_beats, parse_hand

ROOT = Path(__file__).resolve().parents[3]
SONGS = sorted((ROOT / "content" / "songs").glob("*.json"))


def skip_unsupported(song):
    """Converter tests cover the notation the model handles (same subset as test_tokenizer)."""
    try:
        for b in song["bars"]:
            for h in ("RH", "LH"):
                parse_hand(b.get(h, ""))
    except Unsupported:
        pytest.skip("notation the model does not cover")


FIXTURES = Path(__file__).parent / "fixtures"


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


CHORD_FINGERING = re.compile(r"((?:[A-G][#b]?\d){2,}:[\d.]+)@\d+")


def hands_only(bars, chord_fingering=True):
    # chord-symbol directives are display-only labels; the converter does not carry them
    out = [
        {
            h: " ".join(x for x in b[h].split() if not x.startswith("{chord:"))
            for h in ("RH", "LH", "RH2", "LH2")
            if h in b
        }
        for b in bars
    ]
    if not chord_fingering:  # MusicXML import drops chord fingering (see convert.py)
        out = [{h: CHORD_FINGERING.sub(r"\1", s) for h, s in b.items()} for b in out]
    return out


@pytest.mark.parametrize("path", SONGS, ids=lambda p: p.stem)
def test_musicxml_round_trip(path, tmp_path):
    song = load(path)
    skip_unsupported(song)
    xml = tmp_path / "song.musicxml"
    convert.song_to_score(song).write("musicxml", fp=str(xml))
    try:
        [back] = convert.convert_file(xml)
    except Unsupported as e:  # e.g. 6/4: outside the subset
        pytest.skip(str(e))
    assert back["time"] == song["time"]
    assert back["key"] == song["key"]
    assert back["bars"] == hands_only(song["bars"], chord_fingering=False)


def midi_and_beats(bars, hand):
    """(pitches, duration) per event; runs of rests are summed, since MIDI stores none."""
    out = []
    for b in bars:
        for e in parse_hand(b.get(hand, "")):
            if not e.pitches and out and not out[-1][0]:
                out[-1] = ((), out[-1][1] + dur_beats(e.dur, 4))
            else:
                out.append((tuple(sorted(p.midi for p in e.pitches)), dur_beats(e.dur, 4)))
    return out if any(p for p, _ in out) else []  # a hand of rests only has no MIDI notes


def ends_in_silence(song):
    """A hand resting through the last bar: MIDI cannot carry that trailing silence."""
    last = song["bars"][-1]
    return any(all(not e.pitches for e in parse_hand(last.get(h, ""))) for h in ("RH", "LH") if h in last)


@pytest.mark.parametrize("path", SONGS, ids=lambda p: p.stem)
def test_midi_round_trip_pitch_and_rhythm(path, tmp_path):
    """MIDI (Mutopia path) loses spelling and fingering; pitches and durations must survive."""
    song = load(path)
    skip_unsupported(song)
    if any(":32" in b.get(h, "") for b in song["bars"] for h in ("RH", "LH")):
        pytest.skip("MIDI quantization merges 32nd-note ornaments")
    if ends_in_silence(song):
        pytest.skip("a hand rests through the last bar")
    mid = tmp_path / "song.mid"
    convert.song_to_score(song).write("midi", fp=str(mid))
    try:
        [back] = convert.convert_file(mid)
    except Unsupported as e:  # MIDI quantization can yield lengths outside the subset
        pytest.skip(str(e))
    assert back["time"] == song["time"]
    for hand in ("RH", "LH"):
        if any(hand in b for b in song["bars"]):
            assert midi_and_beats(back["bars"], hand) == midi_and_beats(song["bars"], hand), hand


def test_abc_multi_tune_file():
    songs, errors = convert.convert_file_lenient(FIXTURES / "pd-tunes.abc")
    assert all(isinstance(e, Unsupported) for e in errors)
    assert [str(e) for e in errors] == ["duration 1/3 quarters"]  # the triplet tune is rejected, not mangled
    by_title = {s["title"]: s for s in songs}
    twinkle = by_title["Twinkle Twinkle Little Star"]
    assert (twinkle["time"], twinkle["key"]) == ("4/4", "C")
    assert twinkle["bars"][:2] == [{"RH": "C4:4 C4:4 G4:4 G4:4"}, {"RH": "A4:4 A4:4 G4:2"}]
    jig = by_title["Pickup Jig"]
    assert (jig["time"], jig["key"]) == ("6/8", "G")
    assert jig["bars"][0] == {
        "RH": "r:2 r:8 D4:8"
    }  # anacrusis padded with leading rests (greedy, longest first)
    assert jig["bars"][1] == {"RH": "G4:4 A4:8 B4:4 G4:8"}


def test_two_voices_round_trip():
    song = {
        "title": "Two Voices",
        "composer": "Test",
        "time": "4/4",
        "key": "C",
        "bars": [
            {"RH": "E4:4 F4:4 G4:4 A4:4", "RH2": "C4:1", "LH": "C3:1"},
            {"RH": "s:2 G4:2", "RH2": "E4:1", "LH": "C3:1"},
        ],
    }
    score = convert.song_to_score(song)
    back = convert.convert_score(score, key="C")
    assert back["bars"] == song["bars"]
