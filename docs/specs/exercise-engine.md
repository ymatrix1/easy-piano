# Exercise engine

Status: implemented in `core/src/session.rs` ([D2](../DECISIONS.md)); pure, deterministic, driven by note events and audio-clock ticks in µs. Tests: unit tests in the module and `core/tests/lessons_playable.rs` (every lesson song). `one_note` stages run in Wait mode until a dedicated drill flow exists; `animation` and `quiz` are handled by the UI.

## Stage types

| Type | Clock | Pass rule |
|---|---|---|
| `wait` | Paused until correct note(s) | All notes played; wrong notes counted for stars |
| `play_along` | Audio clock, backing track optional | Hit ratio ≥ threshold in each critical section |
| `one_note` | Wait per prompt | N correct of M |
| `animation` | Scene timeline | Watched (skippable after first view) |
| `quiz` | None | Correct answer |

## Matching

- Expected event = (pitch set, onset beat, hand). Chord = all pitches within chord window (80 ms MIDI).
- Timing window (half-width), start values, tune in Phase 1:

| Input | Window |
|---|---|
| MIDI | ±150 ms (perfect ±50) |
| Mic | ±200 ms |
| Touch | ±200 ms |

Reference: Simply Piano uses ~0.34 s MIDI / ~0.15 s mic total tolerance.

- Hand modes: RH only, LH only, both; app auto-plays the other hand.

## Critical sections and adaptive threshold

- Default pass ratio 0.7. After every 2 failed attempts subtract 0.1 (floor 0.4). Matches proven reference behaviour.
- After 3 fails offer Practice Mode: tempo 60%, wait-mode toggle.

## Stars

| Stars | Rule |
|---|---|
| 1 | Pass |
| 2 | ≥ 85% hit, ≤ 3 wrong |
| 3 | ≥ 95% hit, timing mean error ≤ 60 ms |

## Interfaces

```
Session::new(&song, Settings { mode, input, tempo, pass_ratio, failed_attempts, hand }) -> Session
session.on_note(NoteEvent { pitch, on, t_us })
session.tick(t_us) -> Frame { playhead_beat, cursor, hits, misses, wrong, done }
session.result() -> StageResult { passed, stars, hit_ratio, wrong, mean_abs_timing_ms, sections, threshold, suggest_practice }
session.end_us()   // audio time when the last window has closed
```

Rules as implemented:

- Targets: notes grouped by onset (chord = all pitches at one beat), filtered by hand.
- Wait: playhead frozen at the current target; wrong pitches counted; stars 3 / 2 / 1 for ≤ 1 / ≤ 3 / more wrong notes.
- Play-along: a press matches the nearest pending target with that pitch inside the input window; a chord is hit when all its pitches are pressed (timing from the first); targets past due + window are missed; other presses are wrong.
- Pass: every critical section's hit ratio ≥ `max(pass_ratio − 0.1 × ⌊failed_attempts / 2⌋, 0.4)`; `suggest_practice` after 2+ failed attempts when still failing.
