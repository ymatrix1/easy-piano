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
| MIDI | −300 / +430 ms (perfect ±50); reference opens notes 0.3 s early, closes 0.43 s late |
| Mic | −150 / +430 ms |
| Touch | −300 / +430 ms |

Reference: Simply Piano uses ~0.34 s MIDI / ~0.15 s mic total tolerance.

- Hand modes: RH only, LH only, both; app auto-plays the other hand.

## Critical sections and adaptive threshold

- Default pass ratio 0.7. After every 2 failed attempts subtract 0.1 (floor 0.4). Matches proven reference behaviour.
- After 3 fails offer Practice Mode: tempo 60%, wait-mode toggle.

## Training mode

Play-along stages run with `Settings::training` (the app turns it on for every play-along stage). Each critical section is graded as it ends, like the reference ([teardown](../research/simply-piano-teardown.md#play-along-error-feedback-and-training-mode)):

| Step | Rule |
|---|---|
| Section threshold | `effective_threshold(pass_ratio, failed_attempts + section_fails)` |
| Pass | All section notes judged and hits ≥ threshold × notes → `SectionEvent::Passed`, next section, `section_fails = 0` |
| Early fail | Misses > (1 − threshold) × notes, even before the section ends |
| Fail at full tempo | `section_fails += 1`, rewind to the section's first note; every `FAILS_BEFORE_PRACTICE` (2) failures the replay is a practice run (`intro` set) |
| Practice run | Tempo × `PRACTICE_TEMPO` (0.75). Failed → practise again. Passed → `section_fails += 1`, replay the section at full tempo |

`SectionEvent::Replay { beat, tempo, .. }` means the engine reset the section's targets and switched tempo; the caller restarts its clock one count-in before `beat` (the engine's clock resets). Slow runs count as assists: `assists` = lowest tempo used.

## Play-along feedback

`Session::take_feedback()` drains events in order: `Hit { target, delta_us, timing }` (`Timing::Early / OnTime / Late`, on time within ±`ON_TIME_US` = 120 ms), `Wrong { pitch, t_us }`, `Missed { target }`. `Frame::streak` counts chords hit in a row (a miss or wrong key resets it); the UI does not show it (the reference has none).

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
session.tick(t_us) -> Frame { playhead_beat, cursor, hits, misses, wrong, done, hint_active, streak }
session.take_feedback() -> Vec<Feedback>              // play-along error animations
session.take_section_event() -> Option<SectionEvent>  // training mode
session.result() -> StageResult { passed, stars, hit_ratio, wrong, mean_abs_timing_ms, sections, threshold, suggest_practice }
session.end_us()   // audio time when the last window has closed
```

Rules as implemented:

- Targets: notes grouped by onset (chord = all pitches at one beat), filtered by hand.
- Wait (reference behaviour): the cursor moves on as soon as the chord is complete. A note that waits `hint_after_us` (4 s; 1 s for one-note drills) gets a hint (`Frame::hint_active`): the screen shows the beam and key colours, earlier chord presses are forgotten and any order completes it. Before the hint, chord notes must start within 0.4 s. Pass when more than 80% of chords were completed before their hint; wrong keys are counted but never lower the grade. Stars: 3 all clean, 2 ≥ 90%, 1 otherwise.
- Play-along: a press matches the nearest pending target with that pitch inside the input window; a chord is hit when all its pitches are pressed (timing from the first); targets past due + window are missed; other presses are wrong.
- Play-along score (reference song results): notes hit / total (each chord note counts), timing = 0.8 × spread + 0.2 × mean, each `(0.3 s − error) / 0.26 s` clamped 0–1 (+0.1 for microphone), assists = tempo factor, score = assists × notes × (0.75 + 0.25 × timing), `stars_exact` linear through 0.5 → 1, 0.7 → 2, 0.9 → 3.
- Pass: every critical section's hit ratio ≥ `max(pass_ratio − 0.1 × ⌊failed_attempts / 2⌋, 0.4)`; `suggest_practice` after 2+ failed attempts when still failing.
