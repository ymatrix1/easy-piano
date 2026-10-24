---
# piano-t60e
title: 'Professional sheet engraving: Leland font, clean open staves, time signature, chord stems and fingers'
status: completed
type: task
created_at: 2026-10-23T21:10:51Z
updated_at: 2026-10-23T21:30:00Z
parent: piano-eeut
---

Engraving visual overhaul based on Leland font, sightread, and app-ss references.
Context:
Previous band padding and artificial accidental shift created visual artifacts.
Also chords had overlapping finger numbers and opposing stems, and time signatures were missing.

Acceptance Criteria:
- [x] Add Leland font and use it for crisp SMuFL music engraving
- [x] Restore clean staff band / open staves (remove artificial vPad and heavy boxing border artifacts)
- [x] Remove artificial noteX / barLineX offsets that disrupted natural metric spacing
- [x] Add Time Signature rendering on the staff (e.g. 4/4, 3/4) using SMuFL glyphs
- [x] Fix chord rendering: unified stem for notes in chord, single/stacked fingering without overlapping text
- [x] All tests in app/ pass and flutter analyze is clean

## Summary of Changes
- Integrated Leland (MuseScore / Sightread modern SMuFL font) into `assets/fonts/` and loaded alongside Bravura.
- Changed default SMuFL glyph rendering in `StaffPainter` to `Leland`.
- Removed the heavy rectangle frame and extra padding around the staves so staves and ledger notes breathe openly like the references.
- Added time signature display (`Smufl.digitGlyph`) at the beginning of the staves after the clefs.
- Fixed chord fingering text collision: when multiple notes occur in a chord, only the top note renders the finger text to prevent overlapping numbers.
- Fixed chord stems: unified vertical stem connecting all noteheads in a chord instead of competing opposing stems.
- Ignored same-beat notes in horizontal accidental collision check.
- All 82 unit/widget tests passing and zero analyzer warnings.
