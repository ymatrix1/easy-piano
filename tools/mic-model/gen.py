"""Training data: endless synthetic mic clips with note labels (docs/research/mic-input.md).

Piano comes from the license-clean sample sets (pianos.py) and, optionally, from
real MAESTRO recordings (fetch_maestro.py). Every clip then goes through a
random room/mic/noise chain. Noise-only clips and voice/hum negatives are
labelled empty. Labels are per 16 ms frame and 88 keys: onset (1 at the frame
centred on the attack, its two neighbours get weight 0) and frame (key down).
All audio is 16 kHz mono float32.
"""

import json

import numpy as np
import torch
from scipy.signal import butter, fftconvolve, lfilter

import pianos
from features import HOP, MIDI_LO, NKEYS, SR

CLIP_S = 6.0
N = int(CLIP_S * SR)
T = N // HOP + 1
MAESTRO = pianos.ROOT / "data" / "maestro"


# ---------------------------------------------------------------- piano ----
class Bank:
    """Piano sample banks at 16 kHz with attack alignment."""

    def __init__(self, names):
        self.names = list(names)
        self.banks = {n: pianos.load(n, SR) for n in self.names}
        self.lead = {}

    def note(self, rng, piano, pitch, cents=0.0, inharm=0.0, max_len=N):
        bank = self.banks[piano]
        base = min(bank, key=lambda p: abs(p - pitch))
        k = int(rng.integers(len(bank[base])))
        x = bank[base][k]
        key = (piano, base, k)
        if key not in self.lead:
            self.lead[key] = int(np.argmax(np.abs(x) > 0.05 * np.abs(x).max()))
        ratio = 2 ** ((pitch - base + cents / 100) / 12)
        lead0 = self.lead[key]
        x = x[lead0 : lead0 + int(max_len * ratio) + 2]  # only what the clip can use
        if ratio != 1:  # linear-interpolation pitch shift: <= 1.5 semitones, fine for training
            idx = np.arange(0, len(x) - 1, ratio)
            i = idx.astype(np.int64)
            x = x[i] * (1 - (idx - i)) + x[i + 1] * (idx - i)
        if inharm:
            x = pianos.sharpen(x, pitch, inharm, SR)
        return x.astype(np.float32)


def scale_walk(rng, lo, hi, n):
    major = np.array([0, 2, 4, 5, 7, 9, 11])
    root = int(rng.integers(lo, hi - 12))
    pool = [root + 12 * o + d for o in range(3) for d in major if lo <= root + 12 * o + d <= hi]
    i = int(rng.integers(len(pool)))
    out = []
    for _ in range(n):
        out.append(pool[i])
        i = int(np.clip(i + rng.choice([-2, -1, -1, 0, 1, 1, 2, 3]), 0, len(pool) - 1))
    return out


