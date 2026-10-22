"""Exports the streaming step of PianoNet to ONNX and checks it against PyTorch.

Inputs : ctx [1, FRONT_CTX, 264] (last 7 log-band frames, newest last), state0..state4
Outputs: onset [1, 88], frame [1, 88] (probabilities, for the frame LOOKAHEAD behind
         the newest), state0..state4 (feed back; zero them for the first
         LOOKAHEAD steps, see tests/test_model.py).

Usage: uv run python export_onnx.py runs/v1/model.pt ../../app/web/models/piano_net.onnx
"""

import json
import sys
from pathlib import Path

import numpy as np
import onnx
import onnxruntime as ort
import torch

from eval_model import load_model
from features import NBANDS
from model import FRONT_CTX, LOOKAHEAD


class Step(torch.nn.Module):
    def __init__(self, m):
        super().__init__()
        self.m = m

    def forward(self, ctx, *states):
        o, f, *new = self.m.step(ctx, *states)
        return (torch.sigmoid(o), torch.sigmoid(f), *new)


def main(ckpt, out):
    m = load_model(ckpt)
    shapes = m.state_shapes()
    ctx = torch.rand(1, FRONT_CTX, NBANDS)
    states = [torch.rand(s) for s in shapes]
    in_names = ["ctx"] + [f"state{i}" for i in range(len(shapes))]
    out_names = ["onset", "frame"] + [f"new_state{i}" for i in range(len(shapes))]
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    torch.onnx.export(
        Step(m),
        (ctx, *states),
        out,
        input_names=in_names,
        output_names=out_names,
        opset_version=17,
        dynamo=False,
    )
    onnx.checker.check_model(onnx.load(out))
    sess = ort.InferenceSession(out, providers=["CPUExecutionProvider"])
    got = sess.run(None, {n: t.numpy() for n, t in zip(in_names, [ctx, *states])})
    with torch.no_grad():
        want = Step(m)(ctx, *states)
    err = max(np.abs(g - w.numpy()).max() for g, w in zip(got, want))
    ops = sorted({n.op_type for n in onnx.load(out).graph.node})
    print(f"{out}: {Path(out).stat().st_size / 1024:.0f} KiB, max |onnx - torch| = {err:.2e}, ops = {ops}")
    assert err < 1e-4
    meta = {"states": [list(s) for s in shapes], "lookahead": LOOKAHEAD, "frontCtx": FRONT_CTX}
    Path(out).with_suffix(".json").write_text(json.dumps(meta))


if __name__ == "__main__":
    main(*sys.argv[1:3])
