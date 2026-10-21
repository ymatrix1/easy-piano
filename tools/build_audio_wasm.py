"""Build the audio engine for the web AudioWorklet (D30 stage 3) and copy it
to app/web/audio_engine.wasm (git-ignored), which app/web/audio_worklet.js
runs. Needs the wasm32-unknown-unknown target. Run before `flutter build web`
or `flutter run -d chrome`.

Usage: python tools/build_audio_wasm.py
"""
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CRATE = ROOT / "audio" / "web"
subprocess.run(
    ["cargo", "build", "--release", "--target", "wasm32-unknown-unknown"],
    cwd=CRATE,
    check=True,
)
src = CRATE / "target" / "wasm32-unknown-unknown" / "release" / "easy_piano_audio_web.wasm"
dst = ROOT / "app" / "web" / "audio_engine.wasm"
shutil.copy2(src, dst)
print(f"{dst.relative_to(ROOT)}: {dst.stat().st_size / 1024:.0f} KiB")
