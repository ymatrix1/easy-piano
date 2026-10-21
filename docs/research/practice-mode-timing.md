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

Deployed preview (Cloudflare Pages, `feat-practice-mode.easy-piano.pages.dev`, model files served same-origin from the `melody-model-v1` release, same headless Chrome, home connection):

| Case | Fetch + verify | ORT sessions | First round (4 tunes) | Total |
|---|---|---|---|---|
| Cold | 3102 ms | 1925 ms | 776 ms | **5.80 s** |
| Cached | 83 ms | 327 ms | 593 ms | **1.00 s** |

Rounds on the preview: RH 469–546 ms (5 runs), both hands 2.9–4.4 s (3 runs, 16 bars).

Localhost hides network time: a 12.5 MB download on a real connection adds about 1 s at 100 Mbit/s and 10 s at 10 Mbit/s. The progress bar covers that part.

## Per round, all 41 nodes × 3 seeds (123 rounds, 4 candidates each)

| Hands | Rounds | Median | Max |
|---|---|---|---|
| RH | 45 | 536 ms | 1717 ms |
| LH | 9 | 736 ms | 996 ms |
| BOTH | 69 | 2165 ms | 8413 ms |
| All | 123 | 1065 ms (p90 3070 ms) | 8413 ms |

Per tune (÷ 4): about 130–270 ms one hand, 540 ms both hands, in line with melody-browser.md (0.3–0.4 s per 8-bar tune). Two-hand nodes are slower because sequences are longer (both hands, up to 16 bars).

## Endless practice (streaming), real app UI

Release web build on localhost, headless Chrome driving the Flutter UI (Practice → Endless practice → play along → PLAY), 4-bar chunks, 4 candidates per round, times from the app's own log:

| Level, hands | First chunk | Next chunks | Chunks in the run |
|---|---|---|---|
| Piano Basics · Find middle C, RH, 68 bpm | 337 ms | 109–222 ms | 5 in ~50 s |
| Essentials I · Saints both hands, both, 96 bpm | 685 ms | 296–612 ms | 5 in ~35 s |

PLAY to first chunk shown: about 0.5 s plus the 1.5 s the script waits after its tap. No chunk was refused and the stream never ran dry: a 4-bar chunk at 96 bpm is 10 s of music.

## Rubric yield (same 492 candidates)

| Measure | Value |
|---|---|
| Candidates passing | 377 / 492 (**77 %**, same as the offline generator) |
| Rounds with at least one passing tune | 116 / 123 (94 %) |
| Failure reason | all 118 errors are `missing required pattern` (masks already enforce pitches, leaps, durations, rests, chords) |
| Nodes with no passing candidate | `essentials-3/flats`, `essentials-3/amazing-grace` |

These are whole-tune numbers with the node's required patterns. Endless practice (streaming) checks 4-bar chunks against the taught set without required patterns, so its yield is at least this and the two zero-yield nodes no longer block practice.

## Phone

No phone measurement: no Android device was attached (`adb devices` empty) and no iOS device is available on this Windows machine. As a rough proxy only, Chrome's CPU throttling (DevTools "mid-tier"/"low-end" mobile emulation) gave:

| Throttle | Cold total (localhost) | RH round (5 runs) | BOTH round (3 runs) |
|---|---|---|---|
| 4× | 8.0 s | 1.8–2.3 s | 13.2–14.8 s |
| 6× | 9.2 s | 3.1–4.6 s | 15.1–25.7 s |

Throttling slows the main thread, not necessarily the wasm worker threads, and a phone has fewer and slower cores and less memory bandwidth; treat these as a lower bound, not a phone result.

## Implications

- Desktop web: the first tune arrives in about 1 s cached and 6 s cold on the preview (download included); a one-hand 8-bar round takes about 0.5 s.
- Streaming chunks are 4 bars: at 80 bpm in 4/4 a chunk is 12 s of music and costs well under 1 s to write on desktop, so one chunk of look-ahead is plenty. On a 4× throttled CPU a two-hand chunk may take around 7 s; still inside one chunk of music, with no margin to spare on slower phones.
- `PracticeStream.roundTimeout` (60 s) bounds a stuck or very slow round.

## Follow-ups

- Measure on a real mid-range Android phone in Chrome (bean under `piano-c6v1`).
- Two-hand speed on phones: measure chunk time on a real phone; if it nears a chunk's duration, generate n = 2 or keep two chunks ahead.
