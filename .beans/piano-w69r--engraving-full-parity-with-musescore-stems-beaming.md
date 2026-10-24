# piano-w69r: Engraving full parity with MuseScore: stems, beaming, keysig, chord seconds, tuplets

**Status:** completed  
**Type:** task  
**Parent:** piano-eeut  

## Context
Following the addition of Leland music font and initial SMuFL beaming, several notation inaccuracies remained compared to MuseScore's professional engraving rules (`references/MuseScore/src/engraving/`):
- Stems defaulted to pointing UP regardless of pitch unless explicitly forced.
- 4/4 eighth-note runs were split strictly in 2-note pairs rather than half-measure 4-note beams.
- Only sharps existed with no flat/natural SMuFL glyphs or key signature layout.
- Chords with intervals of a second collided directly on the same X axis.
- Tuplet brackets were not supported.

Blocked by: none.

## Higher Goal
Achieve professional engraving parity with MuseScore for piano sheet notation, adhering to Elaine Gould's rules and MuseScore's layout algorithms, while keeping the Flutter rendering architecture modular, DRY, and thoroughly tested.

## Acceptance Criteria
- [x] Automatic stem direction follows middle-line rule (Treble: B4 line 3, Bass: D3 line 3; $\ge$ middle line is DOWN, $<$ middle line is UP) with chord extreme note distance voting.
- [x] Ledger line notes extend stems to reach at least the middle staff line.
- [x] Beaming supports half-measure grouping (4 eighth notes in beats 1-2 and 3-4 in 4/4 meter).
- [x] Key signatures (sharps and flats) render after clef with standard vertical positions; flat and natural glyphs are supported.
- [x] Chords with seconds offset one notehead to avoid collision.
- [x] Tuplet layout supports rendering triplet brackets and numbers.
- [x] Modular code structure with dedicated helpers (`stem_layout.dart`, `chord_layout.dart`, `key_signature.dart`, `tuplet_layout.dart`).
- [x] Unit tests for each new module in `app/test/ui/staff/` with 100% test pass rate and clean `flutter analyze`.

## Out of Scope
- Cross-staff beaming between treble and bass.
- Non-standard/microtonal accidentals.
- Full orchestral multi-stave bracket groups.

## Summary of Changes
- **Modular Engraving Engine (`app/lib/ui/staff/`)**:
  - `stem_layout.dart`: Gould & MuseScore `stemlayout.cpp` middle-line rule (Treble: B4, Bass: D3), extreme distance voting for chords, and ledger line stem elongation reaching at least middle line.
  - `chord_layout.dart`: Gould & MuseScore `chordlayout.cpp` second displacement (stem UP: lower normal, higher shifted right; stem DOWN: higher normal, lower shifted left).
  - `key_signature.dart`: Gould & MuseScore `keysig.cpp` standard sharps and flats positions, system width calculation, and key signature awareness for note accidentals (covering in-key notes and naturalizing canceled alterations).
  - `tuplet_layout.dart`: Gould & MuseScore `tupletlayout.cpp` triplet grouping, SMuFL tuplet digit glyphs, and bracket lines with end hooks for unbeamed tuplets.
  - `smufl.dart`: Added SMuFL tuplet digits (U+E880 - U+E889) and `tupletDigitGlyph`.
  - `staff_note.dart`: Added `accidental`, `tuplet`, and made `stemDown` optional with automatic resolution via `isStemDown`.
  - `beam_layout.dart`: Added half-measure 4/4 beaming grouping 4 consecutive eighth notes across beats 0-2 and 2-4.
  - `staff_painter.dart`: Wired all modular engines cleanly, supporting `keyFifths`, auto stems, chord offsets, and tuplets without bloat.
- **Unit Tests (`app/test/ui/staff/`)**:
  - `stem_layout_test.dart`: Verifies Treble/Bass middle lines, auto stem directions, chord voting, and ledger line elongation.
  - `beam_layout_test.dart`: Added test for half-measure 4/4 beaming across beats 0-2 and 2-4.
  - `chord_layout_test.dart`: Verifies second displacement with stem UP/DOWN and non-collision of non-second intervals.
  - `key_signature_test.dart`: Verifies G major, F major, C major widths and accidental resolutions.
  - `tuplet_layout_test.dart`: Verifies triplet group extraction and beam/bracket state detection.
- **Quality Gates**:
  - All 109 tests passed (`flutter test`).
  - Clean `flutter analyze` with 0 warnings.
  - Formatted with `dart format`.
