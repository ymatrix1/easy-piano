"""PR #45 review: dedupe false positives, local registry validation, determinism, gate, bar handling."""

import json
from fractions import Fraction

import music21 as m21
import mido
import pytest

from melody_model import build, convert, filters, gate


def song(*bars, time="4/4"):
    return {"time": time, "key": "C", "bars": [{"RH": b} for b in bars]}


def test_dedupe_no_false_positive_for_same_shape_other_degree():
    a = song("C4:4 E4:4 G4:4 C5:4", "C4:4 E4:4 G4:4 C5:4")
    b = song("C4:4 E4:4 G4:4 C5:4", "D4:4 F#4:4 A4:4 D5:4")
    assert filters.dedupe_key(a) != filters.dedupe_key(b)


def test_dedupe_still_transposition_invariant():
    a = song("C4:4 E4:4 G4:4 C5:4", "D4:4 F4:4 A4:4 D5:4")
    b = song("D4:4 F#4:4 A4:4 D5:4", "E4:4 G4:4 B4:4 E5:4")
    assert filters.dedupe_key(a) == filters.dedupe_key(b)


def test_dedupe_bar_lines_matter():
    a = song("C4:2 D4:2", "E4:1")
    b = song("C4:2 D4:2 E4:1")
    assert filters.dedupe_key(a) != filters.dedupe_key(b)


def write_reg(tmp_path, monkeypatch, entries):
    reg = tmp_path / "local-datasets.json"
    reg.write_text(json.dumps(entries))
    monkeypatch.setattr(build, "LOCAL", reg)


BASE = {"name": "mine", "path": "p", "source": "https://x", "license": "CC0", "flags": []}


@pytest.mark.parametrize("change", [
    {"flags": "pop"}, {"flags": [1]}, {"license": ""}, {"source": "  "}, {"name": 3},
    {"timing": "live"}, {"meter": "6/8"}, {"group_by": "album"}, {"track": True}, {"name": "pdmx"},
])
def test_local_registry_rejects_bad_entries(tmp_path, monkeypatch, change):
    write_reg(tmp_path, monkeypatch, [{**BASE, **change}])
    with pytest.raises(SystemExit):
        build.load_local()


def test_local_registry_rejects_duplicate_names(tmp_path, monkeypatch):
    write_reg(tmp_path, monkeypatch, [BASE, BASE])
    with pytest.raises(SystemExit):
        build.load_local()


def test_local_registry_records_licence_as_given_and_honours_track(tmp_path, monkeypatch):
    folder = tmp_path / "set"
    folder.mkdir()
    s = m21.stream.Score()
    for pitches in (["C2"] * 8, ["E5", "D5", "C5", "D5", "E5", "E5", "E5", "D5"]):  # bass first, melody is track 1
        p = m21.stream.Part()
        p.append(m21.meter.TimeSignature("4/4"))
        p.append(m21.key.Key("C"))
        for x in pitches:
            p.append(m21.note.Note(x, quarterLength=1))
        s.append(p)
    s.write("midi", fp=str(folder / "t.mid"))
    write_reg(tmp_path, monkeypatch, [{**BASE, "path": str(folder), "license": "my own words", "track": 1}])
    [entry] = build.load_local()
    [job] = list(build.jobs_local(entry))
    assert job[4]["license"] == "my own words" and len(job[4]["sha256"]) == 64
    _, _, _, songs, errors = build.work(job)
    assert errors == [] and songs[0]["bars"][0]["RH"] == "E5:4 D5:4 C5:4 D5:4"


def test_performed_midi_uses_given_meter(tmp_path):
    from melody_model import timed
    mf = mido.MidiFile(ticks_per_beat=480)
    tr = mido.MidiTrack()
    mf.tracks.append(tr)
    for p in [60, 62, 64] * 8:
        tr.append(mido.Message("note_on", note=p, velocity=80, time=0))
        tr.append(mido.Message("note_off", note=p, velocity=0, time=480))
    mf.save(tmp_path / "w.mid")
    out = timed.performed_song(tmp_path / "w.mid", meter="3/4")
    assert out["time"] == "3/4" and out["bars"][0]["RH"] == "C4:4 D4:4 E4:4"


def test_build_is_deterministic(tmp_path, monkeypatch):
    monkeypatch.setattr(build, "OUT", tmp_path / "a")
    build.main(["--corpora", "own", "--jobs", "2"])
    first = (tmp_path / "a" / "tunes.jsonl").read_bytes()
    monkeypatch.setattr(build, "OUT", tmp_path / "b")
    build.main(["--corpora", "own", "--jobs", "3"])
    assert (tmp_path / "b" / "tunes.jsonl").read_bytes() == first
    rec = json.loads(first.splitlines()[0])
    for k in ("source_url", "sha256", "license", "composition_license", "arranger", "flags", "plan"):
        assert k in rec


def test_train_refuses_without_gate(tmp_path, monkeypatch):
    from melody_model import train
    monkeypatch.setattr(gate, "GATE", tmp_path / "gate.json")
    with pytest.raises(SystemExit, match="no review gate"):
        train.main(["--name", "t"])


