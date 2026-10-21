import json
from pathlib import Path

import pytest
import torch

pytest.importorskip("onnxruntime")

from melody_model.export import export, parity
from melody_model.model import CompoundGPT, Config
from melody_model.tokenizer import FIELDS, encode_song

ROOT = Path(__file__).resolve().parents[3]


@pytest.fixture(scope="module")
def exported(tmp_path_factory):
    torch.manual_seed(0)
    m = CompoundGPT(Config(layers=2, d=64, heads=4, ctx=256, dropout=0.1)).eval()
    out = tmp_path_factory.mktemp("onnx")
    sizes = export(m, out)
    return m, out, sizes


def _steps(*names):
    songs = [encode_song(json.loads((ROOT / "content" / "songs" / f"{n}.json").read_text(encoding="utf-8"))) for n in names]
    t = min(len(s) for s in songs)
    return torch.tensor([s[:t] for s in songs])


def test_writes_fp32_and_int8(exported):
    _, out, sizes = exported
    assert set(sizes) == {"decoder.onnx", "decoder.int8.onnx", "heads.onnx", "heads.int8.onnx"}
    assert sizes["decoder.int8.onnx"] < sizes["decoder.onnx"]
    assert (out / "vocab.json").exists()


def test_export_leaves_model_in_eval(exported):
    assert not exported[0].training


def test_kv_cache_parity_batch_of_two(exported):
    m, out, _ = exported
    steps = _steps("ode-to-joy", "twinkle-twinkle")
    split = next(i for i, s in enumerate(steps[0].tolist()) if s[0] == FIELDS["kind"].index("SPEC_END")) + 1
    res = parity(m, out, steps, split)
    assert res["fp32"]["max_abs"] < 1e-4 and res["fp32"]["top1"] == 1.0
    assert res["int8"]["max_prob_diff"] < 0.05 and res["int8"]["top1"] > 0.9
