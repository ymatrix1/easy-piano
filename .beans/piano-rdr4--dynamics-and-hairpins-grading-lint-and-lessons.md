---
# piano-rdr4
title: 'Dynamics and hairpins: grading, lint and lessons'
status: in-progress
type: feature
created_at: 2026-10-24T19:07:09Z
updated_at: 2026-10-24T20:00:00Z
parent: piano-bjig
---

## Context
PR 1 of piano-boat renders dynamics (p..ff, sf, sfz) and hairpins from `{dyn}`, `{cresc}`, `{dim}`, `{end}` directives. Grading and lint are done here. Teaching lessons are not. Blocked by: none.

## Higher Goal
Dynamics and hairpins are part of practice feedback, not only decoration.

## Acceptance Criteria
- [x] Core parser and model: `core/src/dynamics.rs` (`Dynamic`, `Mark`, layout of hairpin spans), `Song::marks()`. Rust unit tests.
- [x] Grading rule per mark: MIDI velocity classified to the nearest MuseScore centre (ppp 16 .. fff 126); a dynamic passes at >= half of its onsets; a hairpin passes at a trend of 8 velocity units in its direction. Mic and touch are not graded. Result is informational: `StageResult.dynamics` and `ResultView.dynamics*`, not part of the stars.
- [x] Content lint rejects unknown `{dyn}` text and malformed `{cresc}`/`{dim}`/`{end}` arguments (`Song::validate`, so `content lint` runs it). Unclosed hairpins are closed at the next mark or the song end, not an error.
- [ ] Teaching lessons (animation scene + drill + song, strings in 5 locales) for p/mp/mf/f/ff and crescendo/diminuendo. Not started: needs scene briefs and drill design.
- [ ] Show the dynamics grade on the result screen (data is in `ResultView`).

## Out of Scope
- Articulation marks and damper pedal (piano-boat, later PR or bean).
- Hairpin stem clearance (piano-boat).
- Putting dynamics into the star score (needs a product decision).

## Summary of Changes
- `core/src/dynamics.rs`: marks, hairpin layout (same rules as `song_marks_parser.dart`), grading.
- `core/src/song.rs`: `marks()`, `total_beats()`, lint of dynamics directives in `validate`.
- `core/src/session.rs`: `NoteEvent.velocity`; matched MIDI onsets recorded with their beat; `StageResult.dynamics`.
- `app/rust/src/api/practice.rs`: `on_note(pitch, on, velocity, t_us)`; `ResultView` gets four counters. FRB regenerated.
- `app/lib/practice/practice_stage.dart`: passes MIDI velocity; touch and mic pass 0.
- Tests: `dynamics.rs` unit tests, song lint and beat-line tests, session MIDI and mic grading tests, `result_screen_test` updated.
- Docs: `content-format.md` grading section.
