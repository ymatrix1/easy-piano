r"""Independent noise/voice test set: speech from eSpeak NG (a synthesizer the
training generators in gen.py never used) as `speech` clips (no notes: every
detection is a false note) and mixed over piano clips from tools/mic-fixtures
as `mixed` (piano at 0 / +6 dB over the speech, truth = the piano's notes).
Output: tools/mic-fixtures-noise/ (git-ignored), scored by eval_model.py and
app/tool/mic_eval.dart like the other fixture dirs. Needs espeak-ng on PATH or
in C:\Program Files\eSpeak NG.

Usage: uv run python export_noise.py
"""

import json
import shutil
import subprocess
import tempfile
import wave
from pathlib import Path

import numpy as np

from pianos import ROOT

OUT = ROOT / "tools" / "mic-fixtures-noise"
FIX = ROOT / "tools" / "mic-fixtures"
SR = 24000
ESPEAK = shutil.which("espeak-ng") or r"C:\Program Files\eSpeak NG\espeak-ng.exe"
TEXT = [
    "The quick brown fox jumps over the lazy dog while the children play the piano in the next room.",
    "Okay, let us start the lesson. Place your right thumb on middle C and press the key gently, then count one two three four.",
    "Voce pode tocar essa musica devagar, primeiro com a mao direita e depois com as duas maos juntas.",
    "Hoy vamos a practicar las escalas. Escucha con atencion y repite despues de mi, por favor.",
    "Did you hear that? I think somebody is at the door. Could you turn the music down for a moment?",
    "Twinkle twinkle little star, how I wonder what you are, up above the world so high, like a diamond in the sky.",
]
VOICES = [
    "en+m1",
    "en+m3",
    "en+m7",
    "en+f2",
    "en+f4",
    "en-us+m2",
    "pt+m1",
    "pt+f3",
    "es+f1",
    "de+m4",
    "fr+f2",
    "en+croak",
]


def speak(voice, text, speed, pitch):
    with tempfile.TemporaryDirectory() as d:
        f = Path(d) / "s.wav"
        subprocess.run(
            [ESPEAK, "-v", voice, "-s", str(speed), "-p", str(pitch), "-w", str(f), text],
            check=True,
            capture_output=True,
        )
        with wave.open(str(f), "rb") as w:
            sr = w.getframerate()
            x = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float32) / 32768
    from scipy.signal import resample_poly

    g = np.gcd(SR, sr)
    return resample_poly(x, SR // g, sr // g)


def read(path):
    with wave.open(str(path), "rb") as w:
        return np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float32) / 32768


def write(path, y):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(y, -1, 1) * 32767).astype("<i2").tobytes())


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(11)
    truth = {}

    def talk(n):
        y = np.zeros(0, np.float32)
        while len(y) < n:
            v = VOICES[int(rng.integers(len(VOICES)))]
            y = np.concatenate(
                [
                    y,
                    speak(
                        v,
                        TEXT[int(rng.integers(len(TEXT)))],
                        int(rng.integers(120, 200)),
                        int(rng.integers(20, 80)),
                    ),
                    np.zeros(int(rng.uniform(0.1, 0.5) * SR), np.float32),
                ]
            )
        return y[:n]

    for i in range(10):
        y = talk(8 * SR)
        y = y / (np.abs(y).max() + 1e-9) * 10 ** rng.uniform(-1.6, -0.4)
        y = y + rng.standard_normal(len(y)).astype(np.float32) * 10 ** rng.uniform(-4, -2.5)
        name = f"espeak__room__speech_{i:02d}.wav"
        write(OUT / name, y)
        truth[name] = {
            "split": "test",
            "condition": "room",
            "kind": "speech",
            "piano": "none",
            "variant": "plain",
            "notes": [],
        }
    src = json.loads((FIX / "truth.json").read_text())
    picks = [
        n
        for n, v in src.items()
        if v["split"] == "test" and v["kind"] in ("single", "chord", "melody") and v["condition"] == "room"
    ]
    for j, n in enumerate(picks):
        piano = read(FIX / n)
        db = [0, 6][j % 2]
        sp = talk(len(piano))
        sp = sp / (np.sqrt(np.mean(sp**2)) + 1e-9) * np.sqrt(np.mean(piano**2)) / 10 ** (db / 20)
        y = piano + sp
        name = f"{src[n]['piano']}__room__mixed_{n.split('__')[-1][:-4]}_{db}dB.wav"
        write(OUT / name, y / (np.abs(y).max() + 1e-9) * 0.5)
        truth[name] = {**src[n], "kind": "mixed", "condition": "room", "split": "test"}
    (OUT / "truth.json").write_text(json.dumps(truth, indent=1))
    print(len(truth), "clips")


if __name__ == "__main__":
    main()
