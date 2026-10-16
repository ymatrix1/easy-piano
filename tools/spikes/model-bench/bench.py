"""Benchmark audio-to-notes models on the synthetic PD test set.

Each model runs on each input; notes are written as
`<out>/<model>__<input>.txt` (pitch start_s duration_s amplitude) and scored
later by `cargo run --example score_notes` in core/ so every model goes through
the same cleanup and melody steps. See docs/research/song-import.md.

Usage: python bench.py <audio_dir> <out_dir> [model ...]
Inputs expected in <audio_dir>: piano.wav, mix.wav, nopiano.wav, plus stems
made by the `demucs` model (stems/<input>/<stem>.wav).
"""
import json
import subprocess
import sys
import time
import traceback
from pathlib import Path

AUDIO, OUT = Path(sys.argv[1]), Path(sys.argv[2])
OUT.mkdir(parents=True, exist_ok=True)
STEMS = AUDIO / "stems"


def write_notes(name, rows, header):
    """rows: iterable of (pitch, start, dur, amp)."""
    path = OUT / f"{name}.txt"
    with open(path, "w") as f:
        f.write(f"# synthetic: {header}\n")
        for p, s, d, a in sorted(rows, key=lambda r: (r[1], r[0])):
            f.write(f"{int(p)} {s:.4f} {d:.4f} {a:.3f}\n")
    return path


def midi_rows(midi_path):
    import pretty_midi

    pm = pretty_midi.PrettyMIDI(str(midi_path))
    return [
        (n.pitch, n.start, n.end - n.start, n.velocity / 127)
        for inst in pm.instruments
        if not inst.is_drum
        for n in inst.notes
    ]


# Inputs each transcription model sees. Stems come from the demucs step.
def inputs():
    items = {k: AUDIO / f"{k}.wav" for k in ("piano", "mix", "nopiano")}
    for src, stem in [("mix", "piano"), ("mix", "other"), ("nopiano", "vocals"), ("nopiano", "other")]:
        p = STEMS / "htdemucs_6s" / src / f"{stem}.wav"
        if p.exists():
            items[f"{src}-{stem}"] = p
    return items


def run_demucs():
    """6-stem Demucs (has a piano stem) on the two mixes."""
    for src in ("mix", "nopiano"):
        t0 = time.perf_counter()
        subprocess.run(
            [sys.executable, "-m", "demucs", "-n", "htdemucs_6s", "-d", "cpu", "-o", str(STEMS), str(AUDIO / f"{src}.wav")],
            check=True,
        )
        yield f"demucs_6s {src}: {time.perf_counter() - t0:.1f} s"


def basic_pitch(name, path):
    from basic_pitch.inference import predict

    _, _, events = predict(str(path))
    return [(p, s, e - s, a) for s, e, p, a, _ in events], "Basic Pitch 0.4 (Python, default thresholds)"


_bytedance = None


def bytedance(name, path):
    global _bytedance
    from piano_transcription_inference import PianoTranscription, load_audio, sample_rate

    _bytedance = _bytedance or PianoTranscription(device="cpu")
    audio, _ = load_audio(str(path), sr=sample_rate, mono=True)
    res = _bytedance.transcribe(audio, str(OUT / f"bytedance__{name}.mid"))
    rows = [(e["midi_note"], e["onset_time"], e["offset_time"] - e["onset_time"], e["velocity"] / 127) for e in res["est_note_events"]]
    return rows, "ByteDance piano_transcription_inference (Kong et al. 2021)"


def muscriptor(name, path):
    mid = OUT / f"muscriptor__{name}.mid"
    exe = Path(sys.executable).with_name("muscriptor.exe")
    subprocess.run([str(exe if exe.exists() else "muscriptor"), "transcribe", str(path),
                    "-o", str(mid), "-m", "small", "-d", "cpu"], check=True)
    rows = midi_rows(mid)
    return rows, "MuScriptor small (CC BY-NC weights, reference only)"


_p2p = None


def pop2piano(name, path):
    global _p2p
    import librosa
    from transformers import Pop2PianoForConditionalGeneration, Pop2PianoProcessor

    if _p2p is None:
        _p2p = (
            Pop2PianoForConditionalGeneration.from_pretrained("sweetcocoa/pop2piano"),
            Pop2PianoProcessor.from_pretrained("sweetcocoa/pop2piano"),
        )
    model, proc = _p2p
    audio, sr = librosa.load(str(path), sr=44100)
    feats = proc(audio=audio, sampling_rate=sr, return_tensors="pt")
    ids = model.generate(input_features=feats["input_features"], composer="composer1")
    pm = proc.batch_decode(token_ids=ids, feature_extractor_output=feats)["pretty_midi_objects"][0]
    mid = OUT / f"pop2piano__{name}.mid"
    pm.write(str(mid))
    return midi_rows(mid), "pop2piano (piano cover generator, not a transcriber)"


MODELS = {"basic_pitch": basic_pitch, "bytedance": bytedance, "muscriptor": muscriptor, "pop2piano": pop2piano}

if __name__ == "__main__":
    wanted = sys.argv[3:] or ["demucs", *MODELS]
    report = []
    if "demucs" in wanted:
        try:
            report += list(run_demucs())
        except Exception:
            report.append(f"demucs FAILED: {traceback.format_exc(limit=1)}")
    for model in [m for m in wanted if m in MODELS]:
        for name, path in inputs().items():
            t0 = time.perf_counter()
            try:
                rows, header = MODELS[model](name, path)
                write_notes(f"{model}__{name}", rows, f"{header} on {path.name}")
                report.append(f"{model:12} {name:16} {time.perf_counter() - t0:7.1f} s  notes={len(rows)}")
            except Exception as e:
                report.append(f"{model:12} {name:16} FAILED: {type(e).__name__}: {str(e)[:160]}")
            print(report[-1], flush=True)
    (OUT / "report.json").write_text(json.dumps(report, indent=1))
    print("\n".join(report))
