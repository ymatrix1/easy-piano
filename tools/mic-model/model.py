"""Streaming piano-note CNN: 264 log bands/frame -> onset + frame prob for 88 keys.

forward_seq(x [B,T,264]) is the training path. step(...) is the streaming path
(one new feature frame + explicit state tensors, exported to ONNX) and is
numerically identical to forward_seq (tests/test_model.py). Look-ahead is
LOOKAHEAD frames (16 ms each): the front block is time-symmetric, everything
after it is causal.
"""

import torch
import torch.nn.functional as F
from torch import nn

from features import BPS, H_OFFSETS, NKEYS

FRONT_T = (3, 3, 3)  # time kernels of the symmetric front block
LOOKAHEAD = sum(k // 2 for k in FRONT_T)
FRONT_CTX = 2 * LOOKAHEAD + 1  # feature frames the front block needs per step
DILATIONS = (1, 2, 4, 8, 16)


def harmonic_stack(x):
    """[B, T, NBANDS] -> [B, H, T, NBANDS] (band index shifted up by each harmonic's offset)."""
    chans = []
    for off in H_OFFSETS:
        if off >= 0:
            s = F.pad(x[..., off:], (0, off))
        else:
            s = F.pad(x[..., :off], (-off, 0))
        chans.append(s)
    return torch.stack(chans, 1)


class PianoNet(nn.Module):
    def __init__(self, c1=16, c2=24, c3=32, ct=48):
        super().__init__()
        h = len(H_OFFSETS)
        # Front block: conv over (time, band); the 2nd conv strides bands 3 -> 1 per key.
        self.f1 = nn.Conv2d(h, c1, (3, 3), padding=(0, 1))
        self.f2 = nn.Conv2d(c1, c2, (3, 3), stride=(1, BPS), padding=(0, 1))
        self.f3 = nn.Conv2d(c2, c3, (3, 5), padding=(0, 2))
        # Causal temporal convs per key (weights shared over keys).
        ins = [c3] + [ct] * (len(DILATIONS) - 1)
        self.t = nn.ModuleList(nn.Conv2d(i, ct, (3, 1), dilation=(d, 1)) for i, d in zip(ins, DILATIONS))
        self.key_mix = nn.Conv2d(ct, ct, (1, 5), padding=(0, 2))  # a little cross-key context
        self.onset = nn.Conv2d(ct, 1, 1)
        self.frame = nn.Conv2d(ct, 1, 1)

    # --- training path -------------------------------------------------
    def forward_seq(self, x):
        """x [B, T, NBANDS] log bands -> (onset, frame) logits [B, T, NKEYS]."""
        z = harmonic_stack(x)
        z = F.pad(z, (0, 0, LOOKAHEAD, LOOKAHEAD))  # zeros = silence before/after
        z = F.relu(self.f1(z))
        z = F.relu(self.f2(z))
        z = F.relu(self.f3(z))  # [B, c3, T, 88]
        for conv, d in zip(self.t, DILATIONS):
            z = F.relu(conv(F.pad(z, (0, 0, 2 * d, 0))))
        z = F.relu(self.key_mix(z))
        return self.onset(z)[:, 0], self.frame(z)[:, 0]

    # --- streaming path ------------------------------------------------
    def state_shapes(self, batch=1):
        c3 = self.f3.out_channels
        ct = self.t[0].out_channels
        shapes = []
        for i, d in enumerate(DILATIONS):
            shapes.append((batch, c3 if i == 0 else ct, 2 * d, NKEYS))
        return shapes

    def step(self, ctx, *states):
        """ctx [B, FRONT_CTX, NBANDS]: last FRONT_CTX feature frames (newest last).
        Returns onset/frame logits [B, NKEYS] for the frame LOOKAHEAD behind the
        newest, then the new states."""
        z = harmonic_stack(ctx)
        z = F.relu(self.f1(z))
        z = F.relu(self.f2(z))
        z = F.relu(self.f3(z))  # [B, c3, 1, 88]
        new = []
        for conv, d, st in zip(self.t, DILATIONS, states):
            z = torch.cat([st, z], 2)
            new.append(z[:, :, 1:])
            z = F.relu(conv(z))
        z = F.relu(self.key_mix(z))
        return (self.onset(z)[:, 0, 0], self.frame(z)[:, 0, 0], *new)


if __name__ == "__main__":
    m = PianoNet()
    print(sum(p.numel() for p in m.parameters()), "params, lookahead", LOOKAHEAD)