def test_gate_tied_to_dataset_hash(tmp_path, monkeypatch):
    out = tmp_path / "ds"
    out.mkdir()
    (out / "tunes.jsonl").write_text("{}\n")
    monkeypatch.setattr(gate, "OUT", out)
    monkeypatch.setattr(gate, "GATE", tmp_path / "gate.json")
    gate.main(["approve", "--seed", "1", "--n", "50", "--approver-words", "ok", "--date", "2026-10-20"])
    assert gate.require_gate()["seed"] == 1
    (out / "tunes.jsonl").write_text("{}\n{}\n")
    with pytest.raises(SystemExit, match="review a new sample"):
        gate.require_gate()


def ts_score(sigs):
    s = m21.stream.Score()
    p = m21.stream.Part()
    for i, (sig, ql) in enumerate(sigs):
        m = m21.stream.Measure(number=i + 1)
        if sig:
            m.append(m21.meter.TimeSignature(sig))
        m.append(m21.note.Note("C4", quarterLength=ql))
        p.append(m)
    s.append(p)
    return s


def test_time_sig_short_bar_is_not_a_meter_change():
    assert convert._time_sig(ts_score([("6/8", 3), ("3/8", 1.5), ("6/8", 3)])) == "6/8"


def test_time_sig_real_change_rejected():
    with pytest.raises(convert.Unsupported):
        convert._time_sig(ts_score([("4/4", 4), ("3/4", 3), ("4/4", 4), ("5/4", 5)]))


def test_hand_bars_joins_strain_end_and_pickup():
    p = m21.stream.Part()
    for i, notes in enumerate([[2.5], [0.5], [3]]):  # 6/8: 2.5 + 0.5 quarters = one bar
        m = m21.stream.Measure(number=i + 1)
        for ql in notes:
            m.append(m21.note.Note("D4", quarterLength=ql))
        p.append(m)
    with pytest.raises(convert.Unsupported):  # 2.5 quarters is not one duration
        convert._hand_bars(p, Fraction(3))
    p2 = m21.stream.Part()
    for i, notes in enumerate([[1.5, 1], [0.5], [3]]):
        m = m21.stream.Measure(number=i + 1)
        for ql in notes:
            m.append(m21.note.Note("D4", quarterLength=ql))
        p2.append(m)
    bars = convert._hand_bars(p2, Fraction(3))
    assert len(bars) == 2 and [e.dur for e in bars[0]] == ["4.", "4", "8"]


@pytest.mark.parametrize("texts,tags,expected", [
    (["Teresa Teng - The Moon Represents My Heart"], "", True),
    (["March of the Volunteers 义勇军进行曲"], "", True),
    (["Erhu Improvisation no 1"], "", True),
    (["Morning Waltz"], "waltz-piano-violin-taiwan-original", True),
    (["Some tune"], "pianocover-cpop", True),
    (["Seiken Densetsu 3 - 聖剣伝説３ ラスボス"], "", False),  # Japanese (kana present)
    (["The Nutcracker 12c. Chinese Dance"], "", False),
    (["China - Jacob French"], "", False),
    (["Ode to Joy", "Beethoven"], "classical", False),
    (["Catching Wasps", "Gregor Aichinger"], "marching-band", False),
])
def test_is_chinese(texts, tags, expected):
    assert filters.is_chinese(texts, tags) is expected


def test_is_chinese_repairs_mojibake():
    garbled = "义勇军进行曲".encode("utf-8").decode("latin-1")
    assert filters.is_chinese([garbled])


def test_styles_from_metadata():
    from melody_model.styles import styles_for
    assert styles_for("pdmx", {"genres": "soundtrack", "tags": "zelda-ocarina-piano", "title": "Song of Storms"}) == ["game", "soundtrack"]
    assert styles_for("pdmx", {"genres": "classical", "tags": "NA", "title": "Minuet in G"}) == ["classical"]
    assert styles_for("nottingham", {"title": "Ashgrove"}) == ["folk"]
    assert styles_for("mutopia", {"style": "Hymn", "title": "Old 100th"}) == ["religious"]


def test_licence_conflict_is_flagged_not_rejected():
    row = {"subset:no_license_conflict": "False", "subset:deduplicated": "True", "genres": "classical",
           "is_original": "False", "composer_name": "Bach", "artist_name": "NA", "title": "Minuet",
           "song_name": "NA", "subtitle": "NA", "song_length.bars": "32"}
    assert filters.pdmx_ok(row) == (True, "")
    assert filters.pdmx_flags(row) == ["licence-conflict"]


def test_chinese_music_is_tagged_not_rejected():
    from melody_model.styles import styles_for
    row = {"subset:no_license_conflict": "True", "subset:deduplicated": "True", "genres": "worldmusic",
           "is_original": "False", "composer_name": "Teresa Teng", "artist_name": "NA",
           "title": "The Moon Represents My Heart", "song_name": "NA", "subtitle": "NA", "song_length.bars": "32",
           "tags": "chinese-ballad", "groups": "NA"}
    assert filters.pdmx_ok(row) == (True, "")
    meta = {"title": row["title"], "composer": row["composer_name"], "genres": row["genres"], "tags": row["tags"]}
    assert "chinese" in styles_for("pdmx", meta)