def sequence(rng):
    """[(onset_s, pitch, dur_s, gain)]: a beginner-style or random note pattern."""
    ev = []
    kind = rng.choice(["melody", "chords", "hands", "random", "sparse"], p=[0.3, 0.2, 0.2, 0.15, 0.15])
    g = lambda: float(10 ** rng.uniform(-1.4, 0))
    if kind == "melody":
        t = rng.uniform(0, 0.8)
        beat = rng.uniform(0.25, 0.8)
        lo = int(rng.choice([36, 48, 55, 60]))
        for p in scale_walk(rng, lo, min(lo + 30, 100), int(rng.integers(4, 16))):
            ev.append((t, p, beat * rng.uniform(0.6, 1.8), g()))
            t += beat * rng.choice([1, 1, 1, 0.5, 2])
            if t > CLIP_S - 0.2:
                break
    elif kind == "chords":
        t = rng.uniform(0, 1.0)
        while t < CLIP_S - 0.5:
            root = int(rng.integers(36, 84))
            shape = [
                [0, 4, 7],
                [0, 3, 7],
                [0, 7],
                [0, 12],
                [0, 4],
                [0, 5, 9],
                [0, 4, 7, 12],
                [0, 7, 12],
                [0],
            ][int(rng.integers(9))]
            d = rng.uniform(0.5, 2.0)
            for s in shape:
                ev.append((t + rng.uniform(0, 0.03), min(root + s, 104), d, g()))
            t += rng.uniform(0.7, 2.2)
    elif kind == "hands":
        for i, p in enumerate(scale_walk(rng, 55, 84, 12)):
            ev.append((0.3 + i * 0.5, p, rng.uniform(0.3, 0.9), g()))
        for i in range(3):
            ev.append((0.3 + i * 2.0, int(rng.integers(36, 55)), 2.2, g()))
    elif kind == "random":
        t = 0.1
        rate = rng.uniform(1.5, 7)
        while t < CLIP_S - 0.1:
            ev.append((t, int(rng.integers(28, 100)), rng.uniform(0.15, 2.5), g()))
            t += rng.exponential(1 / rate)
    else:  # sparse long sustained notes, with re-strikes
        t = rng.uniform(0, 0.5)
        while t < CLIP_S - 0.3:
            p = int(rng.integers(30, 98))
            ev.append((t, p, rng.uniform(1, 3), g()))
            if rng.random() < 0.3:
                ev.append((t + rng.uniform(0.2, 0.5), p, rng.uniform(0.3, 1), g()))
            t += rng.uniform(0.4, 1.8)
    return ev


def render_piano(rng, bank, piano):
    ev = sequence(rng)
    tune = rng.uniform(-30, 30) if rng.random() < 0.4 else 0.0
    inh = rng.random() < 0.3
    y = np.zeros(N + SR, dtype=np.float32)
    notes = []
    # A re-struck key cuts its own earlier note.
    for t, p, d, gain in ev:
        later = [t2 for t2, p2, _, _ in ev if p2 == p and t2 > t]
        if later:
            d = min(d, min(later) - t - 0.05)
        d = max(d, 0.08)
        s = bank.note(
            rng,
            piano,
            p,
            tune + rng.uniform(-8, 8),
            rng.uniform(0.004, 0.012) if inh and p <= 60 else 0,
            max_len=N - int(t * SR) + 1,
        )
        pedal = rng.random() < 0.2
        n = len(s) if pedal else min(len(s), int(d * SR))
        s = s[:n].copy()
        if not pedal:
            f = min(len(s), int(rng.uniform(0.02, 0.15) * SR))
            s[-f:] *= np.linspace(1, 0, f)
        i = int(t * SR)
        if i >= len(y):
            continue
        m = min(n, len(y) - i)
        y[i : i + m] += gain * s[:m]
        notes.append((t, t + (d if not pedal else n / SR), p))
    return y[:N], notes


def render_maestro(rng, files):
    f = files[int(rng.integers(len(files)))]
    a = f["audio"]
    start = int(rng.integers(0, max(1, len(a) - N)))
    y = a[start : start + N].astype(np.float32) / 32768
    if len(y) < N:
        y = np.pad(y, (0, N - len(y)))
    t0 = start / SR
    notes = []
    for on, off, p, _ in f["notes"]:
        if off > t0 and on < t0 + CLIP_S:
            notes.append((on - t0, min(off - t0, CLIP_S), p))
    return y, notes


def load_maestro(split):
    files = []
    for npy in sorted((MAESTRO / split).glob("*.npy")):
        js = json.loads(npy.with_suffix(".json").read_text())
        files.append({"audio": np.load(npy, mmap_mode="r"), "notes": np.array(js["notes"]).reshape(-1, 4)})
    return files


# --------------------------------------------------------------- labels ----
def labels(notes):
    onset = np.zeros((T, NKEYS), np.float32)
    weight = np.ones((T, NKEYS), np.float32)
    frame = np.zeros((T, NKEYS), np.float32)
    for on, off, p in notes:
        k = int(p) - MIDI_LO
        if not 0 <= k < NKEYS:
            continue
        f_on = round(on * SR / HOP)
        f_off = round(off * SR / HOP)
        if on >= 0 and 0 <= f_on < T:
            for df in (-1, 1):
                if 0 <= f_on + df < T:
                    weight[f_on + df, k] = 0
            onset[f_on, k] = 1
        frame[max(f_on, 0) : max(f_off, 0) + 1, k] = 1
    weight[onset > 0] = 1
    return onset, weight, frame


