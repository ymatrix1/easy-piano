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
    assert (spec.range_lo, spec.range_hi, spec.durs, spec.hands, spec.bars) == (
        "G2",
        "D5",
        ["2.", "4", "8"],
        "BOTH",
        1,
    )


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


SKILL_SPECS = sorted((ROOT / "content" / "skill-specs").glob("*.json"))


def test_every_skill_spec_pattern_encodes():
    patterns = [
        p
        for f in SKILL_SPECS
        for node in json.loads(f.read_text(encoding="utf-8"))["nodes"]
        for p in node.get("required", [])
    ]
    assert len(patterns) > 20
    for p in patterns:
        steps = tk.encode_pattern(p)
        assert tk.show(steps[0]) == "PAT" and len(steps) == 1 + len(p)


def test_pattern_keys_match_skill_spec_doc():
    doc = (ROOT / "docs" / "specs" / "skill-specs.md").read_text(encoding="utf-8")
    for key in tk.PATTERN_KEYS:
        assert f"`{key}`" in doc, key


def test_unknown_pattern_key_raises():
    with pytest.raises(Unsupported):
        tk.encode_pattern({"tempo": 3})


def ok_prefix():
    return [tk.step("BOS"), tk.step("TIME_4/4"), tk.step("KEY_C")]


@pytest.mark.parametrize(
    "body,msg",
    [
        ([tk.step("NOTE", pitch="C4", dur="4")], "outside a hand"),
        (
            [tk.step("BAR"), tk.step("RH"), (tk._IDS["kind"]["NOTE"], tk._IDS["pitch"]["C4"], 0, 0)],
            "needs pitch and dur",
        ),
        ([tk.step("BAR"), tk.step("RH"), tk.step("CHORD", pitch="E4")], "without a preceding NOTE"),
        ([tk.step("BAR"), tk.step("RH"), tk.step("REST", pitch="C4", dur="4")], "only dur"),
        ([tk.step("BAR"), tk.step("RH"), tk.step("NOTE", pitch="C4", dur="1"), tk.step("RH")], "twice"),
        (
            [tk.step("BAR"), tk.step("RH"), tk.step("NOTE", pitch="C4", dur="1"), tk.step("BARS_8")],
            "after the first BAR",
        ),
        ([tk.step("BAR"), tk.step("RH")], "empty RH"),
        ([tk.step("BAR"), tk.step("RH"), (999, 0, 0, 0)], "out of range"),
        ([], "no bars"),
    ],
)
def test_decode_rejects_invalid(body, msg):
    with pytest.raises(tk.InvalidSequence, match=msg):
        tk.decode(ok_prefix() + body + [tk.step("END")])


def test_decode_needs_time_and_key():
    with pytest.raises(tk.InvalidSequence, match="TIME or KEY"):
        tk.decode([tk.step("BAR"), tk.step("RH"), tk.step("NOTE", pitch="C4", dur="1")])


def test_tie_round_trip_and_validation():
    bars = [{"RH": "C4:2 D4:2 {tie}"}, {"RH": "D4:2 E4:2"}]
    steps = tk.encode_bars(bars)
    assert "TIE" in [tk.show(x) for x in steps]
    assert tk.decode(ok_prefix() + steps + [tk.step("END")])["bars"] == bars
    with pytest.raises(tk.InvalidSequence, match="TIE"):
        tk.decode(ok_prefix() + [tk.step("BAR"), tk.step("RH"), tk.step("REST", dur="1"), tk.step("TIE")])


def test_style_and_source_tokens_in_spec():
    song = {"time": "4/4", "key": "C", "bars": [{"RH": "C4:4 D4:4 E4:4 F4:4 G4:4 A4:4 B4:4 C5:4"}]}
    spec = tk.spec_from_song(song)
    spec.styles, spec.source = ["pop", "game"], "pdmx"
    shown = [tk.show(x) for x in tk.encode_song(song, spec)]
    assert shown[1:5] == ["SPEC", "STYLE_game", "STYLE_pop", "SRC_pdmx"]
    assert tk.decode(tk.encode_song(song, spec))["bars"] == song["bars"]
