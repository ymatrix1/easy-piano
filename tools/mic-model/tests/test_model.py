import torch

from features import NBANDS
from model import FRONT_CTX, LOOKAHEAD, PianoNet


def test_step_matches_forward_seq():
    torch.manual_seed(0)
    m = PianoNet().eval()
    x = torch.rand(1, 60, NBANDS)
    with torch.no_grad():
        on, fr = m.forward_seq(x)
        states = [torch.zeros(s) for s in m.state_shapes()]
        buf = torch.zeros(1, FRONT_CTX, NBANDS)
        for f in range(60):
            buf = torch.cat([buf[:, 1:], x[:, f : f + 1]], 1)
            o, fl, *states = m.step(buf, *states)
            g = f - LOOKAHEAD  # frame whose output this step produces
            if g < 0:  # warm-up: the pre-start frames are silence, not computed
                states = [torch.zeros(s) for s in m.state_shapes()]
            if g >= 0:
                assert torch.allclose(o, on[:, g], atol=1e-5), g
                assert torch.allclose(fl, fr[:, g], atol=1e-5), g
