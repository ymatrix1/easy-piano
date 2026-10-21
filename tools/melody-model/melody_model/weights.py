"""Publishable weights: safetensors (tensors only, no pickle) plus a clean config JSON.

    python -m melody_model.weights export --run base1 --out data/melody/release/melody-model-v1
    python -m melody_model.weights check data/melody/release/melody-model-v1/melody-base1.safetensors

The training checkpoint (`ckpt.pt`) is a pickle with run metadata (paths, gate
record); it is never published. `load` rebuilds the model from the two
published files, no `torch.load` involved.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

from .download import ROOT

CONFIG_KEYS = ("dataset_sha256", "vocab_sha256", "params", "torch")


def export(run: str, out: Path) -> tuple[Path, Path]:
    import torch
    from safetensors.torch import save_file

    ck = torch.load(
        ROOT / "data" / "melody" / "runs" / run / "ckpt.pt", map_location="cpu", weights_only=False
    )
    tensors = {k: v.contiguous() for k, v in ck["model"].items()}
    out.mkdir(parents=True, exist_ok=True)
    st = out / f"melody-{run}.safetensors"
    save_file(tensors, str(st), metadata={"format": "pt", "run": run})
    meta = ck["meta"]
    cfg = {
        "run": run,
        "architecture": "CompoundGPT (tools/melody-model/melody_model/model.py)",
        "model": ck["config"],
        "step": ck["step"],
        "val_loss": ck["val_loss"],
        **{k: meta[k] for k in CONFIG_KEYS},
        "safetensors_sha256": hashlib.sha256(st.read_bytes()).hexdigest(),
        "license": "CC-BY-SA-4.0 (D24)",
    }
    cj = out / f"melody-{run}.config.json"
    cj.write_text(json.dumps(cfg, indent=1) + "\n", encoding="utf-8", newline="\n")
    return st, cj


def load(safetensors_path: Path, config_path: Path | None = None, device: str = "cpu"):
    """CompoundGPT from published files; checks the config's hash of the weights."""
    from safetensors.torch import load_file

    from .model import CompoundGPT, Config

    config_path = config_path or safetensors_path.with_name(
        safetensors_path.name.replace(".safetensors", ".config.json")
    )
    cfg = json.loads(config_path.read_text(encoding="utf-8"))
    if hashlib.sha256(safetensors_path.read_bytes()).hexdigest() != cfg["safetensors_sha256"]:
        raise SystemExit(f"{safetensors_path}: sha256 does not match {config_path}")
    model = CompoundGPT(Config(**cfg["model"])).to(device)
    model.load_state_dict(load_file(str(safetensors_path), device=device))
    return model.eval(), cfg


def main(argv):
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    e = sub.add_parser("export")
    e.add_argument("--run", required=True)
    e.add_argument("--out", required=True)
    c = sub.add_parser("check")
    c.add_argument("path")
    args = ap.parse_args(argv)
    if args.cmd == "export":
        for p in export(args.run, Path(args.out)):
            print(p)
    else:
        model, cfg = load(Path(args.path))
        print(f"ok: {cfg['run']} step {cfg['step']}, {model.n_params():,} params")


if __name__ == "__main__":
    main(sys.argv[1:])
