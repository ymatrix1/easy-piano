import json
import random
from pathlib import Path

from melody_model import samples
from melody_model import tokenizer as tk
from melody_model.labels import plan

ROOT = Path(__file__).resolve().parents[3]


def tune_from(name, **extra):
    s = json.loads((ROOT / "content" / "songs" / f"{name}.json").read_text(encoding="utf-8"))
    bars = [{h: b[h] for h in ("RH", "LH") if h in b} for b in s["bars"]]
    t = {"corpus": "own", "time": s["time"], "key": s["key"], "bars": bars, "styles": ["children"]}
    t["plan"] = plan(t)
    t.update(extra)
    return t


def kinds(steps):
    return [tk.FIELDS["kind"][s[0]] for s in steps]


def test_left_to_right_sample_decodes_and_loss_starts_after_spec():
    t = tune_from("ode-to-joy")
    steps, loss_from = samples.make_sample(t, random.Random(1), fim_p=0.0, style_drop_p=0.0)
    k = kinds(steps)
    assert k[0] == "BOS" and k[1] == "SPEC" and "STYLE_children" in k and "SRC_own" in k
    assert k[loss_from] == "PLAN" and k[loss_from - 1] == "SPEC_END"
    song = tk.decode(steps)
    assert len(song["bars"]) == k.count("BAR")
    assert k.count("SEC_A") >= 1  # window plans are relettered from A


def test_fim_sample_layout():
    t = tune_from("ode-to-joy")
    steps, loss_from = samples.make_sample(t, random.Random(2), fim_p=1.0, style_drop_p=1.0)
    k = kinds(steps)
    assert not any(x.startswith("STYLE_") for x in k)
    i_pre, i_suf, i_mid = k.index("FIM_PRE"), k.index("FIM_SUF"), k.index("FIM_MID")
    assert i_pre < i_suf < i_mid and loss_from == i_mid + 1 and k[-1] == "END"
    mid_bars = k[i_mid:].count("BAR")
    assert 1 <= mid_bars <= samples.MAX_FIM_BARS


def test_transposition_changes_key_and_stays_in_vocab():
    t = tune_from("ode-to-joy")
    keys = {tk.decode(samples.make_sample(t, random.Random(s), fim_p=0.0)[0])["key"] for s in range(20)}
    assert len(keys) > 3


def test_reletter():
    assert samples.reletter([("C", "OPEN", "UP"), ("A", "OPEN", "UP"), ("C", "STABLE", "FLAT")]) == [
        ("A", "OPEN", "UP"),
        ("B", "OPEN", "UP"),
        ("A", "STABLE", "FLAT"),
    ]


def test_samples_fit_context():
    t = tune_from("ode-to-joy")
    for s in range(30):
        steps, _ = samples.make_sample(t, random.Random(s), ctx=1024)
        assert len(steps) <= 1024
