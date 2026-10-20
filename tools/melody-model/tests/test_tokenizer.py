import json
from pathlib import Path

import pytest

from melody_model import tokenizer as tk
from melody_model.notation import Unsupported

ROOT = Path(__file__).resolve().parents[3]
SONGS = sorted((ROOT / "content" / "songs").glob("*.json"))


def hands_only(bars):
    return [{h: b[h] for h in ("RH", "LH") if h in b} for b in bars]


def normalize(bars):
    return [{h: " ".join(s.split()) for h, s in b.items()} for b in bars]


@pytest.mark.parametrize("path", SONGS, ids=lambda p: p.stem)
def test_song_round_trip(path):
    song = json.loads(path.read_text(encoding="utf-8"))
    steps = tk.encode_song(song)
    back = tk.decode(steps)
    assert back["time"] == song["time"]
    assert back["key"] == song["key"]
    assert back["bars"] == normalize(hands_only(song["bars"]))


def test_all_songs_covered():
    assert len(SONGS) >= 40


def test_chord_is_note_plus_chord_steps():
    steps = tk.encode_bars([{"LH": "C3E3G3:2@531 r:2"}])
    assert [tk.show(s) for s in steps] == ["BAR", "LH", "NOTE C3 2 5", "CHORD E3 3", "CHORD G3 1", "REST 2"]


def test_spec_from_song():
    song = {"time": "3/4", "key": "G", "bars": [{"RH": "D5:4@5 G4:8@1 A4:8@2 B4:4@3", "LH": "G2:2.@5"}]}
    spec = tk.spec_from_song(song)
    assert (spec.range_lo, spec.range_hi, spec.durs, spec.hands, spec.bars) == ("G2", "D5", ["2.", "4", "8"], "BOTH", 1)


def test_unsupported_notation_raises():
    for bad in ["C4:3/8", "C4:4{tie}", "Cn4:4", "C4:4@12"]:
        with pytest.raises(Unsupported):
            tk.encode_bars([{"RH": bad}])


def test_vocab_file_matches_code():
    assert (Path(__file__).parents[1] / "vocab.json").read_text(encoding="utf-8") == tk.vocab_json()


def test_vocab_size_and_sequence_length():
    total = sum(len(v) for v in tk.FIELDS.values())
    assert total < 400
    longest = max(len(tk.encode_song(json.loads(p.read_text(encoding="utf-8")))) for p in SONGS)
    assert longest <= 1024, longest
