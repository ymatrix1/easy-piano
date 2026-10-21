import json
from pathlib import Path

import pytest

from melody_model import augment, filters, labels
from melody_model.notation import Unsupported

ROOT = Path(__file__).resolve().parents[3]
ODE = json.loads((ROOT / "content" / "songs" / "ode-to-joy.json").read_text(encoding="utf-8"))


def test_plan_labels_ode_to_joy():
    p = labels.plan(ODE)
    assert len(p) == len(ODE["bars"])
    # Ode to Joy: phrase 1 (bars 1-4) and phrase 2 (bars 5-8) share bars 1-3
    assert [x[0] for x in p[:3]] == [x[0] for x in p[4:7]]
    assert p[7][1] == "STABLE"  # phrase ends on the tonic
    assert all(c in ("STABLE", "OPEN") and k in ("UP", "DOWN", "FLAT") for _, c, k in p)


def test_plan_tokens_round_shape():
    steps = labels.encode_plan([("A", "OPEN", "UP"), ("B", "STABLE", "FLAT")])
    assert len(steps) == 2 + 3 * 2


def test_transpose_spelled():
    song = {"time": "4/4", "key": "C", "bars": [{"RH": "C4:4@1 E4:4@3 G4:2@5", "LH": "C3E3G3:1@531"}]}
    up = augment.transpose_song(song, 7)  # C -> G
    assert up["key"] == "G"
    assert up["bars"][0] == {"RH": "G4:4@1 B4:4@3 D5:2@5", "LH": "G3B3D4:1@531"}
    down = augment.transpose_song(song, -2)  # C -> Bb
    assert down["key"] == "Bb"
    assert down["bars"][0]["RH"] == "Bb3:4@1 D4:4@3 F4:2@5"


def test_transpose_rejects_double_accidentals():
    song = {"time": "4/4", "key": "Cb", "bars": [{"RH": "Cb4:1"}]}  # +1 semitone would need Dbb
    with pytest.raises(Unsupported):
        augment.transpose_song(song, 1)


def test_windows_phrase_aligned():
    w = augment.windows(16)
    assert (0, 16) in w and (4, 8) in w and (8, 16) in w
    assert all(a % 4 == 0 for a, _ in w)


def test_split_deterministic_and_balanced():
    splits = [filters.split_of("pdmx", f"t{i}") for i in range(5000)]
    assert splits == [filters.split_of("pdmx", f"t{i}") for i in range(5000)]
    assert 0.87 < splits.count("train") / 5000 < 0.93


def test_dedupe_is_transposition_invariant():
    assert filters.dedupe_key(ODE) == filters.dedupe_key(augment.transpose_song(ODE, 5))


def test_playable_rejects_big_leap():
    song = {"time": "4/4", "key": "C", "bars": [{"RH": "C4:8 C6:8 C4:8 D4:8 E4:8 F4:8 G4:8 A4:8"}]}
    assert filters.playable(song) == (False, "big leap")
    assert filters.playable(ODE) == (True, "")


def pdmx_row(**kw):
    row = {
        "subset:no_license_conflict": "True",
        "subset:deduplicated": "True",
        "genres": "classical",
        "is_original": "False",
        "composer_name": "Johann Sebastian Bach",
        "artist_name": "NA",
        "title": "Minuet",
        "song_name": "NA",
        "subtitle": "NA",
        "song_length.bars": "32",
    }
    row.update(kw)
    return row


@pytest.mark.parametrize(
    "kw,ok",
    [
        ({}, True),
        ({"genres": "pop"}, False),
        ({"genres": "NA"}, False),
        ({"genres": "NA", "is_original": "True"}, True),
        ({"composer_name": "NA"}, False),
        ({"title": "Minuet (arr. for easy piano)"}, False),
        ({"title": "Minuet (arr. for easy piano)", "is_original": "True"}, True),
        ({"composer_name": "Joe Hisaishi"}, False),
        ({"title": "Hedwig's Theme"}, False),
        ({"title": "Sonata Op. 13"}, True),
        ({"subset:no_license_conflict": "False"}, False),
    ],
)
def test_pdmx_screen(kw, ok):
    """ok == no clean-data flags (D21 keeps flagged tunes, separable)."""
    row = pdmx_row(**kw)
    hard_ok = filters.pdmx_ok(row)[0]
    assert (hard_ok and not filters.pdmx_flags(row)) is ok


def test_nmd_named_composer():
    assert not filters.nmd_ok("X:2\nT:Abacus\nS:By Hugh Barwell, via Phil Rowe\nK:G\n")
    assert filters.nmd_ok("X:1\nT:A and D\nS:EF\nK:A\n")
