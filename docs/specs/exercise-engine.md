# Exercise engine

Status: implemented in `core/src/session.rs` ([D2](../DECISIONS.md)); pure, deterministic, driven by note events and audio-clock ticks in µs. Tests: unit tests in the module and `core/tests/lessons_playable.rs` (every lesson song). `one_note` stages run in Wait mode (hint after 1 s) until a dedicated drill flow exists, but pass on notes completed (> 80%, hinted or not); the hint only costs stars; `animation` and `quiz` are handled by the UI.

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

## Practice screen behaviour

Matches the reference app (studied from its stage logic, not copied):

- **Wait:** notes sit on a still page; the highlight jumps to the next note as soon as the right key is pressed; when the next note passes 72% of the width the page slides left (1 s ease-in-out) so it lands near the left edge. No play line.
- **Play-along:** notes scroll right to left toward a glowing play line at 30% of the width; one-bar count-in.
- **Feedback:** current note amber with glow, hit teal with expanding blue rings (~0.45 s), miss red; next keys highlighted on the keyboard; progress bar of judged notes.

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
- Wait (reference behaviour): the cursor moves on as soon as the chord is complete. A note that waits `hint_after_us` (4 s; 1 s for one-note drills) gets a hint (`Frame::hint_active`): the screen shows the beam and key colours, earlier chord presses are forgotten and any order completes it. Before the hint, chord notes must start within 0.4 s. Pass when more than 80% of chords were completed before their hint; wrong keys are counted but never lower the grade. Stars: 3 all clean, 2 ≥ 90%, 1 otherwise.
- Play-along: a press matches the nearest pending target with that pitch inside the input window; a chord is hit when all its pitches are pressed (timing from the first); targets past due + window are missed; other presses are wrong.
- Play-along score (reference song results): notes hit / total (each chord note counts), timing = 0.8 × spread + 0.2 × mean, each `(0.3 s − error) / 0.26 s` clamped 0–1 (+0.1 for microphone), assists = tempo factor, score = assists × notes × (0.75 + 0.25 × timing), `stars_exact` linear through 0.5 → 1, 0.7 → 2, 0.9 → 3.
- Pass: every critical section's hit ratio ≥ `max(pass_ratio − 0.1 × ⌊failed_attempts / 2⌋, 0.4)`; `suggest_practice` after 2+ failed attempts when still failing.
