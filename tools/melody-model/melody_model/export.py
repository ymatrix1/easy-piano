"""Export a checkpoint to ONNX for the browser (D20, docs/specs/melody-model.md "Browser export").

    python -m melody_model.export --run smoke3 [--runs DIR] [--out web/model]

Writes two graphs plus their int8 versions:

  decoder.onnx  one decoding call with a KV cache:
                x (B, T, 4) int64, past_k / past_v (L, B, H, P, hd) float32
                -> h (B, d) hidden state of the last input step, present_k / present_v (L, B, H, P+T, hd).
                Prefill passes the spec prefix with P = 0; each later call passes one step (T = 1).
  heads.onnx    the cascaded heads for one step: h (B, d), kind, pitch, dur (B,) int64
                -> kind, pitch, dur, finger logits. Head i reads only the fields before it, so the
                caller runs it once per field: sample kind, rerun with that kind for pitch, and so on.

A full-sequence graph (no cache) would be simpler but re-runs the whole prefix every step:
O(n^2) work for an n-step tune instead of O(n). With ~200 steps per 8-bar tune that is ~100x more
attention and MLP work per tune, so the cache is worth its two extra inputs.

int8: onnxruntime dynamic quantization (weights int8 per tensor, activations quantized at run time),
MatMul / Gemm only; embeddings and LayerNorm stay fp32.
Also writes next to the graphs: vocab.json; parity.json (an Ode to Joy step sequence and its PyTorch logits,
for the in-browser parity check); meta.json (config, run, step, val loss, sizes, sha256 per file, parity,
and validation NLL of PyTorch vs ONNX fp32 vs ONNX int8 on held-out tunes).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import torch
import torch.nn as nn
import torch.nn.functional as F

from .model import CompoundGPT, Config, rope
from .tokenizer import vocab_json

HERE = Path(__file__).resolve().parent.parent
OPSET = 17


class StepDecoder(nn.Module):
    """CompoundGPT.hidden with a KV cache and a position offset of P = past length."""

    def __init__(self, m: CompoundGPT):
        super().__init__()
        self.m = m

    def forward(self, x, past_k, past_v):
        m = self.m
        b, t, _ = x.shape
        p = past_k.shape[3]
        pos = torch.arange(t, device=x.device) + p
        cos, sin = m.cos[0, 0][pos], m.sin[0, 0][pos]  # (T, hd/2), broadcast over B, H
        # absolute query position p+i may see keys 0..p+i
        allow = torch.arange(p + t, device=x.device)[None, :] <= pos[:, None]
        h = sum(emb(x[..., i]) for i, emb in enumerate(m.inp))
        ks, vs = [], []
        for li, blk in enumerate(m.blocks):
            d = h.shape[-1]
            q, k, v = blk.qkv(blk.n1(h)).view(b, t, 3, blk.heads, d // blk.heads).permute(2, 0, 3, 1, 4)
            q, k = rope(q, cos, sin), rope(k, cos, sin)
            k = torch.cat([past_k[li], k], dim=2)
            v = torch.cat([past_v[li], v], dim=2)
            ks.append(k)
            vs.append(v)
            a = F.scaled_dot_product_attention(q, k, v, attn_mask=allow)
            h = h + blk.proj(a.transpose(1, 2).reshape(b, t, d))
            h = h + blk.mlp(blk.n2(h))
        return m.norm(h)[:, -1], torch.stack(ks), torch.stack(vs)


class Heads(nn.Module):
    """CompoundGPT.heads_logits for one position; unknown later fields may be any id (they are not read)."""

    def __init__(self, m: CompoundGPT):
        super().__init__()
        self.m = m

    def forward(self, h, kind, pitch, dur):
        fields = torch.stack([kind, pitch, dur, torch.zeros_like(kind)], dim=-1)
        return tuple(self.m.heads_logits(h, fields))


def load(ckpt: Path) -> tuple[CompoundGPT, dict]:
    blob = torch.load(ckpt, map_location="cpu", weights_only=False)
    m = CompoundGPT(Config(**blob["config"]))
    m.load_state_dict(blob["model"])
    return m.eval(), blob


def export(m: CompoundGPT, out: Path) -> dict:
    """Write decoder/heads fp32 and int8 graphs to `out`; return file sizes in bytes."""
    from onnxruntime.quantization import QuantType, quantize_dynamic

    out.mkdir(parents=True, exist_ok=True)
    c = m.c
    hd = c.d // c.heads
    x = torch.zeros(2, 3, 4, dtype=torch.long)
    past = torch.zeros(c.layers, 2, c.heads, 5, hd)
    with torch.no_grad():
        torch.onnx.export(
            StepDecoder(m).eval(),
            (x, past, past),
            out / "decoder.onnx",
            dynamo=False,
            opset_version=OPSET,
            input_names=["x", "past_k", "past_v"],
            output_names=["h", "present_k", "present_v"],
            dynamic_axes={
                "x": {0: "B", 1: "T"},
                "past_k": {1: "B", 3: "P"},
                "past_v": {1: "B", 3: "P"},
                "h": {0: "B"},
                "present_k": {1: "B", 3: "PT"},
                "present_v": {1: "B", 3: "PT"},
            },
        )
        ids = torch.zeros(2, dtype=torch.long)
        torch.onnx.export(
            Heads(m).eval(),
            (torch.zeros(2, c.d), ids, ids, ids),
            out / "heads.onnx",
            dynamo=False,
            opset_version=OPSET,
            input_names=["h", "kind", "pitch", "dur"],
            output_names=["kind_logits", "pitch_logits", "dur_logits", "finger_logits"],
            dynamic_axes={
                n: {0: "B"}
                for n in (
                    "h",
                    "kind",
                    "pitch",
                    "dur",
                    "kind_logits",
                    "pitch_logits",
                    "dur_logits",
                    "finger_logits",
                )
            },
        )
    for name in ("decoder", "heads"):
        quantize_dynamic(
            out / f"{name}.onnx",
            out / f"{name}.int8.onnx",
            weight_type=QuantType.QInt8,
            op_types_to_quantize=["MatMul", "Gemm"],
        )
    (out / "vocab.json").write_text(vocab_json(), encoding="utf-8")
    return {p.name: p.stat().st_size for p in sorted(out.glob("*.onnx"))}


_SESSIONS: dict = {}


def _session(path: Path):
    """One onnxruntime CPU session per file and modification time (the NLL check runs hundreds of tunes)."""
    import onnxruntime as ort

    key = (str(path), path.stat().st_mtime_ns)
    if key not in _SESSIONS:
        _SESSIONS[key] = ort.InferenceSession(str(path), providers=["CPUExecutionProvider"])
    return _SESSIONS[key]


def _ort_logits(out: Path, suffix: str, steps: torch.Tensor, split: int) -> list[torch.Tensor]:
    """Run the ONNX graphs like the browser: prefill steps[:split], then one step per call.
    Returns per-field logits at positions split-1 .. T-2, teacher-forced on steps (as torch_logits)."""
    import numpy as np

    dec, heads = (_session(out / f"{name}{suffix}.onnx") for name in ("decoder", "heads"))
    pk_shape = [s if isinstance(s, int) else 0 for s in dec.get_inputs()[1].shape]
    b, t, _ = steps.shape
    pk_shape[1] = b
    pk = pv = np.zeros(pk_shape, dtype=np.float32)
    s = steps.numpy()
    outs: list[list] = [[], [], [], []]
    pos, nxt = 0, split
    while True:
        h, pk, pv = dec.run(None, {"x": s[:, pos:nxt], "past_k": pk, "past_v": pv})
        if nxt >= t:
            break
        tgt = s[:, nxt]  # next step's fields condition the later heads
        lg = heads.run(None, {"h": h, "kind": tgt[:, 0], "pitch": tgt[:, 1], "dur": tgt[:, 2]})
        for i in range(4):
            outs[i].append(lg[i])
        pos, nxt = nxt, nxt + 1
    return [torch.from_numpy(np.stack(o, axis=1)) for o in outs]


def torch_logits(m: CompoundGPT, steps: torch.Tensor, split: int) -> list[torch.Tensor]:
    """Reference: full-sequence PyTorch logits at positions split-1 .. T-2 (predicting steps split .. T-1)."""
    with torch.no_grad():
        h = m.hidden(steps[:, :-1])
        lg = m.heads_logits(h, steps[:, 1:])
    return [x[:, split - 1 :] for x in lg]


def parity(m: CompoundGPT, out: Path, steps: torch.Tensor, split: int) -> dict:
    """Max abs logit difference and top-1 agreement per field, fp32 and int8 vs PyTorch."""
    ref = torch_logits(m, steps, split)
    res = {}
    for suffix, label in (("", "fp32"), (".int8", "int8")):
        got = _ort_logits(out, suffix, steps, split)
        res[label] = {
            "max_abs": max(float((g - r).abs().max()) for g, r in zip(got, ref)),
            "top1": min(float((g.argmax(-1) == r.argmax(-1)).float().mean()) for g, r in zip(got, ref)),
            "max_prob_diff": max(
                float((g.softmax(-1) - r.softmax(-1)).abs().max()) for g, r in zip(got, ref)
            ),
        }
    return res


def nll(m: CompoundGPT, out: Path, seqs: list[tuple[torch.Tensor, int]]) -> dict:
    """Mean per-field NLL (nats/step) over the left-to-right loss positions (after SPEC_END, as in training),
    for PyTorch and both ONNX variants. Total = sum of the field means, the training loss."""
    import torch.nn.functional as F2

    sums = {k: [0.0] * 4 for k in ("torch", "fp32", "int8")}
    count = 0
    for steps, split in seqs:
        tgt = steps[0, split:]
        runs = {
            "torch": torch_logits(m, steps, split),
            "fp32": _ort_logits(out, "", steps, split),
            "int8": _ort_logits(out, ".int8", steps, split),
        }
        for k, lg in runs.items():
            for i in range(4):
                sums[k][i] += float(F2.cross_entropy(lg[i][0].float(), tgt[:, i], reduction="sum"))
        count += tgt.shape[0]
    res = {}
    for k, v in sums.items():
        fields = [x / count for x in v]
        res[k] = {
            "total": round(sum(fields), 5),
            "kind": round(fields[0], 5),
            "pitch": round(fields[1], 5),
            "dur": round(fields[2], 5),
            "finger": round(fields[3], 5),
        }
    res["steps"] = count
    res["tunes"] = len(seqs)
    return res


def eval_seqs(tunes_path: Path, n: int) -> list[tuple[torch.Tensor, int]]:
    """First n validation tunes (by id), encoded like training without random drops: spec (with level),
    plan, bars, END. Tunes longer than the context are skipped."""
    from .difficulty import level_of
    from .labels import encode_plan
    from .tokenizer import Unsupported, encode_bars, encode_spec, spec_from_song, step

    tunes = sorted((json.loads(line) for line in open(tunes_path, encoding="utf-8")), key=lambda t: t["id"])
    out = []
    for t in tunes:
        if t["split"] != "valid":
            continue
        try:
            spec = spec_from_song(t)
            spec.level = level_of(t)
            head = [step("BOS")] + encode_spec(spec)
            steps = head + encode_plan(t["plan"]) + encode_bars(t["bars"]) + [step("END")]
        except Unsupported:
            continue
        if len(steps) <= 1024:
            out.append((torch.tensor([steps]), len(head)))
        if len(out) == n:
            break
    return out


def sha256(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--run", required=True)
    ap.add_argument("--runs", type=Path, default=HERE.parent.parent / "data" / "melody" / "runs")
    ap.add_argument("--out", type=Path, default=HERE / "web" / "model")
    ap.add_argument(
        "--tunes", type=Path, default=HERE.parent.parent / "data" / "melody" / "dataset" / "tunes.jsonl"
    )
    ap.add_argument(
        "--eval-tunes", type=int, default=200, help="validation tunes for the NLL check (0 = skip)"
    )
    args = ap.parse_args(argv)
    m, blob = load(args.runs / args.run / "ckpt.pt")
    sizes = export(m, args.out)
    from .tokenizer import FIELDS, encode_song

    song = json.loads(
        (HERE.parent.parent / "content" / "songs" / "ode-to-joy.json").read_text(encoding="utf-8")
    )
    steps = torch.tensor([encode_song(song)])
    split = next(i for i, s in enumerate(steps[0].tolist()) if s[0] == FIELDS["kind"].index("SPEC_END")) + 1
    par = parity(m, args.out, steps, split)
    ref = torch_logits(m, steps, split)
    (args.out / "parity.json").write_text(
        json.dumps(
            {
                "steps": steps[0].tolist(),
                "split": split,
                "logits": [[[round(v, 4) for v in row] for row in lg[0].tolist()] for lg in ref],
            }
        ),
        encoding="utf-8",
    )
    quality = nll(m, args.out, eval_seqs(args.tunes, args.eval_tunes)) if args.eval_tunes else None
    files = sorted(
        p.name for p in args.out.iterdir() if p.suffix in (".onnx", ".json") and p.name != "meta.json"
    )
    meta = {
        "run": args.run,
        "step": blob.get("step"),
        "val_loss": blob.get("val_loss"),
        "config": blob["config"],
        "params": m.n_params(),
        "sizes_mb": {k: round(v / 1e6, 2) for k, v in sizes.items()},
        "sha256": {f: sha256(args.out / f) for f in files},
        "parity": par,
        "nll": quality,
    }
    (args.out / "meta.json").write_text(json.dumps(meta, indent=1) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in meta.items() if k != "sha256"}, indent=1))


if __name__ == "__main__":
    main(sys.argv[1:])
