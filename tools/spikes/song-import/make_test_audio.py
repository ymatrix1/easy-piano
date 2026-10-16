"""Synthetic test audio for the song-import spike. Own rendering of a public
domain melody (Ode to Joy, Beethoven); no recorded music.

Writes public/piano.wav (piano-like melody only) and public/mix.wav
(melody + bass + drums), 44.1 kHz stereo, plus public/truth.json with the
exact notes for scoring transcription.
"""
import json, sys, wave
import numpy as np

SR = 44100
BPM = 100
BEAT = 60 / BPM
MELODY = [(64,1),(64,1),(65,1),(67,1),(67,1),(65,1),(64,1),(62,1),
          (60,1),(60,1),(62,1),(64,1),(64,1.5),(62,.5),(62,2)] * 2
BASS = [48, 43, 48, 43] * 2  # one per bar

def hz(m): return 440 * 2 ** ((m - 69) / 12)

def piano(m, dur):
    t = np.arange(int(SR * dur)) / SR
    f = hz(m)
    tone = sum(a * np.sin(2 * np.pi * f * k * t) for k, a in [(1, 1), (2, .5), (3, .25), (4, .12)])
    env = np.exp(-3 * t) * np.minimum(1, t * 200)
    return tone * env

def render():
    total = sum(d for _, d in MELODY) * BEAT + 1
    mel = np.zeros(int(SR * total)); bass = np.zeros_like(mel); drums = np.zeros_like(mel)
    truth, b = [], 0.0
    for m, d in MELODY:
        s = int(b * BEAT * SR); x = piano(m, d * BEAT * 0.95)
        mel[s:s + len(x)] += x; truth.append({"pitch": m, "start": b * BEAT, "end": (b + d * .95) * BEAT}); b += d
    for i, m in enumerate(BASS):
        s = int(i * 4 * BEAT * SR); t = np.arange(int(4 * BEAT * SR)) / SR
        x = np.sin(2 * np.pi * hz(m) * t) * np.exp(-1.2 * t); bass[s:s + len(x)] += x
    rng = np.random.default_rng(0)
    for k in range(int(b)):
        s = int(k * BEAT * SR); n = int(.08 * SR); t = np.arange(n) / SR
        kick = np.sin(2 * np.pi * 60 * t) * np.exp(-40 * t) if k % 2 == 0 else 0
        snare = rng.normal(0, 1, n) * np.exp(-30 * t) * (0 if k % 2 == 0 else .5)
        drums[s:s + n] += kick + snare
    return mel, bass, drums, truth

def write(path, mono):
    x = mono / (np.max(np.abs(mono)) + 1e-9) * .8
    st = np.stack([x, x], 1); pcm = (st * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "public"
    mel, bass, drums, truth = render()
    write(f"{out}/piano.wav", mel)
    write(f"{out}/mix.wav", mel * .6 + bass * .5 + drums * .5)
    json.dump(truth, open(f"{out}/truth.json", "w"), indent=0)
    print(len(truth), "notes,", round(len(mel) / SR, 1), "s")
