"""Train the compound melody model (step 4). Refuses to run without the review gate for the current dataset.

    python -m melody_model.train --name smoke --minutes 5
    python -m melody_model.train --name base --steps 20000

Writes data/melody/runs/<name>/: config.json (model, data hash, vocab hash, gate, params),
log.jsonl (step, train/val loss per field, tokens/s, elapsed), ckpt.pt (best validation loss).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
import sys
import time

from .build import OUT
from .download import ROOT
from .gate import dataset_hash, require_gate
from .notation import Unsupported
from .samples import make_sample
from .tokenizer import vocab_json

RUNS = ROOT / "data" / "melody" / "runs"
PAD_STEP = (1, 0, 0, 0)  # kind PAD; asserted against the vocab in main()


def load_tunes(split: str, limit: int | None = None) -> list[dict]:
    out = []
    with open(OUT / "tunes.jsonl", encoding="utf-8") as fh:
        for line in fh:
            t = json.loads(line)
            if t["split"] == split:
                out.append(t)
    return out[:limit] if limit else out


def collate(batch, torch):
    """batch: list of (steps, loss_from) -> x, y (B, T, 4) and mask (B, T)."""
    t = max(len(s) for s, _ in batch) - 1
    x = torch.full((len(batch), t, 4), 0, dtype=torch.long)
    y = torch.full((len(batch), t, 4), 0, dtype=torch.long)
    x[..., 0] = PAD_STEP[0]
    y[..., 0] = PAD_STEP[0]
    mask = torch.zeros((len(batch), t), dtype=torch.bool)
    for i, (steps, loss_from) in enumerate(batch):
        s = torch.tensor(steps, dtype=torch.long)
        n = len(steps) - 1
        x[i, :n], y[i, :n] = s[:-1], s[1:]
        mask[i, max(loss_from - 1, 0) : n] = True  # target index j+1 >= loss_from
    return x, y, mask


def sample_stream(tunes, seed, ctx):
    rng = random.Random(seed)
    while True:
        t = tunes[rng.randrange(len(tunes))]
        try:
            yield make_sample(t, rng, ctx=ctx)
        except Unsupported:
            continue


def make_stream(tunes, seed, ctx, batch_size):
    """Endless batches; module level so DataLoader workers (spawned on Windows) can pickle it."""
    return TrainStream(tunes, seed, ctx, batch_size)


try:
    import torch as _torch
    from torch.utils.data import IterableDataset as _Iterable
except ImportError:  # tests without torch
    _torch, _Iterable = None, object


class TrainStream(_Iterable):
    """Batches by token budget: samples of similar length are grouped so padding stays small
    and one long sample cannot blow up GPU memory. batch_size = padded tokens per batch."""

    POOL = 512

    def __init__(self, tunes, seed, ctx, batch_size):
        self.tunes, self.seed, self.ctx, self.batch_size = tunes, seed, ctx, batch_size

    def __iter__(self):
        info = _torch.utils.data.get_worker_info()
        wid = info.id if info else 0
        rng = random.Random(self.seed * 7919 + wid)
        stream = sample_stream(self.tunes, self.seed * 1000 + wid, self.ctx)
        while True:
            pool = sorted((next(stream) for _ in range(self.POOL)), key=lambda it: len(it[0]))
            batches, cur = [], []
            for item in pool:
                if cur and len(item[0]) * (len(cur) + 1) > self.batch_size:
                    batches.append(cur)
                    cur = []
                cur.append(item)
            if cur:
                batches.append(cur)
            rng.shuffle(batches)
            for b in batches:
                yield collate(b, _torch)


def git_state() -> dict:
    import subprocess

    def run(*a):
        r = subprocess.run(["git", *a], cwd=ROOT, capture_output=True, text=True)
        return r.stdout.strip() if r.returncode == 0 else None

    return {
        "sha": run("rev-parse", "HEAD"),
        "branch": run("rev-parse", "--abbrev-ref", "HEAD"),
        "dirty": bool(run("status", "--porcelain", "--untracked-files=no")),
    }


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True)
    ap.add_argument("--layers", type=int, default=6)
    ap.add_argument("--d", type=int, default=384)
    ap.add_argument("--heads", type=int, default=6)
    ap.add_argument("--ctx", type=int, default=1024)
    ap.add_argument("--dropout", type=float, default=0.1)
    ap.add_argument("--batch", type=int, default=32768, help="padded tokens per batch")
    ap.add_argument("--lr", type=float, default=3e-4)
    ap.add_argument("--warmup", type=int, default=500)
    ap.add_argument("--steps", type=int, default=20000, help="schedule length (cosine decay to 10%)")
    ap.add_argument("--minutes", type=float, default=None, help="stop early after this wall time")
    ap.add_argument("--val-every", type=int, default=500)
    ap.add_argument("--val-samples", type=int, default=1024)
    ap.add_argument("--log-every", type=int, default=50)
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--limit-tunes", type=int, default=None, help="smoke runs only")
    args = ap.parse_args(argv)

    gate = require_gate()
    import torch
    from torch.utils.data import DataLoader

    from .model import FIELD_NAMES, PAD_KIND, CompoundGPT, Config

    assert PAD_KIND == PAD_STEP[0]
    if not torch.cuda.is_available():
        raise SystemExit("CUDA GPU not available")
    torch.manual_seed(args.seed)
    dev = "cuda"

    train_tunes = load_tunes("train", args.limit_tunes)
    valid_tunes = load_tunes("valid", args.limit_tunes)

    loader = iter(
        DataLoader(
            make_stream(train_tunes, args.seed, args.ctx, args.batch),
            batch_size=None,
            num_workers=args.workers,
            persistent_workers=args.workers > 0,
            prefetch_factor=4 if args.workers else None,
            pin_memory=True,
        )
    )
    vstream = sample_stream(valid_tunes, 12345, args.ctx)
    val_items = sorted((next(vstream) for _ in range(args.val_samples)), key=lambda it: len(it[0]))
    val_batches = [collate(val_items[i : i + 32], torch) for i in range(0, len(val_items), 32)]

    cfg = Config(layers=args.layers, d=args.d, heads=args.heads, ctx=args.ctx, dropout=args.dropout)
    model = CompoundGPT(cfg).to(dev)
    decay = [p for n, p in model.named_parameters() if p.dim() >= 2]
    no_decay = [p for n, p in model.named_parameters() if p.dim() < 2]
    opt = torch.optim.AdamW(
        [{"params": decay, "weight_decay": 0.1}, {"params": no_decay, "weight_decay": 0.0}],
        lr=args.lr,
        betas=(0.9, 0.95),
        fused=True,
    )

    def lr_at(step):
        if step < args.warmup:
            return args.lr * (step + 1) / args.warmup
        p = min(1.0, (step - args.warmup) / max(1, args.steps - args.warmup))
        return args.lr * (0.1 + 0.9 * 0.5 * (1 + math.cos(math.pi * p)))

    run = RUNS / args.name
    if run.exists() and any(run.iterdir()):
        raise SystemExit(f"{run} exists: pick a new --name (runs are never overwritten or mixed)")
    run.mkdir(parents=True, exist_ok=True)
    meta = {
        "args": vars(args),
        "argv": ["python", "-m", "melody_model.train", *argv],
        "git": git_state(),
        "model": cfg.to_dict(),
        "params": model.n_params(),
        "dataset_sha256": dataset_hash(),
        "vocab_sha256": hashlib.sha256(vocab_json().encode()).hexdigest(),
        "gate": gate,
        "train_tunes": len(train_tunes),
        "valid_tunes": len(valid_tunes),
        "torch": torch.__version__,
        "gpu": torch.cuda.get_device_name(0),
    }
    (run / "config.json").write_text(json.dumps(meta, indent=1), encoding="utf-8")
    print(
        f"params {meta['params']:,}  train tunes {len(train_tunes)}  valid tunes {len(valid_tunes)}",
        flush=True,
    )

    @torch.no_grad()
    def evaluate():
        model.eval()
        tot, per = 0.0, [0.0] * 4
        for x, y, m in val_batches:
            with torch.autocast("cuda", dtype=torch.bfloat16):
                loss, parts = model(x.to(dev), y.to(dev), m.to(dev))
            tot += loss.item()
            per = [a + b.item() for a, b in zip(per, parts)]
        model.train()
        n = len(val_batches)
        return tot / n, [p / n for p in per]

    log = open(run / "log.jsonl", "a", encoding="utf-8")
    best = float("inf")
    t0 = time.time()
    tokens = 0
    tok_t, tok_n = time.time(), 0
    step = 0
    model.train()
    while step < args.steps:
        x, y, m = (a.to(dev, non_blocking=True) for a in next(loader))
        for g in opt.param_groups:
            g["lr"] = lr_at(step)
        with torch.autocast("cuda", dtype=torch.bfloat16):
            loss, parts = model(x, y, m)
        opt.zero_grad(set_to_none=True)
        loss.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
        opt.step()
        n_tok = int((x[..., 0] != PAD_KIND).sum())
        tokens += n_tok
        tok_n += n_tok
        step += 1
        elapsed = time.time() - t0
        if step % args.log_every == 0:
            rate = tok_n / (time.time() - tok_t)
            tok_t, tok_n = time.time(), 0
            rec = {
                "step": step,
                "loss": loss.item(),
                **{f"loss_{f}": p.item() for f, p in zip(FIELD_NAMES, parts)},
                "lr": lr_at(step),
                "tok_per_s": round(rate),
                "tokens": tokens,
                "elapsed_s": round(elapsed, 1),
            }
            log.write(json.dumps(rec) + "\n")
            log.flush()
            print(f"step {step} loss {loss.item():.3f} {rate:,.0f} tok/s {elapsed:.0f}s", flush=True)
        stop = args.minutes is not None and elapsed > args.minutes * 60
        if step % args.val_every == 0 or stop or step == args.steps:
            vl, vparts = evaluate()
            rec = {
                "step": step,
                "val_loss": vl,
                **{f"val_loss_{f}": p for f, p in zip(FIELD_NAMES, vparts)},
                "elapsed_s": round(time.time() - t0, 1),
            }
            log.write(json.dumps(rec) + "\n")
            log.flush()
            print(
                f"  val {vl:.3f} ({', '.join(f'{f} {p:.3f}' for f, p in zip(FIELD_NAMES, vparts))})",
                flush=True,
            )
            if vl < best:
                best = vl
                torch.save(
                    {
                        "model": model.state_dict(),
                        "config": cfg.to_dict(),
                        "step": step,
                        "val_loss": vl,
                        "meta": meta,
                    },
                    run / "ckpt.pt",
                )
        if stop:
            break
    summary = {
        "steps": step,
        "best_val_loss": best,
        "tokens": tokens,
        "elapsed_s": round(time.time() - t0, 1),
        "peak_mem_gb": round(torch.cuda.max_memory_allocated() / 1e9, 2),
    }
    (run / "summary.json").write_text(json.dumps(summary, indent=1), encoding="utf-8")
    print(json.dumps(summary), flush=True)


if __name__ == "__main__":
    main(sys.argv[1:])
