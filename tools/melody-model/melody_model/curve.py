"""Loss curve SVG from a training log (no plotting dependencies).

python -m melody_model.curve releases/melody-model-v1.train-log.jsonl docs/models/melody-v1-loss.svg
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

W, H, PAD = 720, 360, 48


def svg(log: Path) -> str:
    rows = [json.loads(line) for line in log.read_text(encoding="utf-8").splitlines() if line.strip()]
    train = [(r["step"], r["loss"]) for r in rows if "loss" in r]
    val = [(r["step"], r["val_loss"]) for r in rows if "val_loss" in r]
    xmax = max(s for s, _ in train + val)
    ymax = max(v for _, v in train[5:] + val) * 1.05
    ymin = min(v for _, v in train + val) * 0.95

    def pt(s, v):
        return f"{PAD + (W - 2 * PAD) * s / xmax:.1f},{H - PAD - (H - 2 * PAD) * (min(v, ymax) - ymin) / (ymax - ymin):.1f}"

    grid = []
    for i in range(5):
        v = ymin + (ymax - ymin) * i / 4
        y = H - PAD - (H - 2 * PAD) * i / 4
        grid.append(
            f'<line x1="{PAD}" y1="{y:.1f}" x2="{W - PAD}" y2="{y:.1f}" stroke="#ddd"/>'
            f'<text x="{PAD - 6}" y="{y + 4:.1f}" font-size="11" text-anchor="end">{v:.2f}</text>'
        )
    for i in range(5):
        s = xmax * i / 4
        x = PAD + (W - 2 * PAD) * i / 4
        grid.append(
            f'<text x="{x:.1f}" y="{H - PAD + 16}" font-size="11" text-anchor="middle">{int(s):,}</text>'
        )
    best = min(val, key=lambda r: r[1])
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" font-family="sans-serif">'
        f'<rect width="{W}" height="{H}" fill="white"/>'
        + "".join(grid)
        + f'<polyline fill="none" stroke="#9bb7d4" stroke-width="1" points="{" ".join(pt(s, v) for s, v in train)}"/>'
        f'<polyline fill="none" stroke="#c0392b" stroke-width="2" points="{" ".join(pt(s, v) for s, v in val)}"/>'
        f'<text x="{PAD}" y="20" font-size="13">loss per step: train (blue), validation (red); best val {best[1]:.3f} at step {best[0]:,}</text>'
        f'<text x="{W / 2}" y="{H - 8}" font-size="11" text-anchor="middle">step</text></svg>\n'
    )


if __name__ == "__main__":
    Path(sys.argv[2]).parent.mkdir(parents=True, exist_ok=True)
    Path(sys.argv[2]).write_text(svg(Path(sys.argv[1])), encoding="utf-8")
    print(sys.argv[2])