# ---------------------------------------------------------------- noise ----
def pink(rng, n):
    w = rng.standard_normal(n)
    b = [0.049922035, -0.095993537, 0.050612699, -0.004408786]
    a = [1, -2.494956002, 2.017265875, -0.522189400]
    return lfilter(b, a, w)


def colored(rng, n):
    kind = rng.choice(["white", "pink", "brown", "low"])
    w = rng.standard_normal(n)
    if kind == "white":
        return w
    if kind == "pink":
        return pink(rng, n)
    if kind == "brown":
        return np.cumsum(w) / np.sqrt(np.arange(1, n + 1) + 500)
    return lfilter(*butter(2, rng.uniform(200, 3000) / (SR / 2)), w)


def _burst_train(rng, n, rate, make):
    y = np.zeros(n)
    t = rng.uniform(0, 1 / rate)
    while t < n / SR - 0.1:
        b = make()
        i = int(t * SR)
        m = min(len(b), n - i)
        y[i : i + m] += b[:m]
        t += rng.exponential(1 / rate) + 0.02
    return y


def ev_typing(rng, n):
    def click():
        k = int(rng.uniform(0.002, 0.012) * SR)
        b = rng.standard_normal(k) * np.exp(-np.arange(k) / (rng.uniform(0.001, 0.004) * SR))
        b = lfilter(*butter(2, rng.uniform(800, 3000) / (SR / 2), btype="high"), b)
        return b * rng.uniform(0.3, 1)

    return _burst_train(rng, n, rng.uniform(3, 10), click)


def ev_knock(rng, n):
    def thump():
        k = int(rng.uniform(0.08, 0.3) * SR)
        f = rng.uniform(50, 400)
        t = np.arange(k) / SR
        return np.sin(2 * np.pi * f * t) * np.exp(-t / rng.uniform(0.02, 0.08)) + 0.3 * rng.standard_normal(
            k
        ) * np.exp(-t / 0.01)

    return _burst_train(rng, n, rng.uniform(0.5, 3), thump)


def ev_clap(rng, n):
    def clap():
        k = int(rng.uniform(0.05, 0.25) * SR)
        b = rng.standard_normal(k) * np.exp(-np.arange(k) / (rng.uniform(0.01, 0.05) * SR))
        return lfilter(*butter(2, [rng.uniform(300, 1000) / (SR / 2), 0.9], btype="band"), b)

    return _burst_train(rng, n, rng.uniform(0.3, 2), clap)


def ev_clink(rng, n):
    """Keys, cutlery, glass: short inharmonic high rings."""

    def ring():
        k = int(rng.uniform(0.1, 0.6) * SR)
        t = np.arange(k) / SR
        out = np.zeros(k)
        for _ in range(int(rng.integers(2, 6))):
            out += (
                rng.uniform(0.3, 1)
                * np.sin(2 * np.pi * rng.uniform(1500, 7000) * t)
                * np.exp(-t / rng.uniform(0.03, 0.2))
            )
        return out

    return _burst_train(rng, n, rng.uniform(0.3, 3), ring)


def ev_hum(rng, n):
    t = np.arange(n) / SR
    f = rng.choice([50.0, 60.0])
    y = sum(
        np.sin(2 * np.pi * f * h * t + rng.uniform(0, 6)) / h ** rng.uniform(0.5, 1.5) for h in range(1, 8)
    )
    return y * (1 + 0.2 * np.sin(2 * np.pi * rng.uniform(0.1, 0.5) * t)) + 0.3 * lfilter(
        *butter(1, 800 / (SR / 2)), rng.standard_normal(n)
    )


