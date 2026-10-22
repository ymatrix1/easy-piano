# Melody model: improvements for later versions

Checked: 2026-10-21

Sources: model card `docs/models/melody-v1.md`, spec `docs/specs/melody-model.md`, run `base1` results (`tools/melody-model/releases/`), decisions D17–D28, discussions with the user in the melody-model session (2026-10-20/21).

Question: what should the next versions of the melody model improve, in what order, and what does each need?

## Where v1 stands

- 11.1M-param compound decoder, best val loss 0.875, 37 min on an RTX 4070 SUPER.
- Rubric pass 77% (123/160 over 10 lesson nodes). Taught-set rules always hold; failures are unmet required patterns.
- 0.3–0.4 s per 8-bar tune in Chrome (int8, WASM). 8 batched candidates ~0.95 s (WASM, 4 threads; WebGPU slower on the measured desktop).
- Covers Piano Basics to Essentials III. Not advanced material: one voice per hand, no tuplets.

## Improvements, by value for effort

| # | Improvement | Needs retrain? | Effort | Value | Bean |
|---|---|---|---|---|---|
| 1 | User ratings of the 36-tune blind listening set | no | 15 min (user) | highest: only quality signal | piano-blr4 (open criterion) |
| 2 | Steer decoding toward unmet required patterns near the end of a tune (force or boost the required pitch, accidental or rhythm) | no | ½ day | rubric 77% → ~90%+ | piano-z0m5 |
| 3 | Seed-variation knob: variations on a known (PD/our) song, closeness 0–1, via kept plan/bars + FIM | no | ½ day | strong for teaching | piano-2uz9 |
| 4 | Style-strength knob (classifier-free guidance on style tokens; trained with 20% style dropout already) | no | few hours | better style control | piano-2uz9 |
| 5 | Calibrate the similarity check (known-innocent vs known-copy sets, min length and information) and decide block vs report (D27) | no | 1 day | safety for course content | piano-vx1w |
| 6 | Style labels for the 12,999 untagged PDMX tunes (keywords, then CLaMP 3/2 zero-shot or own classifier) | rebuild + retrain | 1–2 days | style control over all data | piano-oial |
| 7 | Per-level playability filters: keep hard tunes as `LEVEL_4/5` instead of dropping (range > 2 octaves, leaps > octave, big chords) | rebuild + retrain | ½ day | more data, toward advanced | piano-8v9d |
| 8 | Tuplets (triplets) in format, converter and tokenizer | rebuild + retrain | 1 day | ~12k more PDMX tunes; waltz/folk | piano-8v9d |
| 9 | Replace `difficulty.level_of` with the core difficulty evaluator (D26, PR #50) for `LEVEL_*` labels and a generation-time level check | rebuild + retrain | ½ day | consistent levels app-wide | piano-8v9d |
| 10 | Composer tokens for public-domain composers and traditional styles (Bach, Mozart, Irish trad, hymns); `COMPOSER_other` for the rest | retrain | 1 day | "like Bach" requests | piano-8v9d |
| 11 | Free-text conditioning via a text–music embedding (CLaMP 3 preferred, CLaMP 2 fallback; offline only) for styles and moods, not specific songs | retrain | several days | flexible requests | piano-8k2s |
| 12 | Preference tuning (DPO) on blind listening ratings | fine-tune | 1–2 days after enough ratings | musical quality | piano-8k2s |
| 13 | Two voices per hand, full chords, grace notes; pedal/dynamics tokens; ctx 2,048–4,096; 15–30M params | retrain + app (staff, grading) | weeks | advanced courses | piano-p4mu |
| 14 | int4 weights (~6 MB download), Web Worker decoding; phone latency measurement | re-export | ½–1 day | mobile practice mode | piano-c6v1 |

Already done in v1's follow-ups: WebGPU backend with WASM fallback, batched candidates (PR #48), SRC dropout for future runs, safetensors weights in the release.

Not worth it at our sizes: RWKV/Mamba-style architectures (sequences are 100–1,000 steps; attention's exact recall suits repeated motifs; weak ONNX support).

## Suggested versions

- **v1.1 (no retrain):** 1, 2, 3, 4, 14. Better pass rate, knobs, mobile.
- **v2 (data + retrain):** 5, 6, 7, 8, 9, 10; then retrain about 1–2 h. Optionally 12 once ratings exist.
- **v3 (advanced):** 11, 13. Needs app-side notation and grading work and its own decision.

## Implications

- v1.1 items improve what the app's practice mode serves today without new training data or licence questions.
- v2 changes the dataset, so a new 50-tune review gate and a new release (`melody-model-v2`, D24 process) are required.
- Free-text and composer requests raise copying risk; keep them to public-domain composers, traditional styles and moods while the similarity check only reports (D27).

## Follow-ups

Beans listed in the table; this page is the index.
