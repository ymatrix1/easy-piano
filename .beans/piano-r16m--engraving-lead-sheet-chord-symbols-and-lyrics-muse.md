# piano-r16m: Engraving: lead sheet chord symbols and lyrics (MuseScore harmonylayout.cpp, lyricslayout.cpp)

**Status:** todo  
**Type:** feature  
**Parent:** piano-r9p5  

## Context
Lead sheets and pop arrangements combine standard notation with harmonic chord symbols above the staff and sung lyrics below the melody notes. MuseScore implements specialized layout engines for harmony parsing/stacking and lyric syllabic hyphenation (`docs/specs/sheet-engraving.md`).

Algorithmic reference: MuseScore `references/MuseScore/src/engraving/rendering/score/harmonylayout.cpp` and `lyricslayout.cpp`.

Blocked by: none.

## Higher Goal
Support authentic lead-sheet and accompaniment score rendering with chord symbols and lyric text.

## Acceptance Criteria
- [ ] Chord symbols: rendered above treble staff (e.g. `C`, `Am7`, `G7/B`, `F#m7b5`) with proper superscript extensions and subscript bass notes.
- [ ] Lyric syllables: centered under the notehead of each vocal note.
- [ ] Lyric connectors: hyphens (`-`) between syllables within the same word, and extension lines (`_`) for melismas and sustained notes.
- [ ] Dedicated helper `harmony_layout.dart` under `app/lib/ui/staff/`.
- [ ] Unit tests under `app/test/ui/staff/harmony_layout_test.dart`.

## Out of Scope
- Multi-verse lyric stacking (verse 2, verse 3).

## Summary of Changes
*(To be completed upon finishing)*