def ev_rumble(rng, n):
    return lfilter(*butter(2, rng.uniform(100, 600) / (SR / 2)), rng.standard_normal(n)) * (
        1 + np.sin(2 * np.pi * rng.uniform(0.05, 0.3) * np.arange(n) / SR)
    )


VOWELS = [(730, 1090), (270, 2290), (300, 870), (530, 1840), (570, 840), (660, 1720)]


def _formant(x, fc, bw=120):
    lo, hi = max(fc - bw, 50), min(fc + bw, SR / 2 - 100)
    return lfilter(*butter(2, [lo / (SR / 2), hi / (SR / 2)], btype="band"), x)


def ev_speech(rng, n):
    """Voiced speech-like buzz: gliding f0, vowel formants, syllable envelope, fricative bursts."""
    t = np.arange(n) / SR
    base = rng.uniform(85, 260)
    f0 = base * 2 ** (
        0.25 * np.sin(2 * np.pi * rng.uniform(0.3, 1.2) * t)
        + 0.08 * np.sin(2 * np.pi * rng.uniform(2, 5) * t)
    )
    phase = 2 * np.pi * np.cumsum(f0) / SR
    src = (phase / np.pi % 2) - 1  # sawtooth: all harmonics
    out = np.zeros(n)
    i = 0
    while i < n:
        k = int(rng.uniform(0.12, 0.35) * SR)
        f1, f2 = VOWELS[int(rng.integers(len(VOWELS)))]
        seg = src[i : i + k]
        out[i : i + len(seg)] = _formant(seg, f1 * rng.uniform(0.9, 1.1), 150) + 0.6 * _formant(
            seg, f2 * rng.uniform(0.9, 1.1), 250
        )
        i += k
    env = np.clip(np.sin(2 * np.pi * rng.uniform(2.5, 5.5) * t + rng.uniform(0, 6)), 0, None) ** 0.6
    gate = (np.sin(2 * np.pi * rng.uniform(0.2, 0.6) * t + rng.uniform(0, 6)) > -0.3).astype(float)
    return out * env * gate


def ev_tonal_voice(rng, n):
    """Hummed/sung/whistled tones in the piano range: steady pitch, vibrato, a few harmonics."""
    t = np.arange(n) / SR
    y = np.zeros(n)
    i = 0
    while i < n:
        k = int(rng.uniform(0.3, 2.0) * SR)
        f = 440 * 2 ** ((rng.integers(48, 84) - 69) / 12)
        vib = 1 + 0.01 * np.sin(2 * np.pi * rng.uniform(4, 7) * t[i : i + k])
        ph = 2 * np.pi * np.cumsum(f * vib) / SR
        h = rng.integers(1, 6)
        seg = sum(np.sin(ph * j) / j ** rng.uniform(0.5, 2) for j in range(1, h + 1))
        a = np.minimum(1, np.minimum(np.arange(len(seg)), len(seg) - np.arange(len(seg))) / (0.05 * SR))
        y[i : i + len(seg)] += seg * a
        i += k + int(rng.uniform(0, 0.5) * SR)
    return y


def ev_beep(rng, n):
    def beep():
        k = int(rng.uniform(0.1, 0.5) * SR)
        return np.sin(2 * np.pi * rng.uniform(500, 3000) * np.arange(k) / SR) * np.hanning(k)

    return _burst_train(rng, n, rng.uniform(0.2, 1), beep)


EVENTS = {
    "typing": ev_typing,
    "knock": ev_knock,
    "clap": ev_clap,
    "clink": ev_clink,
    "hum": ev_hum,
    "rumble": ev_rumble,
    "speech": ev_speech,
    "tonal": ev_tonal_voice,
    "beep": ev_beep,
}


def rms(x):
    return float(np.sqrt(np.mean(x**2)) + 1e-9)


def add_events(rng, y, p_each=0.15, level_db=(-12, 8), kinds=None):
    """Overlay random non-piano sounds at a level relative to the signal rms."""
    ref = rms(y)
    for name, fn in EVENTS.items():
        if kinds and name not in kinds:
            continue
        if rng.random() < p_each:
            e = fn(rng, len(y))
            y = y + e / rms(e) * ref * 10 ** (rng.uniform(*level_db) / 20)
    return y


