"""Front-end shared by training, offline eval and the web port (app/web/mic_model.js).

16 kHz audio -> |STFT| (Hann 1024, hop 256, frame f centred on sample f*256,
zero padded at the start) -> 264 log-frequency bands (3 per semitone, band 3k+1
is key k = MIDI 21+k, linear interpolation of the magnitude at the band's
centre frequency) -> log1p(4 * magnitude).
Frame f is complete once sample f*256+512 has arrived.
"""

import numpy as np
import torch

SR = 16000
HOP = 256
WIN = 1024
NBINS = WIN // 2 + 1
BPS = 3  # bands per semitone
NKEYS = 88
NBANDS = NKEYS * BPS
MIDI_LO = 21
LOG_GAIN = 4.0


def band_matrix():
    """[NBANDS, NBINS] interpolation matrix: spectrum -> band magnitudes."""
    m = np.zeros((NBANDS, NBINS), dtype=np.float32)
    for b in range(NBANDS):
        midi = MIDI_LO + (b - 1) / BPS
        pos = 440 * 2 ** ((midi - 69) / 12) / (SR / WIN)
        i = int(np.floor(pos))
        w = pos - i
        if i + 1 < NBINS:
            m[b, i] += 1 - w
            m[b, i + 1] += w
    return m


_BM = torch.from_numpy(band_matrix())
_WINDOW = torch.hann_window(WIN, periodic=True)


def log_bands(audio):
    """audio [B, N] float (-1..1) -> [B, T, NBANDS], T = N // HOP + 1."""
    dev = audio.device
    spec = torch.stft(
        audio, WIN, HOP, WIN, _WINDOW.to(dev), center=True, pad_mode="constant", return_complex=True
    ).abs()  # [B, NBINS, T]
    bands = torch.einsum("bft,nf->btn", spec, _BM.to(dev))
    return torch.log1p(LOG_GAIN * bands)


# Harmonic stack: channel h holds the band h*f0 above each key (1/2 .. 6).
HARMONICS = (0.5, 1, 2, 3, 4, 5, 6)
H_OFFSETS = tuple(round(BPS * 12 * np.log2(h)) for h in HARMONICS)


def frame_times(n_frames):
    """Centre time (s) of each frame."""
    return np.arange(n_frames) * HOP / SR
