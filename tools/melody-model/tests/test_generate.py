from melody_model import tokenizer as tk
from melody_model.generate import KID, Masker, build_prefix, level_for

NS = {"course": "essentials-1", "node": "rests",
      "taught": {"accidentals": [], "durations": ["1", "2", "4", "8"], "hands_together": False, "max_interval": 5,
                 "pitches": {"RH": ["C4", "D4", "E4", "F4", "G4"]}, "polyphony": {"RH": 1}, "rest_durations": ["4"],
                 "rests": True, "times": ["4/4"]},
      "spec": {"bars": [8, 8], "bpm": [72, 88], "hands": "RH", "time": "4/4", "required": [{"rest": True}]}}


def test_prefix_is_a_valid_spec():
    steps = build_prefix(NS, "C", 8, "4/4", ["folk"], 1)
    k = [tk.FIELDS["kind"][s[0]] for s in steps]
    assert k[:3] == ["BOS", "SPEC", "STYLE_folk"] and "PAT_rest" in k and k[-1] == "SPEC_END"


def test_masker_walks_the_grammar_and_fills_bars():
    m = Masker(NS, 2, "4/4")
    seq = []
    for _ in range(6):
        k = m.kinds()[0]
        seq.append(k)
        m.advance(k, tk.NONE, tk.NONE)
    assert seq == ["SEC_A", "CAD_STABLE", "CON_UP", "SEC_A", "CAD_STABLE", "CON_UP"]
    assert m.kinds() == ["PLAN_END"]
    for k in ("PLAN_END", "BAR", "RH"):
        m.advance(k, tk.NONE, tk.NONE)
    assert set(m.kinds()) == {"NOTE", "REST"}
    assert m.durs_for("NOTE") == ["1", "2", "4", "8"] and m.durs_for("REST") == ["4"]
    m.advance("NOTE", "C4", "2")
    assert m.durs_for("NOTE") == ["2", "4", "8"]
    assert m.pitches_for("NOTE") == ["C4", "D4", "E4", "F4"]  # G4 is a 7-semitone leap, taught up to 5 semitones
    m.advance("NOTE", "D4", "2")
    assert m.kinds() == ["BAR"]


def test_level_for_beginner_set():
    assert level_for(NS["taught"]) <= 2


import json
import random
import subprocess

import pytest

from melody_model import generate


def test_end_to_end_sample_is_a_valid_song(tmp_path):
    torch = pytest.importorskip("torch")
    from melody_model.model import CompoundGPT, Config
    torch.manual_seed(0)
    model = CompoundGPT(Config(layers=1, d=32, heads=2, ctx=1024, dropout=0.0)).eval()  # untrained: masks alone must keep it valid
    prefix = build_prefix(NS, "C", 4, "4/4", [], 1)
    for seed in range(3):
        steps, _ = generate.sample_tune(model, prefix, Masker(NS, 4, "4/4"), random.Random(seed), 1.0, torch, "cpu")
        assert tk.FIELDS["kind"][steps[-1][0]] == "END"
        song = generate.to_song(tk.decode(steps), NS, seed, "test", 1, 80)
        assert len(song["bars"]) == 4 and all(b["RH"] for b in song["bars"])
        f = tmp_path / f"{seed}.json"
        f.write_text(json.dumps(song), encoding="utf-8")
    try:
        cli = generate.content_cli()
    except SystemExit:
        pytest.skip("content CLI not built")
    files = sorted(tmp_path.glob("*.json"))
    errors = generate.rubric_gate(cli, "essentials-1/rests", files)  # parses with core Song::from_json
    assert set(errors) == {str(f) for f in files}
    assert not any("not a song" in e for v in errors.values() for e in v)


class Done:
    def __init__(self, rc, out="", err=""):
        self.returncode, self.stdout, self.stderr = rc, out, err


def test_rubric_gate_fails_closed(tmp_path, monkeypatch):
    f = tmp_path / "a.json"
    for result in (Done(0, ""), Done(2, "", "boom"), Done(1, json.dumps({"other.json": []}))):
        monkeypatch.setattr(generate.subprocess, "run", lambda *a, r=result, **k: r)
        with pytest.raises(SystemExit):
            generate.rubric_gate(["content"], "c/n", [f])


def test_similarity_gate_fails_closed_and_parses(tmp_path, monkeypatch):
    f = tmp_path / "a.json"
    f.write_text(json.dumps({"id": "gen-1"}), encoding="utf-8")
    monkeypatch.setattr(generate.subprocess, "run", lambda *a, **k: Done(0, "corpus: 3 melodies\n"))
    with pytest.raises(SystemExit, match="no result"):
        generate.similarity_gate(["content"], [f])
    monkeypatch.setattr(generate.subprocess, "run", lambda *a, **k: Done(1, "SIMILAR gen-1 (12 notes)\n"))
    assert generate.similarity_gate(["content"], [f]) == {"gen-1": True}
    monkeypatch.setattr(generate.subprocess, "run", lambda *a, **k: Done(2, "", "bad corpus"))
    with pytest.raises(SystemExit):
        generate.similarity_gate(["content"], [f])


def test_leap_mask_never_falls_back():
    m = Masker({**NS, "taught": {**NS["taught"], "pitches": {"RH": ["C4", "C5"]}}}, 1, "4/4")
    for k in ("SEC_A", "CAD_STABLE", "CON_UP", "PLAN_END", "BAR", "RH"):
        m.advance(k, tk.NONE, tk.NONE)
    m.advance("NOTE", "C4", "4")
    assert m.pitches_for("NOTE") == ["C4"]  # C5 is 12 semitones away, taught up to 5
