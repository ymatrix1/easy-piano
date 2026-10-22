"""Trains PianoNet on endless synthetic + MAESTRO clips (gen.py).

Usage: uv run python train.py --name v1 [--steps 20000] [--width 1]
Held out: the YDP piano and the MAESTRO test split (validation here; the fixture
set in tools/mic-fixtures is scored by eval_model.py).
"""

import os

for _v in ("OMP_NUM_THREADS", "MKL_NUM_THREADS", "OPENBLAS_NUM_THREADS"):
    os.environ.setdefault(_v, "1")  # data workers must not each spawn a BLAS thread pool

import argparse
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn.functional as F
from torch.utils.data import DataLoader

import gen
from features import log_bands
from model import LOOKAHEAD, PianoNet

RUNS = Path(__file__).parent / "runs"


def losses(model, audio, onset, weight, frame, pos_weight=4.0):
    x = log_bands(audio)
    lo, lf = model.forward_seq(x)
    keep = torch.ones(lo.shape[1], device=lo.device)
    keep[-LOOKAHEAD:] = 0  # these frames never get their full look-ahead when streaming
    k = keep[None, :, None]
    bce_o = F.binary_cross_entropy_with_logits(
        lo, onset, weight=weight * k, pos_weight=torch.tensor(pos_weight, device=lo.device), reduction="sum"
    ) / (k.sum() * lo.shape[0])
    bce_f = F.binary_cross_entropy_with_logits(lf, frame, weight=k.expand_as(frame), reduction="sum") / (
        k.sum() * lo.shape[0]
    )
    return bce_o, bce_f, lo, lf


@torch.no_grad()
def onset_f1(lo, onset, thr=0.5, tol=2):
    p = torch.sigmoid(lo)[:, :-LOOKAHEAD]
    t = onset[:, :-LOOKAHEAD]
    pk = (p >= thr) & (p >= F.pad(p, (0, 0, 1, 0))[:, :-1]) & (p > F.pad(p, (0, 0, 0, 1))[:, 1:])
    near_t = (
        F.max_pool1d(t.permute(0, 2, 1).reshape(-1, 1, t.shape[1]), 2 * tol + 1, 1, tol)
        .reshape(t.permute(0, 2, 1).shape)
        .permute(0, 2, 1)
        > 0
    )
    near_p = (
        F.max_pool1d(pk.float().permute(0, 2, 1).reshape(-1, 1, pk.shape[1]), 2 * tol + 1, 1, tol)
        .reshape(pk.permute(0, 2, 1).shape)
        .permute(0, 2, 1)
        > 0
    )
    tp_p = (pk & near_t).sum().item()
    tp_t = ((t > 0) & near_p).sum().item()
    return tp_p, pk.sum().item(), tp_t, (t > 0).sum().item()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", default="v2")
    ap.add_argument("--steps", type=int, default=15000)
    ap.add_argument("--batch", type=int, default=32)
    ap.add_argument("--lr", type=float, default=2e-3)
    ap.add_argument("--workers", type=int, default=9)
    ap.add_argument(
        "--configs",
        nargs="+",
        default=["16,24,32,32", "16,16,24,24"],
        help="channel widths c1,c2,c3,ct; one model per config, trained on the same batches",
    )
    ap.add_argument("--train-pianos", nargs="+", default=["salamander", "kw"])
    ap.add_argument("--no-maestro", action="store_true", help="synthetic piano only (no CC BY-NC-SA audio)")
    args = ap.parse_args()
    dev = "cuda"
    torch.backends.cudnn.benchmark = True
    runs = []
    for cfg in args.configs:
        c = [int(x) for x in cfg.split(",")]
        tag = f"{args.name}_" + "-".join(map(str, c))
        out = RUNS / tag
        out.mkdir(parents=True, exist_ok=True)
        model = PianoNet(*c).to(dev)
        print(tag, "params", sum(p.numel() for p in model.parameters()), flush=True)
        opt = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=1e-4)
        sched = torch.optim.lr_scheduler.OneCycleLR(opt, args.lr, total_steps=args.steps, pct_start=0.05)
        runs.append((tag, c, model, opt, sched, out))
    dl = DataLoader(
        gen.Stream(
            train_pianos=tuple(args.train_pianos), maestro_split=None if args.no_maestro else "train", seed=1
        ),
        batch_size=args.batch,
        num_workers=args.workers,
        prefetch_factor=4,
        persistent_workers=True,
    )
    val_gen = gen.Generator(train_pianos=("ydp",), maestro_split="test", seed=999)
    val = [val_gen.clip() for _ in range(96)]
    val = [torch.stack([torch.from_numpy(c[i]) for c in val]).to(dev) for i in range(4)]
    t0 = time.time()
    for step, batch in enumerate(dl, 1):
        a, o, w, f = (b.to(dev, non_blocking=True) for b in batch)
        msg = []
        for tag, c, model, opt, sched, out in runs:
            model.train()
            lo_, lf_, _, _ = losses(model, a, o, w, f)
            loss = lo_ + 0.5 * lf_
            opt.zero_grad(set_to_none=True)
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 2.0)
            opt.step()
            sched.step()
            msg.append(f"{tag} {loss.item():.3f}")
            if step % 1000 == 0 or step == args.steps:
                model.eval()
                with torch.no_grad():
                    tot = np.zeros(4)
                    for i in range(0, 96, 32):
                        _, _, lo, _ = losses(model, *(v[i : i + 32] for v in val))
                        tot += onset_f1(lo, val[1][i : i + 32])
                tp_p, n_p, tp_t, n_t = tot
                print(
                    f"VAL {tag} step {step} onset P {tp_p / max(n_p, 1):.3f} R {tp_t / max(n_t, 1):.3f} (ydp + maestro-test)",
                    flush=True,
                )
                torch.save({"model": model.state_dict(), "c": c}, out / "model.pt")
        if step % 100 == 0:
            print(f"step {step} loss {' | '.join(msg)} {time.time() - t0:.0f}s", flush=True)
        if step >= args.steps:
            break


if __name__ == "__main__":
    main()
