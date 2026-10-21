"""Renders the mic-detector fixture set (docs/research/mic-input.md).

Clips are built from license-clean piano sample sets only (tools/mic-model/
pianos.py: Salamander Grand V3 CC-BY 3.0 = app/assets/piano, FreePats Upright
KW CC0, FreePats YDP Grand CC-BY 3.0), never from other recordings. Each clip
gets a `piano` and a `variant` (plain / detune / inharm / speaker) in
truth.json.
Each clip is degraded like a phone/laptop mic in a room: band-pass, a short
synthetic reverb and background noise. Output (WAV + truth.json) goes to
tools/mic-fixtures/ which is git-ignored; rerun to regenerate.

Usage: python tools/mic_fixtures.py   (needs numpy, scipy, ffmpeg on PATH;
run `python tools/mic-model/pianos.py extract` once first)
"""

import json
import sys
from math import gcd
from pathlib import Path

import numpy as np
from scipy.signal import butter, lfilter, resample_poly, sosfiltfilt

sys.path.insert(0, str(Path(__file__).resolve().parent / "mic-model"))
import pianos  # noqa: E402

SR = 24000
ROOT = Path(__file__).resolve().parent.parent
SAMPLES = ROOT / "app" / "assets" / "piano"
OUT = ROOT / "tools" / "mic-fixtures"
PIANOS = pianos.PIANOS
# One variant per clip, cycled so every piano sees all of them. `plain` is
# twice as common; the cycle (5) is coprime with the test-split stride (3).
VARIANTS = ("plain", "plain", "detune", "inharm", "speaker")
rng = np.random.default_rng(7)


