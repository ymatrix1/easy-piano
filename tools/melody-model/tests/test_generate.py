from melody_model import tokenizer as tk
from melody_model.generate import KID, Masker, build_prefix, level_for

NS = {"course": "essentials-1", "node": "rests",
      "taught": {"accidentals": [], "durations": ["1", "2", "4", "8"], "hands_together": False, "max_interval": 4,
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
    assert m.pitches_for("NOTE") == ["C4", "D4", "E4", "F4"]  # G4 is a 7-semitone leap, taught up to a fourth
    m.advance("NOTE", "D4", "2")
    assert m.kinds() == ["BAR"]


def test_level_for_beginner_set():
    assert level_for(NS["taught"]) <= 2
