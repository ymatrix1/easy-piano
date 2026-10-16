# Exercise engine

Status: draft. Lives in Rust `core` ([D2](../DECISIONS.md)); pure logic, deterministic, tested with recorded input fixtures.

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
Session::new(level, settings) -> Session
session.on_note(event: NoteEvent { pitch, velocity, on, t_audio_us })
session.tick(t_audio_us) -> Frame { playhead_beat, states[], score }
session.result() -> StageResult { passed, stars, hits, misses, timing_stats }
```
