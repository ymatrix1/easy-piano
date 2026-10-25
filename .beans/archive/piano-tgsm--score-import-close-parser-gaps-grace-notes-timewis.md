---
# piano-tgsm
title: 'Score import: close parser gaps (grace notes, timewise MusicXML, bar length)'
status: completed
type: task
priority: normal
created_at: 2026-10-24T20:51:42Z
updated_at: 2026-10-25T22:18:55Z
parent: piano-r9p5
---

## Context
Known gaps in docs/specs/score-import-and-page-view.md section 5.2: grace notes skipped; score-timewise rejected; measure length uses the longest voice (bug candidate); mid-piece meter changes in ABC/LilyPond ignored.
Blocked by: piano-gy3o (done).

## Higher Goal
Parsers give the bar grid and note times a printed score would show.

## Acceptance Criteria
- [x] Measure length for an unfinished voice uses the bar's time signature, with a test (`unfinished_voice_keeps_the_bar_length`, `pickup_measure_has_the_length_of_its_notes`)
- [x] Decide and record: score-timewise support (kept rejected, spec 5.2)
- [x] Decide and record: grace notes (time and pitch) in MusicXML/ABC/LilyPond (skipped in all three, spec 5.2; tests `grace_notes_take_no_time_and_are_not_imported` in MusicXML and ABC)
- [x] Mid-piece meter changes in ABC and LilyPond: ABC implemented (`meter_change_in_the_body_starts_a_new_bar_length`, `inline_meter_change_counts_like_a_body_line`); LilyPond already read `\time` (test `meter_change_in_the_body_starts_a_new_bar_length`)

## Out of Scope
- Fingering, dynamics and articulation import (not in ImportedScore)
- Playing grace notes or ornaments (pitch is not in ImportedScore)
- Timewise MusicXML (kept rejected; new bean if a source needs it)

## Summary of Changes
- `musicxml.rs`: a regular bar keeps its time-signature length when a voice ends early; implicit pickups use their notes; overfull bars use the longest voice. Tests: unfinished voice, pickup, grace.
- `abc.rs`: `M:` in the body and `[M:...]` start a new bar length (`set_meter`). Tests: body change, inline change, grace.
- `lilypond.rs`: `\markup`, `\lyricmode`, `\lyrics`, `\addlyrics`, `\chordmode`, `\figuremode`, `\layout`, `\midi`, `\paper`, `\with`, grace commands and `\override`/`\revert`/`\set` no longer add notes. Tests: markup/grace/settings, LilyPond meter change.
- Spec `docs/specs/score-import-and-page-view.md` 5.2 and 5.4 updated with decisions and fixes.
- Verified: the new MusicXML bar-length and LilyPond text tests fail on the old code (checked by reverting each fix for one run).
