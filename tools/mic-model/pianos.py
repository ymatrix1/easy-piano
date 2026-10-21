"""Piano sample sets for mic fixtures and model training (docs/research/mic-input.md).

Three license-clean sets, extracted once into git-ignored data/pianos/<name>/
as mono 16-bit WAVs named `<midi>_<layer>.wav` (root note, velocity layer):

| name       | source                                   | license      |
|------------|------------------------------------------|--------------|
| salamander | app/assets/piano (Yamaha C5, Salamander) | CC-BY 3.0    |
| kw         | FreePats Upright Piano KW (Kawai upright)| CC0 1.0      |
| ydp        | FreePats YDP Grand (Zenph Disklavier Pro)| CC-BY 3.0    |

Download the archives into data/pianos/ (see docs/research/mic-input.md),
then `python pianos.py extract` (needs sf2utils: run it from the uv venv).
`load(name, sr)` returns {midi: [float32 arrays]} resampled to `sr`.
"""

import re
import subprocess
import sys
import wave
from math import gcd
from pathlib import Path

import numpy as np
from scipy.signal import butter, resample_poly, sosfiltfilt

ROOT = Path(__file__).resolve().parent.parent.parent
DATA = ROOT / "data" / "pianos"
PIANOS = ("salamander", "kw", "ydp")
_NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
_cache = {}


def midi_of(name):
    """'D#3' / 'Eb4' / 'A0' -> MIDI number (C4 = 60)."""
    m = re.fullmatch(r"([A-G])([#b]?)(-?\d)", name)
    n = _NOTE[m.group(1)] + {"": 0, "#": 1, "b": -1}[m.group(2)]
    return (int(m.group(3)) + 1) * 12 + n


def _decode(path):
    raw = subprocess.run(
        ["ffmpeg", "-v", "quiet", "-i", str(path), "-ac", "1", "-f", "s16le", "-"],
        capture_output=True,
        check=True,
    ).stdout
    sr = int(
        subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "stream=sample_rate", "-of", "csv=p=0", str(path)],
            capture_output=True,
            check=True,
            text=True,
        ).stdout.strip()
    )
    return sr, np.frombuffer(raw, dtype="<i2")


def _write(path, sr, pcm):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(np.asarray(pcm, dtype="<i2").tobytes())


def extract():
    sal = DATA / "salamander"
    sal.mkdir(parents=True, exist_ok=True)
    for f in sorted((ROOT / "app" / "assets" / "piano").glob("*.mp3")):
        sr, pcm = _decode(f)
        _write(sal / f"{midi_of(f.stem)}_0.wav", sr, pcm)
    kw = DATA / "kw"
    for f in sorted(kw.rglob("samples/*.flac")):
        m = re.fullmatch(r"([A-G]#?\d)v([HL])", f.stem)
        sr, pcm = _decode(f)
        _write(kw / f"{midi_of(m.group(1))}_{'1' if m.group(2) == 'H' else '0'}.wav", sr, pcm)
    from sf2utils.sf2parse import Sf2File

    ydp = DATA / "ydp"
    for old in ydp.glob("*.wav"):
        old.unlink()
    sf2 = next(DATA.glob("ydp/**/*.sf2"))
    with open(sf2, "rb") as fh:
        s = Sf2File(fh)
        seen = {}
        for smp in s.samples:
            if getattr(smp, "sample_type", None) not in (
                1,
                4,
            ):  # mono or left; the right half of a pair is redundant
                continue
            try:
                raw = smp.raw_sample_data
            except AttributeError:  # EOS terminator record
                continue
            if not raw or smp.duration < 0.5:
                continue
            k = smp.original_pitch
            layer = seen.get(k, 0)
            seen[k] = layer + 1
            pcm = np.frombuffer(raw, dtype="<i2")
            _write(ydp / f"{k}_{layer}.wav", smp.sample_rate, pcm)
    for p in PIANOS:
        print(p, len(list((DATA / p).glob("*.wav"))), "samples")


def load(name, sr):
    """{midi: [float32 mono at sr]} for one piano; cached."""
    key = (name, sr)
    if key not in _cache:
        out = {}
        for f in sorted((DATA / name).glob("*.wav")):
            midi = int(f.stem.split("_")[0])
            with wave.open(str(f), "rb") as w:
                src = w.getframerate()
                x = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float32) / 32768
            g = gcd(sr, src)
            out.setdefault(midi, []).append(resample_poly(x, sr // g, src // g).astype(np.float32))
        _cache[key] = out
    return _cache[key]


def sharpen(x, pitch, amount, sr):
    """Stronger bass inharmonicity: partials from the 3rd up are raised by
    `amount` (0.4-1.2 %) by resampling the high band, as stiff low strings do."""
    if len(x) < 64:
        return x
    f0 = 440 * 2 ** ((pitch - 69) / 12)
    sos = butter(4, min(3 * f0, sr * 0.4) / (sr / 2), btype="high", output="sos")
    hi = sosfiltfilt(sos, x)
    num = round((1 + amount) * 1000)
    g = gcd(num, 1000)
    hi2 = resample_poly(hi, 1000 // g, num // g)[: len(x)]
    hi2 = np.pad(hi2, (0, len(x) - len(hi2)))
    return (x - hi + hi2).astype(np.float32)


def sample_for(piano, pitch, sr, rng, detune_cents=0.0):
    """Nearest sample of `piano`, pitch-shifted by resampling to `pitch` (+ detune)."""
    bank = load(piano, sr)
    base = min(bank, key=lambda p: abs(p - pitch))
    x = bank[base][rng.integers(len(bank[base]))]
    ratio = 2 ** ((pitch - base + detune_cents / 100) / 12)
    if ratio == 1:
        return x
    # Resample by an exact rational approximation of the ratio.
    num = round(ratio * 1000)
    g = gcd(num, 1000)
    return resample_poly(x, 1000 // g, num // g).astype(np.float32)


if __name__ == "__main__":
    if sys.argv[1:] == ["extract"]:
        extract()
    else:
        sys.exit(__doc__)
