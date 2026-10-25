# piano-r16m: Engraving: lead sheet chord symbols and lyrics (MuseScore harmonylayout.cpp, lyricslayout.cpp)

**Status:** in-progress  
**Type:** feature  
**Parent:** piano-r9p5  

## Context
Lead sheets and pop arrangements combine standard notation with harmonic chord symbols above the staff and sung lyrics below the melody notes. MuseScore implements specialized layout engines for harmony parsing/stacking and lyric syllabic hyphenation (`docs/specs/sheet-engraving.md`).

Algorithmic reference: MuseScore `references/MuseScore/src/engraving/rendering/score/harmonylayout.cpp` and `lyricslayout.cpp`.

Blocked by: none.

## Higher Goal
Support authentic lead-sheet and accompaniment score rendering with chord symbols and lyric text.

## Acceptance Criteria
- [x] Chord symbols: rendered above treble staff (e.g. `C`, `Am7`, `G7/B`, `F#m7b5`) with proper superscript extensions and subscript bass notes. (`{chord:"G7/B"}` directive; extension raised, bass lowered; ASCII `#`/`b`, default sans font.)
- [x] Lyric syllables: centered under the notehead of each vocal note. (`{lyric:"Hel-"}`, one row per hand.)
- [x] Lyric connectors: hyphens (`-`) between syllables within the same word, and extension lines (`_`) for melismas and sustained notes.
- [x] Dedicated helper `harmony_layout.dart` under `app/lib/ui/staff/`.
- [x] Unit tests under `app/test/ui/staff/harmony_layout_test.dart` (plus `harmony_paint_test.dart` and new cases in `song_marks_parser_test.dart`).

## Out of Scope
- Multi-verse lyric stacking (verse 2, verse 3).
- Playback or grading that uses chord or lyric text.
- Core parser and lint checks for chord and lyric text.
- Adding chords or lyrics to content files and lessons.

## Summary of Changes
Delivered (PR 6, branch `feat/chords-lyrics`):
- `app/lib/ui/staff/harmony_layout.dart`: `ChordSymbol.parse` (root, suffix, bass; bad input gives null), `HarmonyLayout` geometry (chord runs and baseline, lyric centring and row top, hyphen and melisma segments), `StaffChord`, `StaffLyric.fromDirective`.
- `app/lib/ui/staff/song_marks_parser.dart`: `{chord:"..."}` and `{lyric:"..."}` directives; `SongMarks.chords` / `lyrics` default to empty; malformed text dropped; they do not close a hairpin.
- `app/lib/ui/staff/staff_painter.dart`: `chords` and `lyrics` params (default `const []`), `_drawChordsAndLyrics` inside the scroll mask. `app/lib/practice/practice_stage.dart` passes them.
- Tests: `harmony_layout_test.dart`, `harmony_paint_test.dart` (pixel diff with and without each mark), `song_marks_parser_test.dart` additions.
- Docs: `docs/specs/sheet-engraving.md` (matrix row, section 6), `docs/specs/content-format.md` (directives section).

Remaining (not in this bean's delivery): multi-verse stacking; playback use of chord and lyric text; core parser and lint for these directives; collision clearance of chords and lyrics with dynamics, finger labels and ornaments; lyric line breaking across systems; visual comparison with MuseScore output.
