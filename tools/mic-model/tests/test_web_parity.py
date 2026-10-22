import shutil
import subprocess
import tempfile
from pathlib import Path

import numpy as np
import pytest
import torch
from scipy.signal import resample_poly

from features import HOP, log_bands

NODE = shutil.which("node")


@pytest.mark.skipif(NODE is None, reason="node not installed")
def test_js_frontend_and_resampler_match_python():
    rng = np.random.default_rng(0)
    t = np.arange(16000 * 3) / 16000
    a16 = (
        0.2 * np.sin(2 * np.pi * 440 * t)
        + 0.1 * np.sin(2 * np.pi * 1318 * t) * (t > 1)
        + 0.01 * rng.standard_normal(len(t))
    ).astype(np.float32)
    t48 = np.arange(48000 * 2) / 48000
    a48 = (0.3 * np.sin(2 * np.pi * 330 * t48) + 0.2 * np.sin(2 * np.pi * 3000 * t48)).astype(np.float32)
    with tempfile.TemporaryDirectory() as d:
        d = Path(d)
        a16.tofile(d / "audio16.f32")
        a48.tofile(d / "audio48.f32")
        subprocess.run([NODE, str(Path(__file__).parent / "web_parity.mjs"), str(d)], check=True)
        js = np.fromfile(d / "bands.f32", dtype=np.float32).reshape(-1, 264)
        rs = np.fromfile(d / "rs.f32", dtype=np.float32)
    ref = log_bands(torch.from_numpy(a16)[None])[0].numpy()
    n = len(js)
    assert n >= len(a16) // HOP - 3
    assert np.abs(js - ref[:n]).max() < 2e-3
    want = resample_poly(a48, 1, 3)
    m = min(len(rs), len(want)) - 20
    assert np.abs(rs[10 : m + 10] - want[10 : m + 10]).max() < 0.02
