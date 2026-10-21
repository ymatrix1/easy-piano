import importlib.util
import json
from pathlib import Path

import pytest
from conftest import need

torch = pytest.importorskip("torch")  # train extra; CI installs the base deps only

from melody_model.model import CompoundGPT, Config  # noqa: E402
from melody_model.tokenizer import FIELDS, encode_song  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]


@pytest.fixture(scope="module", autouse=True)
def _ort():
    need(importlib.util.find_spec("onnxruntime") is not None, "onnxruntime")


def _export(cfg: Config, tmp: Path):
    from melody_model.export import export

    torch.manual_seed(0)
    m = CompoundGPT(cfg).eval()
    return m, export(m, tmp)


@pytest.fixture(scope="module")
def exported(tmp_path_factory):
    out = tmp_path_factory.mktemp("onnx")
    m, sizes = _export(Config(layers=2, d=64, heads=4, ctx=256, dropout=0.1), out)
    return m, out, sizes


def _steps(*names):
    songs = [
        encode_song(json.loads((ROOT / "content" / "songs" / f"{n}.json").read_text(encoding="utf-8")))
        for n in names
    ]
    t = min(len(s) for s in songs)
    return torch.tensor([s[:t] for s in songs])


def _split(steps):
    return next(i for i, s in enumerate(steps[0].tolist()) if s[0] == FIELDS["kind"].index("SPEC_END")) + 1


def test_writes_fp32_and_int8(exported):
    _, out, sizes = exported
    assert set(sizes) == {"decoder.onnx", "decoder.int8.onnx", "heads.onnx", "heads.int8.onnx"}
    assert sizes["decoder.int8.onnx"] < sizes["decoder.onnx"]
    assert (out / "vocab.json").exists()


def test_export_leaves_model_in_eval(exported):
    assert not exported[0].training


def test_kv_cache_parity_batch_of_two(exported):
    from melody_model.export import parity

    m, out, _ = exported
    steps = _steps("ode-to-joy", "twinkle-twinkle")
    res = parity(m, out, steps, _split(steps))
    # fp32: the cache path is the same maths as the full sequence. int8 bound is for this toy model only;
    # the shipped checkpoint is judged by validation NLL (docs/specs/melody-model.md "Browser export").
    assert res["fp32"]["max_abs"] < 1e-4 and res["fp32"]["top1"] == 1.0
    assert res["int8"]["max_prob_diff"] < 0.05 and res["int8"]["top1"] > 0.9


def test_nll_matches_torch_for_fp32(exported):
    from melody_model.export import nll

    m, out, _ = exported
    steps = _steps("ode-to-joy")
    res = nll(m, out, [(steps, _split(steps))])
    assert abs(res["fp32"]["total"] - res["torch"]["total"]) < 1e-3
    assert res["steps"] == steps.shape[1] - _split(steps)


@pytest.mark.slow
def test_real_config_parity(tmp_path):
    """Shipped shape (6 layers, d 384, 11.09M params), random weights: export, cache parity, int8 NLL."""
    from melody_model.export import nll, parity

    m, sizes = _export(Config(), tmp_path)
    assert m.n_params() == 11_092_620
    assert 10e6 < sizes["decoder.int8.onnx"] < 14e6
    steps = _steps("ode-to-joy", "twinkle-twinkle")
    res = parity(m, tmp_path, steps, _split(steps))
    assert res["fp32"]["max_abs"] < 1e-4 and res["fp32"]["top1"] == 1.0
    q = nll(m, tmp_path, [(steps[:1], _split(steps))])
    assert abs(q["fp32"]["total"] - q["torch"]["total"]) < 1e-3
    assert abs(q["int8"]["total"] - q["fp32"]["total"]) / q["fp32"]["total"] < 0.02
