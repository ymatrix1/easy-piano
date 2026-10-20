import json
from pathlib import Path

import pytest

from melody_model import convert
from melody_model.notation import parse_hand

ROOT = Path(__file__).resolve().parents[3]
SONGS = sorted((ROOT / "content" / "songs").glob("*.json"))
FIXTURES = Path(__file__).parent / "fixtures"


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def hands_only(bars):
    return [{h: " ".join(b[h].split()) for h in ("RH", "LH") if h in b} for b in bars]


@pytest.mark.parametrize("path", SONGS, ids=lambda p: p.stem)
def test_musicxml_round_trip(path, tmp_path):
    song = load(path)
    xml = tmp_path / "song.musicxml"
    convert.song_to_score(song).write("musicxml", fp=str(xml))
    [back] = convert.convert_file(xml)
    assert back["time"] == song["time"]
    assert back["key"] == song["key"]
    assert back["bars"] == hands_only(song["bars"])


def midi_and_beats(bars, hand):
    out = []
    for b in bars:
        for e in parse_hand(b.get(hand, "")):
            out.append((tuple(sorted(p.midi for p in e.pitches)), e.dur))
    return out


@pytest.mark.parametrize("path", SONGS, ids=lambda p: p.stem)
def test_midi_round_trip_pitch_and_rhythm(path, tmp_path):
    """MIDI (Mutopia path) loses spelling and fingering; pitches and durations must survive."""
    song = load(path)
    mid = tmp_path / "song.mid"
    convert.song_to_score(song).write("midi", fp=str(mid))
    [back] = convert.convert_file(mid)
    assert back["time"] == song["time"]
    for hand in ("RH", "LH"):
        if any(hand in b for b in song["bars"]):
            assert midi_and_beats(back["bars"], hand) == midi_and_beats(song["bars"], hand), hand


def test_abc_multi_tune_file():
    songs, errors = convert.convert_file_lenient(FIXTURES / "pd-tunes.abc")
    assert errors == ["duration 1/3 quarters"]  # the triplet tune is rejected, not mangled
    by_title = {s["title"]: s for s in songs}
    twinkle = by_title["Twinkle Twinkle Little Star"]
    assert (twinkle["time"], twinkle["key"]) == ("4/4", "C")
    assert twinkle["bars"][:2] == [{"RH": "C4:4 C4:4 G4:4 G4:4"}, {"RH": "A4:4 A4:4 G4:2"}]
    jig = by_title["Pickup Jig"]
    assert (jig["time"], jig["key"]) == ("6/8", "G")
    assert jig["bars"][0] == {"RH": "r:2 r:8 D4:8"}  # anacrusis padded with leading rests (greedy, longest first)
    assert jig["bars"][1] == {"RH": "G4:4 A4:8 B4:4 G4:8"}
