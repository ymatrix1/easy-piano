# Practice mode timing and rubric yield

Checked: 2026-10-21. Sources: own measurements, app release web build (`flutter build web --release`) served by `tools/serve_web.py` on localhost (COOP/COEP on, cross-origin isolated), model `melody-model-v1` int8 files staged by `stage_app_model.py` (sha256 = manifest), onnxruntime-web 1.30.0, 4 wasm threads.

Question: how long does the learner wait for a practice tune (cold and cached), what does one generation round cost, and how often does the rubric let a tune through?

## Setup

| Item | Value |
|---|---|
| Machine | Windows 11, 32 logical cores, same as [melody-browser.md](melody-browser.md) |
| Browser | HeadlessChrome 155 driven over CDP (a scratch script; the visible app pane runs as a background page and throttles timers, so its numbers were discarded) |
| Path measured | `web/melody/practice.js` exactly as the app calls it: Cache Storage → fetch → sha256 → `load` → `generateJson` (n = 4 candidates, temperature 0.9), same order as `ModelStore` + `WebTuneGenerator` |
| Not measured | Flutter UI frames around it (page transition, stage build) |
| Rubric | `content check` (same `rubric::check` the bridge's `check_generated` calls) on every candidate |

## Time to first tune (node `essentials-1/rests`, RH, 8 bars)

| Case | Fetch + verify | ORT sessions | First round (4 tunes) | Total |
|---|---|---|---|---|
| Cold (empty cache, 12.5 MB from localhost) | 297 ms | 585 ms | 876 ms | **1.76 s** |
| Cached (Cache Storage, re-verified) | 139 ms | 302 ms | 1031 ms | **1.47 s** |

Localhost hides network time: a 12.5 MB download on a real connection adds about 1 s at 100 Mbit/s and 10 s at 10 Mbit/s. The progress bar covers that part.

## Per round, all 41 nodes × 3 seeds (123 rounds, 4 candidates each)

| Hands | Rounds | Median | Max |
|---|---|---|---|
| RH | 45 | 536 ms | 1717 ms |
| LH | 9 | 736 ms | 996 ms |
| BOTH | 69 | 2165 ms | 8413 ms |
| All | 123 | 1065 ms (p90 3070 ms) | 8413 ms |

Per tune (÷ 4): about 130–270 ms one hand, 540 ms both hands, in line with melody-browser.md (0.3–0.4 s per 8-bar tune). Two-hand nodes are slower because sequences are longer (both hands, up to 16 bars).

## Rubric yield (same 492 candidates)

| Measure | Value |
|---|---|
| Candidates passing | 377 / 492 (**77 %**, same as the offline generator) |
| Rounds with at least one passing tune | 116 / 123 (94 %) |
| Failure reason | all 118 errors are `missing required pattern` (masks already enforce pitches, leaps, durations, rests, chords) |
| Nodes with no passing candidate | `essentials-3/flats`, `essentials-3/amazing-grace` |

With 4 rounds (`maxAttempts`) a node with 94 % round yield practically never shows the error; the two zero-yield nodes always do (they require an accidental pattern; the spec prefix is in C and nothing pushes the model to it).

## Phone

No phone measurement: no Android device was attached (`adb devices` empty) and no iOS device is available on this Windows machine. As a rough proxy only, Chrome's CPU throttling (DevTools "mid-tier"/"low-end" mobile emulation) gave:

| Throttle | Cold total (localhost) | RH round (5 runs) | BOTH round (3 runs) |
|---|---|---|---|
| 4× | 8.0 s | 1.8–2.3 s | 13.2–14.8 s |
| 6× | 9.2 s | 3.1–4.6 s | 15.1–25.7 s |

Throttling slows the main thread, not necessarily the wasm worker threads, and a phone has fewer and slower cores and less memory bandwidth; treat these as a lower bound, not a phone result.

## Implications

- Desktop web: the first tune arrives in about 1.5–2 s plus download; "Another one" in about 0.5 s (one hand) to 2 s (two hands). Good enough without pre-generation.
- Phones: two-hand nodes may take 15 s or more per round. `PracticeService.roundTimeout` (60 s) bounds a stuck or very slow round.
- Two nodes cannot get a tune today; the learner sees the friendly error.

## Follow-ups

- Measure on a real mid-range Android phone in Chrome (bean under `piano-c6v1`).
- Required-pattern nodes with accidentals: choose the spec key from the taught keys, or mask toward the required pattern, so `flats` and `amazing-grace` get tunes.
- Two-hand speed on phones: pre-generate the next tune while the learner plays, or generate n = 2 there.
