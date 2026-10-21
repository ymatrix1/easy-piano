"""The browser decoder (web/melody.js) against the Python tokenizer, run through Node (web/check.mjs).

What this checks: encodeSpec == encode_spec, decode == tokenizer.decode on every song, and that masked generation
(driven by random logits) only produces sequences the Python decoder accepts with full bars, in range, allowed
durations and the spec's hands. It does not check that JS and Python pick the same ids: the RNGs differ
(mulberry32 vs torch), and the Python generator (generate.py) uses node masks, not these spec masks."""

import json
import shutil
import subprocess
from pathlib import Path

import pytest
from conftest import need

from melody_model.notation import DURATIONS, dur_beats, parse_hand
from melody_model.tokenizer import FIELDS, Spec, decode, encode_song, encode_spec, step

ROOT = Path(__file__).resolve().parents[3]
WEB = Path(__file__).resolve().parents[1] / "web"
NODE = shutil.which("node")

PATTERNS = [p for f in sorted((ROOT / "content" / "skill-specs").glob("*.json"))
            for node in json.loads(f.read_text(encoding="utf-8"))["nodes"] for p in node.get("required", [])]

GEN_SPECS = [
    {"time": "4/4", "key": "C", "bars": 8, "range_lo": "C4", "range_hi": "G4", "durs": ["2", "4"], "hands": "RH"},
    {"time": "3/4", "key": "G", "bars": 8, "range_lo": "D4", "range_hi": "D5", "durs": ["2.", "4", "8"], "hands": "RH", "level": 2},
    {"time": "6/8", "key": "F", "bars": 4, "range_lo": "F3", "range_hi": "C5", "durs": ["4.", "4", "8"], "hands": "BOTH", "styles": ["folk"]},
    {"time": "2/4", "key": "Am", "bars": 6, "range_lo": "A2", "range_hi": "E3", "durs": ["4", "8", "16"], "hands": "LH"},
    {"time": "4/4", "key": "D", "bars": 8, "range_lo": "D4", "range_hi": "A5", "durs": ["1", "2", "4", "8"], "hands": "BOTH",
     "patterns": [{"rhythm": "8"}, {"chord": True, "hand": "LH"}]},
    # practice mode (content practice-pack): taught-set masks
    {"time": "4/4", "key": "C", "bars": 8, "range_lo": "C4", "range_hi": "G4", "durs": ["2", "4"], "hands": "RH",
     "mask": {"pitches": {"RH": ["C4", "D4", "E4", "G4"]}, "max_leap": 2, "poly": {"RH": 1}, "rest_durs": ["2"]}},
    {"time": "4/4", "key": "C", "bars": 8, "range_lo": "C3", "range_hi": "G3", "durs": ["1", "2", "4", "4.", "8"], "hands": "LH",
     "mask": {"pitches": {"LH": ["C3", "D3", "E3", "F3", "G3"]}, "max_leap": 7, "poly": {"LH": 3}, "rest_durs": ["2", "4"]}},
]


def _spec(d: dict) -> Spec:
    durs = sorted(d["durs"], key=DURATIONS.index)  # as spec_from_song; melody.js sorts too
    return Spec(d["time"], d["key"], d["bars"], d["range_lo"], d["range_hi"], durs, d["hands"],
                patterns=d.get("patterns"), styles=d.get("styles"), level=d.get("level"))


@pytest.fixture(scope="module")
def node_run(tmp_path_factory):
    need(NODE is not None, "node")
    tmp = tmp_path_factory.mktemp("web")
    specs = GEN_SPECS + [dict(GEN_SPECS[0], patterns=[p]) for p in PATTERNS]
    songs = []
    for f in sorted((ROOT / "content" / "songs").glob("*.json")):
        song = json.loads(f.read_text(encoding="utf-8"))
        try:
            steps = encode_song(song)
        except ValueError:
            continue  # notation the model does not cover (same skip as test_tokenizer)
        songs.append({"name": f.stem, "steps": [list(s) for s in steps], "decoded": decode(steps)})
    fixture = {
        "vocab": {n: list(v) for n, v in FIELDS.items()},
        "specs": [{"spec": s, "steps": [list(x) for x in [step("BOS")] + encode_spec(_spec(s))]} for s in specs],
        "songs": songs,
        "gen_specs": GEN_SPECS,
    }
    (tmp / "fixture.json").write_text(json.dumps(fixture), encoding="utf-8")
    r = subprocess.run([NODE, str(WEB / "check.mjs"), str(tmp / "fixture.json"), str(tmp / "out.json")],
                       capture_output=True, text=True)
    print(r.stdout, r.stderr)
    assert r.returncode == 0, r.stderr
    return fixture, json.loads((tmp / "out.json").read_text(encoding="utf-8"))


def test_spec_and_decode_match_python(node_run):
    fixture, _ = node_run
    assert len(fixture["songs"]) > 20 and len(fixture["specs"]) > len(GEN_SPECS)


def test_masked_generation_obeys_spec(node_run):
    _, generated = node_run
    assert len(generated) == 4 * len(GEN_SPECS)
    for g in generated:
        spec, song = g["spec"], decode([tuple(s) for s in g["steps"]])
        assert song == g["decoded"]  # JS and Python decoders agree on model output
        assert song["time"] == spec["time"] and song["key"] == spec["key"] and len(song["bars"]) == spec["bars"]
        num, den = map(int, spec["time"].split("/"))
        hands = ["RH", "LH"] if spec["hands"] == "BOTH" else [spec["hands"]]
        lo, hi = (parse_hand(f"{spec[k]}:4")[0].pitches[0].midi for k in ("range_lo", "range_hi"))
        for bar in song["bars"]:
            assert sorted(bar) == sorted(hands)
            for h in hands:
                events = parse_hand(bar[h])
                assert abs(sum(dur_beats(e.dur, den) for e in events) - num) < 1e-9  # exact bar fill
                mask = spec.get("mask")
                for e in events:
                    assert e.dur in (mask["rest_durs"] if mask and e.is_rest else spec["durs"])
                    if mask:
                        assert {p.name for p in e.pitches} <= set(mask["pitches"][h]) and len(e.pitches) <= mask["poly"][h]
                        assert not e.tie and not e.fingers
                    assert all(lo <= p.midi <= hi for p in e.pitches)
                    assert [p.midi for p in e.pitches] == sorted({p.midi for p in e.pitches})  # chords low to high
        if spec.get("mask"):
            h = hands[0]
            line = [e.pitches[0].midi for bar in song["bars"] for e in parse_hand(bar[h]) if not e.is_rest]
            assert all(abs(a - b) <= spec["mask"]["max_leap"] for a, b in zip(line, line[1:]))
