import json
import random
from pathlib import Path

import pytest

torch = pytest.importorskip("torch")

from melody_model import tokenizer as tk  # noqa: E402
from melody_model.labels import plan  # noqa: E402
from melody_model.model import FIELD_SIZES, CompoundGPT, Config  # noqa: E402
from melody_model.samples import make_sample  # noqa: E402
from melody_model.train import collate  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]


def batch(n=4, seed=0):
    s = json.loads((ROOT / "content" / "songs" / "ode-to-joy.json").read_text(encoding="utf-8"))
    t = {
        "corpus": "own",
        "time": s["time"],
        "key": s["key"],
        "styles": ["children"],
        "bars": [{h: b[h] for h in ("RH", "LH") if h in b} for b in s["bars"]],
    }
    t["plan"] = plan(t)
    rng = random.Random(seed)
    return collate([make_sample(t, rng) for _ in range(n)], torch)


def test_collate_masks_and_pads():
    x, y, m = batch()
    assert x.shape == y.shape and x.shape[-1] == 4 and m.shape == x.shape[:2]
    assert (m.sum(1) > 0).all()
    assert not m[x[..., 0] == tk.FIELDS["kind"].index("PAD")].any()


def test_forward_shapes_and_overfit():
    torch.manual_seed(0)
    model = CompoundGPT(Config(layers=2, d=64, heads=4, ctx=1024, dropout=0.0))
    x, y, m = batch()
    logits = model.heads_logits(model.hidden(x), y)
    assert [lg.shape[-1] for lg in logits] == list(FIELD_SIZES)
    opt = torch.optim.AdamW(model.parameters(), lr=3e-3)
    first = None
    for _ in range(60):
        loss, _ = model(x, y, m)
        first = first or loss.item()
        opt.zero_grad()
        loss.backward()
        opt.step()
    assert loss.item() < first * 0.3


def test_causal():
    """Changing a later step must not change earlier hidden states."""
    model = CompoundGPT(Config(layers=2, d=64, heads=4, ctx=1024, dropout=0.0)).eval()
    x, _, _ = batch(1)
    h1 = model.hidden(x)
    x2 = x.clone()
    x2[0, -1, 1] = (x2[0, -1, 1] + 1) % FIELD_SIZES[1]
    h2 = model.hidden(x2)
    assert torch.allclose(h1[0, :-1], h2[0, :-1], atol=1e-5)