def sharpen(x, pitch, amount):
    """Stronger bass inharmonicity: partials from the 3rd up are raised by
    `amount` (0.4-1.2 %) by resampling the high band, as stiff low strings do."""
    f0 = 440 * 2 ** ((pitch - 69) / 12)
    sos = butter(4, min(3 * f0, SR * 0.4) / (SR / 2), btype="high", output="sos")
    hi = sosfiltfilt(sos, x)
    num = int(round((1 + amount) * 1000))
    g = gcd(num, 1000)
    hi2 = resample_poly(hi, 1000 // g, num // g)[: len(x)]
    hi2 = np.pad(hi2, (0, len(x) - len(hi2)))
    return (x - hi + hi2).astype(np.float32)


def render(events, length, piano, variant, vel_jitter=True):
    """events: list of (onset_s, pitch, dur_s)."""
    y = np.zeros(int(length * SR))
    # A detuned piano is off by one amount overall, plus a little per note.
    tune = rng.uniform(-30, 30) if variant == "detune" else 0.0
    for t, p, dur in events:
        # A re-struck key cuts its own previous note (same string).
        later = [t2 for t2, p2, _ in events if p2 == p and t2 > t]
        if later:
            dur = min(dur, min(later) - t - 0.06)
        cents = tune + (rng.uniform(-8, 8) if variant == "detune" else 0.0)
        s = pianos.sample_for(piano, p, SR, rng, cents)
        if variant == "inharm" and p <= 60:
            s = sharpen(s, p, rng.uniform(0.004, 0.012))
        s = s[: int(dur * SR)].astype(np.float64)
        fade = min(len(s), int(0.03 * SR))
        s[-fade:] *= np.linspace(1, 0, fade)
        g = rng.uniform(0.5, 1.0) if vel_jitter else 1.0
        i = int(t * SR)
        n = min(len(s), len(y) - i)
        y[i : i + n] += g * s[:n]
    return y


def room(y, condition, variant="plain"):
    if variant == "speaker":
        # Digital piano / laptop speaker heard by a mic: no bass or air, a bit of clipping.
        b, a = butter(3, [250 / (SR / 2), 5500 / (SR / 2)], btype="band")
        y = np.tanh(2.0 * lfilter(b, a, y) / (np.max(np.abs(y)) + 1e-9))
    else:
        b, a = butter(2, [120 / (SR / 2), 7000 / (SR / 2)], btype="band")
        y = lfilter(b, a, y)
    if condition in ("room", "noisy"):
        ir_len = int(0.35 * SR)
        ir = rng.standard_normal(ir_len) * np.exp(-np.arange(ir_len) / (0.07 * SR))
        # Direct-to-reverberant ratio +3 dB: a laptop/phone about 1 m away.
        ir *= np.sqrt(0.5 / np.sum(ir**2))
        ir[0] = 1.0
        y = np.convolve(y, ir)[: len(y)]
    y = y / (np.max(np.abs(y)) + 1e-9) * 0.5
    snr_db = {"clean": 50, "room": 35, "noisy": 20}[condition]
    noise = rng.standard_normal(len(y))
    noise = lfilter(*butter(1, 2000 / (SR / 2)), noise)  # pinkish hum/hiss
    noise *= np.sqrt(np.mean(y**2)) / np.sqrt(np.mean(noise**2)) / 10 ** (snr_db / 20)
    return y + noise


def write_wav(path, y):
    pcm = (np.clip(y, -1, 1) * 32767).astype("<i2")
    import wave

    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


CHORDS = [
    [60, 64, 67], [55, 59, 62], [53, 57, 60], [57, 60, 64], [48, 52, 55],
    [60, 64], [60, 67], [62, 65], [64, 67], [48, 60], [43, 59, 62], [41, 57, 60],
]
# Octave and fifth doublings: the detector does not report a note that is an
# octave/twelfth of one already found (docs/research/mic-input.md), so these
# show that limit in the score instead of hiding it.
DOUBLED = [
    [60, 72], [55, 67], [48, 55, 60], [60, 67, 72], [53, 60, 65], [43, 55, 62],
]
# Melodies: public-domain tunes (Ode to Joy, Twinkle Twinkle), our own timing.
ODE = [64, 64, 65, 67, 67, 65, 64, 62, 60, 60, 62, 64, 64, 62, 62]
TWINKLE = [60, 60, 67, 67, 69, 69, 67, 65, 65, 64, 64, 62, 62, 60]


NOISES = ("typing", "chatter", "hum", "knock")


def noise_clip(kind, length):
    """Non-piano room sounds, peak-normalised like the note clips."""
    n = int(length * SR)
    y = np.zeros(n)
    t = np.arange(n) / SR
    if kind == "typing":
        # 6-9 key clicks per second: 3-8 ms bursts, bright, fast decay.
        tt = 0.2
        while tt < length - 0.05:
            i = int(tt * SR)
            k = int(rng.uniform(0.003, 0.008) * SR)
            burst = rng.standard_normal(k) * np.exp(-np.arange(k) / (0.0015 * SR))
            burst = lfilter(*butter(2, 1500 / (SR / 2), btype="high"), burst)
            y[i : i + k] += burst * rng.uniform(0.4, 1.0)
            tt += rng.uniform(0.08, 0.2)
    elif kind == "chatter":
        # Voiced buzz with a gliding pitch (100-250 Hz) through two moving
        # formants, syllable-rate amplitude modulation: speech-like.
        f0 = 150 + 60 * np.sin(2 * np.pi * 0.7 * t) + 30 * np.sin(2 * np.pi * 2.3 * t)
        phase = 2 * np.pi * np.cumsum(f0) / SR
        src = np.sign(np.sin(phase)) * 0.5 + 0.1 * rng.standard_normal(n)
        out = np.zeros(n)
        for fc in (500, 1500):
            b, a = butter(2, [fc * 0.7 / (SR / 2), fc * 1.3 / (SR / 2)], btype="band")
            out += lfilter(b, a, src)
        env = np.clip(np.sin(2 * np.pi * 4 * t + rng.uniform(0, 6)), 0, None) ** 0.5
        y = out * env
    elif kind == "hum":
        # Fan broadband + 50 Hz mains with harmonics, slowly wavering.
        y = lfilter(*butter(1, 800 / (SR / 2)), rng.standard_normal(n)) * 0.5
        for h in range(1, 6):
            y += np.sin(2 * np.pi * 50 * h * t) / h * (1 + 0.2 * np.sin(2 * np.pi * 0.3 * t))
    elif kind == "knock":
        # Low thumps (door, desk): 2 per second, 60-200 Hz damped.
        tt = 0.3
        while tt < length - 0.2:
            i = int(tt * SR)
            k = int(0.15 * SR)
            f = rng.uniform(60, 200)
            y[i : i + k] += np.sin(2 * np.pi * f * np.arange(k) / SR) * np.exp(-np.arange(k) / (0.03 * SR))
            tt += rng.uniform(0.35, 0.7)
    return y / (np.max(np.abs(y)) + 1e-9) * 0.5


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    truth = {}
    clips = []
    for p in range(36, 97, 2):
        clips.append((f"single_{p}", [(0.4, p, 1.2)], 1.8, "single"))
    for c in CHORDS:
        name = "chord_" + "-".join(map(str, c))
        ev = [(0.4 + rng.uniform(0, 0.02), p, 1.5) for p in c]
        clips.append((name, ev, 2.0, "chord"))
    for c in DOUBLED:
        name = "doubled_" + "-".join(map(str, c))
        ev = [(0.4 + rng.uniform(0, 0.02), p, 1.5) for p in c]
        clips.append((name, ev, 2.0, "doubled"))
    for name, tune, beat in (("ode", ODE, 0.45), ("twinkle", TWINKLE, 0.5)):
        ev = [(0.4 + i * beat, p, beat * 1.6) for i, p in enumerate(tune)]
        clips.append((f"melody_{name}", ev, 0.8 + len(tune) * beat, "melody"))
    # Left-hand bass + right-hand melody, overlapping.
    ev = [(0.4 + i * 0.5, p, 0.7) for i, p in enumerate(ODE[:8])]
    ev += [(0.4 + i * 2.0, b, 2.2) for i, b in enumerate([48, 43, 48, 43])]
    clips.append(("hands_ode", ev, 8.8, "two-hands"))

    # Noise only (no notes): every detection is a false note. Synthetic
    # stand-ins for a room: computer-keyboard typing, chatter-like voiced
    # noise, fan/mains hum, door knocks.
    for kind in NOISES:
        clips.append((f"noise_{kind}", [], 8.0, "noise"))

    for cond in ("clean", "room", "noisy"):
        for i, (name, ev, length, kind) in enumerate(clips):
            variant = VARIANTS[i % len(VARIANTS)]
            # Held-out test set: every third clip in list order (spans every
            # kind), fixed by position and never used for tuning.
            split = "test" if i % 3 == 2 else "tune"
            # Noise clips have no piano; render them once.
            for piano in (PIANOS if ev else ("none",)):
                fname = f"{piano}__{cond}__{name}.wav"
                y = render(ev, length, piano, variant) if ev else noise_clip(name[6:], length)
                write_wav(OUT / fname, room(y, cond, variant if ev else "plain"))
                truth[fname] = {
                    "split": split,
                    "condition": cond,
                    "kind": kind,
                    "piano": piano,
                    "variant": variant if ev else "plain",
                    "notes": [{"t": round(t, 4), "pitch": p} for t, p, _ in sorted(ev)],
                }
    (OUT / "truth.json").write_text(json.dumps(truth, indent=1))
    print(f"wrote {len(truth)} clips to {OUT}", file=sys.stderr)


if __name__ == "__main__":
    main()
