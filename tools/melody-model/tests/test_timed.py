from melody_model import timed


def test_notes_on_beat_grid_with_legato_and_pickup():
    beats = [i * 0.5 for i in range(20)]  # 120 bpm
    # pickup 8th before bar 1 (beat 4), then detached quarters (gap < 1 beat -> legato)
    notes = [(1.75, 1.9, 67), (2.0, 2.3, 72), (2.5, 2.8, 74), (3.0, 3.3, 76), (3.5, 4.4, 77)]
    song = timed.notes_to_song(notes, beats, [4], 4, "C")
    assert song["time"] == "4/4"
    assert song["bars"][0]["RH"] == "r:2.. G4:8"
    assert song["bars"][1]["RH"] == "C5:4 D5:4 E5:4 F5:4"


def test_flat_key_spelling_and_monophony():
    beats = [i * 0.5 for i in range(12)]
    notes = [(0.0, 0.5, 70), (0.0, 0.5, 58), (0.5, 1.0, 63), (1.0, 2.0, 65)]  # chord at t=0 -> top note
    song = timed.notes_to_song(notes, beats, [0], 4, "Bb")
    assert song["bars"][0]["RH"] == "Bb4:4 Eb4:4 F4:2"


def test_estimate_beats_finds_tempo():
    period = 60 / 100  # 100 bpm, steady 8ths
    notes = [(i * period / 2, i * period / 2 + 0.2, 60 + i % 5) for i in range(40)]
    beats = timed.estimate_beats(notes)
    assert abs((beats[1] - beats[0]) - period) < 0.01


def test_local_dataset_registry(tmp_path, monkeypatch):
    """A folder of MIDI files registered in local-datasets.json becomes build jobs with its flags."""
    import json
    import mido
    from melody_model import build

    folder = tmp_path / "set" / "album1"
    folder.mkdir(parents=True)
    mf = mido.MidiFile(ticks_per_beat=480)
    tr = mido.MidiTrack()
    mf.tracks.append(tr)
    for i, p in enumerate([60, 62, 64, 65, 67, 65, 64, 62] * 3):
        tr.append(mido.Message("note_on", note=p, velocity=80, time=0))
        tr.append(mido.Message("note_off", note=p, velocity=0, time=480))
    mf.save(folder / "tune.mid")
    reg = tmp_path / "local-datasets.json"
    reg.write_text(json.dumps([{"name": "mine", "path": str(tmp_path / "set"), "source": "test", "license": "CC0",
                                "flags": ["pop"], "timing": "performed", "group_by": "folder"}]))
    monkeypatch.setattr(build, "LOCAL", reg)
    [entry] = build.load_local()
    [job] = list(build.jobs_local(entry))
    assert job[0] == "mine" and job[2] == "performed" and job[4]["flags"] == ["pop"] and job[4]["group"] == "album1"
    corpus, _, _, songs, errors = build.work(job)
    assert errors == [] and songs[0]["bars"][0]["RH"] == "C4:4 D4:4 E4:4 F4:4"


def test_local_dataset_needs_licence_fields(tmp_path, monkeypatch):
    import json
    import pytest
    from melody_model import build

    reg = tmp_path / "local-datasets.json"
    reg.write_text(json.dumps([{"name": "x", "path": "p"}]))
    monkeypatch.setattr(build, "LOCAL", reg)
    with pytest.raises(SystemExit):
        build.load_local()
