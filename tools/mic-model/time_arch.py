"""MACs per streaming step and an untrained ONNX per architecture (runs/arch/), for timing in the browser:
browser_check.py serves them at /arch/<name>; open /check.html?model=/arch/<name>.

Usage: uv run python time_arch.py <name> c1 c2 c3 ct
"""

import json
import sys
from pathlib import Path

import torch

from export_onnx import Step
from features import NBANDS
from model import FRONT_CTX, PianoNet


def macs(m):
    tot = 0

    def hook(mod, i, o):
        nonlocal tot
        k = mod.kernel_size[0] * mod.kernel_size[1]
        tot += o.numel() * mod.in_channels * k // mod.groups

    for x in m.modules():
        if isinstance(x, torch.nn.Conv2d):
            x.register_forward_hook(hook)
    m.step(torch.zeros(1, FRONT_CTX, NBANDS), *[torch.zeros(s) for s in m.state_shapes()])
    return tot


if __name__ == "__main__":
    name = sys.argv[1]
    c = [int(x) for x in sys.argv[2:6]]
    m = PianoNet(*c).eval()
    print(name, c, sum(p.numel() for p in m.parameters()), "params", f"{macs(m) / 1e6:.2f} MMAC/step")
    out = Path(__file__).parent / "runs" / "arch" / f"{name}.onnx"
    shapes = m.state_shapes()
    torch.onnx.export(
        Step(m),
        (torch.rand(1, FRONT_CTX, NBANDS), *[torch.rand(s) for s in shapes]),
        str(out),
        input_names=["ctx"] + [f"state{i}" for i in range(len(shapes))],
        output_names=["onset", "frame"] + [f"new_state{i}" for i in range(len(shapes))],
        opset_version=17,
        dynamo=False,
    )
    out.with_suffix(".json").write_text(json.dumps({"states": [list(s) for s in shapes]}))