# --------------------------------------------------------------- chains ----
def room_chain(rng, y):
    """Random room reverb, mic/speaker EQ, clipping, gain, background noise."""
    if rng.random() < 0.75:
        rt = rng.uniform(0.1, 0.8)
        L = int(min(rt, 0.8) * SR)
        ir = rng.standard_normal(L) * np.exp(-np.arange(L) / (rt / 6.9 * SR))
        ir *= np.sqrt(10 ** (-rng.uniform(-2, 12) / 10) / np.sum(ir**2))
        ir[0] = 1
        y = fftconvolve(y, ir)[: len(y)]
    hp = rng.uniform(30, 350)
    lp = rng.uniform(2500, 7800)
    y = lfilter(*butter(int(rng.integers(1, 3)), hp / (SR / 2), btype="high"), y)
    y = lfilter(*butter(int(rng.integers(1, 3)), lp / (SR / 2)), y)
    if rng.random() < 0.3:  # tilt
        y = y + rng.uniform(-0.6, 0.6) * lfilter(*butter(1, rng.uniform(500, 3000) / (SR / 2)), y)
    peak = np.abs(y).max() + 1e-9
    if rng.random() < 0.2:
        y = np.tanh(rng.uniform(1.5, 5) * y / peak) * peak
    y = y / (np.abs(y).max() + 1e-9) * 10 ** rng.uniform(-2.2, -0.2)
    if rng.random() < 0.9:
        nz = colored(rng, len(y))
        y = y + nz / rms(nz) * rms(y) * 10 ** (-rng.uniform(4, 45) / 20)
    return y.astype(np.float32)


def negative_clip(rng):
    y = np.zeros(N)
    for name in rng.choice(list(EVENTS), size=int(rng.integers(1, 4)), replace=False):
        e = EVENTS[name](rng, N)
        y += e / rms(e) * 10 ** rng.uniform(-1.5, 0.3)
    return y.astype(np.float32)


class Generator:
    """Endless clips: (audio [N], onset [T,88], weight [T,88], frame [T,88])."""

    def __init__(
        self, train_pianos=("salamander", "kw"), maestro_split="train", mix=(0.45, 0.25, 0.15, 0.15), seed=0
    ):
        self.bank = Bank(train_pianos)
        self.maestro = load_maestro(maestro_split) if maestro_split else []
        mix = np.array(mix, dtype=float)
        if not self.maestro:
            mix[1] = 0
        self.mix = mix / mix.sum()
        self.rng = np.random.default_rng(seed)

    def clip(self):
        rng = self.rng
        kind = rng.choice(4, p=self.mix)  # synth, maestro, negative, synth+voices
        if kind == 2:
            y, notes = negative_clip(rng), []
        elif kind == 1:
            y, notes = render_maestro(rng, self.maestro)
        else:
            y, notes = render_piano(rng, self.bank, self.bank.names[int(rng.integers(len(self.bank.names)))])
            if kind == 3:
                y = add_events(
                    rng, y, p_each=0.4, level_db=(-6, 8), kinds=("speech", "tonal", "typing", "clink", "clap")
                )
        y = room_chain(rng, y)
        o, w, f = labels(notes)
        return y.astype(np.float32), o, w, f


class Stream(torch.utils.data.IterableDataset):
    """Endless dataset; one Generator (own RNG) per DataLoader worker."""

    def __init__(self, **kw):
        self.kw = kw

    def __iter__(self):
        info = torch.utils.data.get_worker_info()
        wid = info.id if info else 0
        kw = dict(self.kw)
        g = Generator(seed=int(kw.pop("seed", 0)) * 1000 + wid, **kw)
        while True:
            try:
                clip = g.clip()
            except Exception as e:  # noqa: BLE001  a rare bad random draw must not kill a long run
                print("gen error:", repr(e), flush=True)
                continue
            yield tuple(torch.from_numpy(a) for a in clip)
