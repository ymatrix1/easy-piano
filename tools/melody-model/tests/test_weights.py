import json

import pytest

torch = pytest.importorskip("torch")
pytest.importorskip("safetensors")

from melody_model import weights  # noqa: E402
from melody_model.model import CompoundGPT, Config  # noqa: E402


def test_safetensors_round_trip_and_hash_check(tmp_path, monkeypatch):
    torch.manual_seed(0)
    cfg = Config(layers=1, d=32, heads=2, ctx=64, dropout=0.0)
    model = CompoundGPT(cfg).eval()
    run = tmp_path / "data" / "melody" / "runs" / "t"
    run.mkdir(parents=True)
    torch.save(
        {
            "model": model.state_dict(),
            "config": cfg.to_dict(),
            "step": 7,
            "val_loss": 1.5,
            "meta": {
                "dataset_sha256": "d",
                "vocab_sha256": "v",
                "params": model.n_params(),
                "torch": "x",
                "gate": {"approver_words": "private"},
                "args": {"out": "C:/somewhere"},
            },
        },
        run / "ckpt.pt",
    )
    monkeypatch.setattr(weights, "ROOT", tmp_path)
    st, cj = weights.export("t", tmp_path / "out")
    cfg_json = json.loads(cj.read_text(encoding="utf-8"))
    assert "gate" not in cfg_json and "args" not in cfg_json  # run metadata is not published
    loaded, _ = weights.load(st)
    x = torch.randint(0, 6, (1, 10, 4))
    with torch.no_grad():
        a = loaded.heads_logits(loaded.hidden(x), x)
        b = model.heads_logits(model.hidden(x), x)
    assert all(torch.equal(p, q) for p, q in zip(a, b))
    st.write_bytes(st.read_bytes()[:-1] + b"\0")
    with pytest.raises(SystemExit, match="sha256"):
        weights.load(st)
