"""Compound decoder-only transformer (D20, docs/specs/melody-model.md).

Input: one step = (kind, pitch, dur, finger); the four embeddings are summed.
Blocks: pre-norm, causal self-attention with rotary positions (RoPE), GELU MLP.
Output heads are cascaded so the fields of one step agree:
  kind   <- h
  pitch  <- h + E_kind(kind)
  dur    <- h + E_kind(kind) + E_pitch(pitch)
  finger <- h + E_kind(kind) + E_pitch(pitch) + E_dur(dur)
Training feeds the true fields (teacher forcing); sampling feeds the sampled ones.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass

import torch
import torch.nn as nn
import torch.nn.functional as F

from .tokenizer import FIELDS

FIELD_NAMES = tuple(FIELDS)  # kind, pitch, dur, finger
FIELD_SIZES = tuple(len(v) for v in FIELDS.values())
PAD_KIND = FIELDS["kind"].index("PAD")


@dataclass
class Config:
    layers: int = 6
    d: int = 384
    heads: int = 6
    ctx: int = 1024
    dropout: float = 0.1

    def to_dict(self):
        return asdict(self)


def rope(x: torch.Tensor, cos: torch.Tensor, sin: torch.Tensor) -> torch.Tensor:
    x1, x2 = x[..., ::2], x[..., 1::2]
    return torch.stack((x1 * cos - x2 * sin, x1 * sin + x2 * cos), dim=-1).flatten(-2)


class Block(nn.Module):
    def __init__(self, c: Config):
        super().__init__()
        self.heads = c.heads
        self.n1, self.n2 = nn.LayerNorm(c.d), nn.LayerNorm(c.d)
        self.qkv = nn.Linear(c.d, 3 * c.d, bias=False)
        self.proj = nn.Linear(c.d, c.d, bias=False)
        self.mlp = nn.Sequential(nn.Linear(c.d, 4 * c.d), nn.GELU(), nn.Linear(4 * c.d, c.d))
        self.drop = nn.Dropout(c.dropout)
        self.p = c.dropout

    def forward(self, x, cos, sin):
        b, t, d = x.shape
        q, k, v = self.qkv(self.n1(x)).view(b, t, 3, self.heads, d // self.heads).permute(2, 0, 3, 1, 4)
        q, k = rope(q, cos, sin), rope(k, cos, sin)
        a = F.scaled_dot_product_attention(
            q, k, v, is_causal=True, dropout_p=self.p if self.training else 0.0
        )
        x = x + self.drop(self.proj(a.transpose(1, 2).reshape(b, t, d)))
        return x + self.drop(self.mlp(self.n2(x)))


class CompoundGPT(nn.Module):
    def __init__(self, c: Config):
        super().__init__()
        self.c = c
        self.inp = nn.ModuleList(nn.Embedding(n, c.d) for n in FIELD_SIZES)
        self.blocks = nn.ModuleList(Block(c) for _ in range(c.layers))
        self.norm = nn.LayerNorm(c.d)
        self.heads = nn.ModuleList(nn.Linear(c.d, n) for n in FIELD_SIZES)
        self.cond = nn.ModuleList(
            nn.Embedding(n, c.d) for n in FIELD_SIZES[:-1]
        )  # kind, pitch, dur feed later heads
        hd = c.d // c.heads
        inv = 1.0 / (10000 ** (torch.arange(0, hd, 2).float() / hd))
        ang = torch.outer(torch.arange(c.ctx).float(), inv)
        self.register_buffer("cos", ang.cos()[None, None], persistent=False)
        self.register_buffer("sin", ang.sin()[None, None], persistent=False)
        self.apply(self._init)

    @staticmethod
    def _init(m):
        if isinstance(m, (nn.Linear, nn.Embedding)):
            nn.init.normal_(m.weight, std=0.02)
        if isinstance(m, nn.Linear) and m.bias is not None:
            nn.init.zeros_(m.bias)

    def hidden(self, x: torch.Tensor) -> torch.Tensor:
        """x: (B, T, 4) step ids -> (B, T, d)."""
        t = x.shape[1]
        h = sum(emb(x[..., i]) for i, emb in enumerate(self.inp))
        cos, sin = self.cos[:, :, :t], self.sin[:, :, :t]
        for blk in self.blocks:
            h = blk(h, cos, sin)
        return self.norm(h)

    def heads_logits(self, h: torch.Tensor, fields: torch.Tensor) -> list[torch.Tensor]:
        """Logits per field, each head conditioned on the earlier fields of the same step (`fields`: (B, T, 4))."""
        out, z = [], h
        for i, head in enumerate(self.heads):
            out.append(head(z))
            if i < len(self.cond):
                z = z + self.cond[i](fields[..., i])
        return out

    def forward(self, x: torch.Tensor, y: torch.Tensor, mask: torch.Tensor):
        """x, y: (B, T, 4) inputs and next-step targets; mask: (B, T) bool, where the loss counts.
        Returns (total loss, per-field losses)."""
        logits = self.heads_logits(self.hidden(x), y)
        losses = []
        for i, lg in enumerate(logits):
            loss = F.cross_entropy(
                lg.float().reshape(-1, lg.shape[-1]), y[..., i].reshape(-1), reduction="none"
            )
            losses.append((loss * mask.reshape(-1)).sum() / mask.sum().clamp(min=1))
        return sum(losses), losses

    def n_params(self) -> int:
        return sum(p.numel() for p in self.parameters())
