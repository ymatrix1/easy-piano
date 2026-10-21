import json
import shutil
import subprocess
import tempfile
from pathlib import Path

import numpy as np
import pytest

from eval_model import Params, decode

NODE = shutil.which("node")


@pytest.mark.skipif(NODE is None, reason="node not installed")
def test_js_decoder_matches_python():
    rng = np.random.default_rng(3)
    T = 400
    on = rng.random((T, 88)).astype(np.float32) ** 6  # mostly low, some spikes
    fr = rng.random((T, 88)).astype(np.float32) ** 0.5
    for k, g in [(39, 50), (43, 50), (60, 120), (39, 140), (70, 200), (70, 203)]:
        on[g, k] = 0.95  # clear note-ons, one retrigger inside the refractory time
    exp_set = {60: {39 + 21, 43 + 21}, 61: {60 + 21}}
    expected = [sorted(exp_set[g // 100 % 2 + 60]) if 40 < g < 160 else [] for g in range(T)]
    p = Params(calib=0.01)
    want = decode(on, fr, lambda t: set(expected[min(round((t * 16000 - 512) / 256) - 3, T - 1)]), p)
    with tempfile.TemporaryDirectory() as d:
        d = Path(d)
        params = {
            "thrExp": p.thr_exp,
            "thrUnexp": p.thr_unexp,
            "frameThr": p.frame_thr,
            "hold": p.hold,
            "refractory": p.refractory,
            "calib": p.calib,
        }
        (d / "in.json").write_text(
            json.dumps({"on": on.tolist(), "fr": fr.tolist(), "expected": expected, "params": params})
        )
        subprocess.run([NODE, str(Path(__file__).parent / "decoder_parity.mjs"), str(d)], check=True)
        got = json.loads((d / "out.json").read_text())
    assert len(want) == len(got) > 0
    assert sorted((round(t, 5), p_) for t, p_, _ in want) == sorted((round(t, 5), p_) for p_, t, _ in got)
