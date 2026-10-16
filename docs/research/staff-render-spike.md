# Staff render spike

Checked: 2026-10-16. Bean: piano-jist. Setup: Flutter 3.47.7 web release (CanvasKit), Chrome on Windows 11, high-refresh monitor; served by `tools/serve_web.py`. Code: `app/lib/ui/staff/`.

## Question

Can a Bravura (SMuFL) grand staff scroll smoothly on Flutter web with `CustomPainter`?

## Method

- Grand staff, G and F clefs, noteheads (whole/half/black), stems, sharps and ledger lines drawn as Bravura glyphs via cached `TextPainter`s.
- Score: own simplified Ode to Joy (PD) repeated 24 times, 456 notes. Notes scroll toward a playhead at 100 bpm; only notes in the visible beat window are laid out (binary search on sorted onsets).
- Painter repaints from a `ValueNotifier` inside a `RepaintBoundary`; stats from `Ticker` intervals and `FrameTiming`.

## Results

| Metric | Value |
|---|---|
| fps | ≈ 180 (display refresh) |
| Frame interval p95 | 5.6 ms |
| Janky frames (> 1.5× 60 Hz budget) | 0.0 % |
| Raster p95 | 0.52 ms |
| Bravura font | 0.85 MB OTF (OFL), not subset yet |

Visual check: clefs, staff lines, ledger line for middle C, note positions and playhead render correctly (screenshot reviewed in Chrome).

## Implications

- `CustomPainter` + SMuFL glyphs is enough for the practice studio; no engraving library needed for Phase 1.
- Large headroom (raster < 1 ms) leaves budget for falling notes, particles and hit colors.
- Subset Bravura to used glyphs to cut first-load size (~0.85 MB now).

## Follow-ups

- Beams, ties, rests, time and key signatures in the painter (Phase 1).
- Measure on a mid-range Android phone once mobile builds exist (bean piano-qd1r).
- Bean: subset Bravura font.
