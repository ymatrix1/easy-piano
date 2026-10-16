"""End-to-end personal song import, local only (D11).

Takes Demucs htdemucs_6s stems of a song the user owns, detects tempo,
transcribes melody candidates, runs the core arranger per level and writes
MIDI files to listen to or play. Outputs stay on the machine; never commit
them or the audio.

Usage: python import_song.py <stems_dir> <out_dir> <core_dir>
  stems_dir: folder with vocals.wav, piano.wav, guitar.wav, bass.wav, other.wav
  core_dir:  path to core/ (built examples are used for arranging)
"""
import subprocess
import sys
from pathlib import Path

import librosa
import numpy as np
import pretty_midi

STEMS, OUT, CORE = (Path(a) for a in sys.argv[1:4])
OUT.mkdir(parents=True, exist_ok=True)
ARRANGE = CORE / "target" / "debug" / "examples" / "arrange_notes.exe"


def write_notes(path, rows):
    with open(path, "w") as f:
        f.write("# personal import, local only\n")
        for p, s, d, a in sorted(rows, key=lambda r: (r[1], r[0])):
            f.write(f"{int(p)} {s:.4f} {d:.4f} {a:.3f}\n")


def basic_pitch_rows(wav):
    from basic_pitch.inference import predict

    _, _, events = predict(str(wav))
    return [(p, s, e - s, a) for s, e, p, a, _ in events]


def pyin_rows(wav):
    y, sr = librosa.load(str(wav), sr=22050, mono=True)
    hop = 256
    f0, voiced, prob = librosa.pyin(y, fmin=80, fmax=1000, sr=sr, hop_length=hop)
    midi = np.where(voiced, np.round(librosa.hz_to_midi(np.nan_to_num(f0, nan=1.0))), -1)
    rows, start, cur, dt = [], None, -1, hop / sr
    for i, m in enumerate(list(midi) + [-1]):
        if m != cur:
            if cur >= 0 and (i - start) * dt >= 0.08:
                rows.append((int(cur), start * dt, (i - start) * dt, float(np.nanmean(prob[start:i]))))
            start, cur = i, m
    return rows


def tempo(wav):
    y, sr = librosa.load(str(wav), sr=22050, mono=True)
    bpm, _ = librosa.beat.beat_track(y=y, sr=sr)
    return float(np.atleast_1d(bpm)[0])


def to_midi(arranged_txt, bpm, midi_path):
    pm = pretty_midi.PrettyMIDI(initial_tempo=bpm)
    rh, lh = pretty_midi.Instrument(0, name="RH"), pretty_midi.Instrument(0, name="LH")
    spb = 60.0 / bpm
    for line in arranged_txt.splitlines():
        p, beat, beats, hand = line.split()
        n = pretty_midi.Note(80, int(p), float(beat) * spb, (float(beat) + float(beats)) * spb)
        (lh if hand == "L" else rh).notes.append(n)
    pm.instruments += [rh, lh]
    pm.write(str(midi_path))
    return len(rh.notes), len(lh.notes)


if __name__ == "__main__":
    drums_bass = STEMS / "drums.wav"
    bpm = tempo(drums_bass)
    print(f"tempo ≈ {bpm:.1f} bpm")
    sources = {
        "vocals-pyin": pyin_rows(STEMS / "vocals.wav"),
        "vocals-bp": basic_pitch_rows(STEMS / "vocals.wav"),
        "piano-bp": basic_pitch_rows(STEMS / "piano.wav"),
        "other-bp": basic_pitch_rows(STEMS / "other.wav"),
    }
    # Bass stem gives left-hand roots to the intermediate arrangement.
    bass = basic_pitch_rows(STEMS / "bass.wav")
    for name, rows in sources.items():
        write_notes(OUT / f"{name}.txt", rows)
        merged = OUT / f"{name}+bass.txt"
        write_notes(merged, rows + bass)
        for level in ("beginner", "intermediate", "advanced"):
            src = merged if level != "beginner" else OUT / f"{name}.txt"
            txt = subprocess.run([str(ARRANGE), str(src), f"{bpm:.2f}", level],
                                 capture_output=True, text=True, check=True).stdout
            rh, lh = to_midi(txt, bpm, OUT / f"{name}__{level}.mid")
            print(f"{name:12} {level:12} raw={len(rows):4}  RH={rh:4} LH={lh:3}")
