"""Synthetic test audio for the song-import spike. Own rendering of a public
domain melody (Ode to Joy, Beethoven); no recorded music.

Writes, 44.1 kHz stereo:
- public/piano.wav: piano-like melody only
- public/mix.wav: piano melody + bass + drums
- public/nopiano.wav: no piano at all; a sung-like voice carries the melody
  over plucked guitar chords, bass and drums
plus public/truth.json (melody notes) and public/truth_chords.json (one chord
per bar) for scoring.
"""
import json, sys, wave
import numpy as np

SR = 44100
BPM = 100
BEAT = 60 / BPM
MELODY = [(64,1),(64,1),(65,1),(67,1),(67,1),(65,1),(64,1),(62,1),
          (60,1),(60,1),(62,1),(64,1),(64,1.5),(62,.5),(62,2)] * 2
BASS = [48, 43, 48, 43] * 2  # one per bar
CHORDS = [("C", [60, 64, 67]), ("G", [55, 59, 62])] * 4  # one per bar, matches BASS

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

def voice(m, dur, rng):
    """Sung-like tone: vibrato, breathy attack, vowel-ish harmonic weights."""
    t = np.arange(int(SR * dur)) / SR
    f = hz(m) * (1 + 0.012 * np.sin(2 * np.pi * 5.5 * t) * np.minimum(1, t * 3))
    phase = 2 * np.pi * np.cumsum(f) / SR
    tone = sum(a * np.sin(k * phase) for k, a in [(1, 1), (2, .6), (3, .45), (4, .2), (5, .15)])
    env = np.minimum(1, t * 12) * np.minimum(1, (dur - t) * 20)
    return tone * env + rng.normal(0, .02, len(t)) * env

def pluck(m, dur, rng):
    """Karplus-Strong plucked string."""
    n = int(SR * dur); period = int(SR / hz(m))
    buf = rng.uniform(-1, 1, period); out = np.zeros(n)
    for i in range(n):
        out[i] = buf[i % period]
        buf[i % period] = 0.5 * (buf[i % period] + buf[(i + 1) % period]) * 0.996
    return out

def render_nopiano(drums):
    rng = np.random.default_rng(1)
    total = sum(d for _, d in MELODY) * BEAT + 1
    voc = np.zeros(int(SR * total)); gtr = np.zeros_like(voc); bass = np.zeros_like(voc)
    b = 0.0
    for m, d in MELODY:
        s = int(b * BEAT * SR); x = voice(m, d * BEAT * 0.95, rng); voc[s:s + len(x)] += x; b += d
    for bar, (_, notes) in enumerate(CHORDS):
        for beat in range(4):  # strum each beat, slight spread between strings
            for k, m in enumerate(notes):
                s = int(((bar * 4 + beat) * BEAT + k * 0.012) * SR)
                x = pluck(m, BEAT * 0.9, rng) * 0.5; gtr[s:s + len(x)] += x
        s = int(bar * 4 * BEAT * SR); t = np.arange(int(4 * BEAT * SR)) / SR
        x = np.sin(2 * np.pi * hz(BASS[bar]) * t) * np.exp(-1.2 * t); bass[s:s + len(x)] += x
    n = min(len(voc), len(drums))
    return voc[:n] * .7 + gtr[:n] * .45 + bass[:n] * .5 + drums[:n] * .4

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
    write(f"{out}/nopiano.wav", render_nopiano(drums))
    json.dump(truth, open(f"{out}/truth.json", "w"), indent=0)
    json.dump([{"bar": i, "chord": c, "root": BASS[i]} for i, (c, _) in enumerate(CHORDS)],
              open(f"{out}/truth_chords.json", "w"), indent=0)
    print(len(truth), "notes,", round(len(mel) / SR, 1), "s")
