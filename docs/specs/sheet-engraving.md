# Sheet Music Engraving Specification (MuseScore Parity)

## Overview
Easy Piano renders piano sheet music on Flutter canvas using SMuFL (Standard Music Font Layout) compliant vector fonts (Leland as primary, Bravura as fallback).
The engraving engine is designed for full algorithmic parity with **MuseScore Studio** (`references/MuseScore/src/engraving/rendering/score/`) and follows standard professional engraving principles established by Elaine Gould (*Behind Bars*).

## Layout & Architecture Principles
1. **Audio Clock is Master:** The score scrolls or advances based on real-time audio time (beats), never on frame deltas.
2. **Modular Components:** Staves rendering is decomposed into specialized, unit-tested layout modules under `app/lib/ui/staff/`:
   - `smufl.dart`: SMuFL glyph code points, digit glyphs, tuplet numbers.
   - `stem_layout.dart`: Gould middle-line stem direction, chord voting, ledger elongation.
   - `beam_layout.dart`: Metric subdivision, half-measure 4/4 grouping, slope clamping, parallel secondary beams.
   - `chord_layout.dart`: Second interval displacement (preventing notehead collisions).
   - `key_signature.dart`: Sharps and flats vertical positions, system spacing, accidental spelling.
   - `tuplet_layout.dart`: Triplet grouping, SMuFL tuplet digits, unbeamed bracket rendering.
   - `engraving_decorations.dart`: Tapering quadratic Bézier ties and articulation placement.
   - `staff_painter.dart`: Main custom painter coordinating the modules.
3. **No Monolithic Painters:** Every geometric calculation is isolated in its own module with mirrored unit tests under `app/test/ui/staff/`.

---

## MuseScore Engraving Parity Matrix

| Feature | MuseScore Reference | Status | Module |
|---|---|---|---|
| Leland SMuFL glyphs | `dom/sym.cpp`, `dom/symdefaultdata.h` | Delivered | `smufl.dart` |
| Middle-line stem direction | `rendering/score/stemlayout.cpp` | Delivered | `stem_layout.dart` |
| Stem elongation on ledgers | `rendering/score/stemlayout.cpp:1293` | Delivered | `stem_layout.dart` |
| Metric Beaming (16ths & 8ths) | `rendering/score/beamlayout.cpp` | Delivered | `beam_layout.dart` |
| 4/4 Half-measure beaming | `rendering/score/beamlayout.cpp:115` | Delivered | `beam_layout.dart` |
| Chord Seconds Displacement | `rendering/score/chordlayout.cpp:1895` | Delivered | `chord_layout.dart` |
| Key Signatures (1-7 sharps/flats)| `rendering/score/tlayout.cpp:3588` | Delivered | `key_signature.dart` |
| Enbarmonic Accidental Spelling | `dom/keysig.cpp`, `dom/pitchspeller.cpp` | Delivered | `key_signature.dart` |
| Tuplet / Triplet Brackets | `rendering/score/tupletlayout.cpp` | Delivered | `tuplet_layout.dart` |
| Tapered Bézier Ties & Slurs | `rendering/score/slurtielayout.cpp` | Delivered | `engraving_decorations.dart` |
| End barline (thin + thick) at the end of the piece | `rendering/score/barline.cpp` | Delivered | `staff_painter.dart` (`endBeat`) |
| Articulations (staccato, tenuto) | `dom/articulation.cpp` | Delivered | `engraving_decorations.dart` |
| Dynamics (p..ff, sf, sfz) & Hairpins | `rendering/score/dynamicslayout.cpp`, `tlayout.cpp` (layoutHairpinSegment) | Delivered (rendering: notehead centring, grand-staff gap, collisions; grading in core) | `dynamics_layout.dart` |
| Piano Damper Pedal (Ped., *) | `rendering/score/tlayout.cpp` (pedal) | Planned (PR 2) | `pedal_layout.dart` |
| Arpeggios & Glissandi | `rendering/score/arpeggiolayout.cpp` | Planned (PR 3) | `arpeggio_layout.dart` |
| Grace Notes & Ornaments | `rendering/score/tlayout.cpp` (ornaments)| Planned (PR 4) | `ornament_layout.dart` |
| Repeat signs & Voltas (1st/2nd) | `rendering/score/measurelayout.cpp` | Planned (PR 5) | `repeat_layout.dart` |
| Chord Symbols & Lyrics (single verse) | `harmonylayout.cpp`, `lyricslayout.cpp` | Delivered (PR 6, `piano-r16m`: rendering only; multi-verse, playback and lint not included) | `harmony_layout.dart` |
| Ottava (8va/8vb) & Clef Changes | `systemheaderlayout.cpp`, `tlayout.cpp` | Planned (PR 7) | `ottava_layout.dart` |
| Shared Staff Multi-Voice | `rendering/score/stavesharinglayout.cpp`| Planned (PR 8) | `voice_sharing_layout.dart` |
| Static Multi-System Page View | `rendering/score/pagelayout.cpp` | Planned (`piano-ev1n`) | `score_page_layout.dart` |

---

See [score-import-and-page-view.md](score-import-and-page-view.md) for the end-to-end specification on static page engraving layout, multi-format score import (MusicXML, MIDI, ABC, LilyPond), and UI integration.

---

## Module Specifications

### 1. Dynamics and Hairpins (`dynamics_layout.dart`, `staff_painter.dart`)
- **Reference:** MuseScore `rendering/score/dynamicslayout.cpp` (centring, barline avoidance), `rendering/score/tlayout.cpp:layoutHairpinSegment` (hairpin arms), `rendering/score/systemlayout.cpp` (`centerElementsBetweenStaves`, `centerItemGroup`, `groupItemsToCenterTogether`, `elementShouldBeCenteredBetweenStaves`), `autoplace` for the clearances.
- **Style values** (`data/styles/legacy-style-defaults-v450.mss`): `dynamicsPosBelow` y=2 sp; `hairpinPosBelow` y=1.75 sp; `hairpinHeight` 1.15 sp; `hairpinLineWidth` 0.12 sp; `dynamicsMinDistance` 0.5 sp; `hairpinMinDistance` 0.7 sp; `autoplaceHairpinDynamicsDistance` 0.5 sp; `centerOnNotehead` 1; `dynamicsHairpinsAutoCenterOnGrandStaff` 1.
- **Glyph metrics** (`fonts/bravura/bravura_metadata.json`): thin barline 0.16 sp; stem 0.12 sp; black notehead 1.18 x 1.0 sp; whole notehead 1.688 sp wide.
- **Glyphs:** composed letter by letter as MuseScore `Dynamic::DYN_LIST`: `p` U+E520, `m` U+E521, `f` U+E522, `s` U+E524, `z` U+E525. Supported marks: `p pp ppp mp mf f ff fff fp sf sfz`.
- **Horizontal:** a dynamic is centred on the notehead (`centerOnNotehead`, centre = left + 0.59 sp, or 0.844 sp for whole notes). A hairpin runs from its start note's left edge to its end note's left edge. Dynamics keep 0.25 sp from the nearest barline on each side (`manageBarlineCollisions`), using the thin barline width.
- **Treble staff in a grand staff:** dynamics and hairpins of the right hand (`StaffDynamic.leftHand` false) are centred between the two staves (`centerItemGroup`): the free band runs from the bottom of the obstacles above to the top of those below, minus `minDistance` on each side. Obstacles are the staff lines and the noteheads and stems of both staves.
- **Overlapping items in that gap** form one group. They are stacked by preferred top and centred as one unit (`groupItemsToCenterTogether`, `convergence`).
- **Bass staff, or a single staff:** placed below the bottom staff line. Dynamic top at 2 sp, hairpin centre at 1.75 sp. Each is then moved down past noteheads and stems it overlaps, keeping `minDistance` (`autoplace`). Dynamics and hairpins keep 0.5 sp from each other.
- **Hairpins:** two straight arms from a tip, `hairpinHeight` 1.15 sp at the wide end, line width 0.12 sp. Crescendo tip on the left; diminuendo tip on the right. Shorter than 1 sp is stretched to 1 sp.
- **Not implemented (by design or not yet):**
  - Multi-system hairpin segments (the app paints one scrolling line, no systems).
  - Circled tip and hairpin text (`hairpinCircledTip` and `hairpinText` are off by default in MuseScore).
  - Shape-based skylines: obstacles are boxes around noteheads and stems, not the glyph outlines, and beams are not included.
  - Rests are not obstacles.
- **Known limitations (verified, not fixed):**
  - *Dense gaps:* when many marks fall in one 2-beat window of a grand staff, the stacked group can be taller than the gap and reach over a staff line. MuseScore has the same constraint, but I have not compared the exact result.
  - *Box width:* a dynamic's box is its TextPainter width, which depends on the loaded font. A wide advance can push a nearby hairpin down a little more than the real glyph would.
  - *Test fonts:* widget tests without the music font paint placeholder boxes with different metrics. Paint tests therefore check that ink exists in a region, not that a region is empty. The layout rules themselves are unit-tested without fonts.
  - *No pixel comparison* with MuseScore output has been done.
  - *Result screen:* the dynamics grade is in ResultView but not shown in the UI (piano-rdr4).- **Data:** song JSON directives, see [content-format.md](content-format.md#directives-dynamics-and-hairpins).

### 2. Piano Damper Pedal (`pedal_layout.dart`)
- **Reference:** MuseScore `pedal.cpp` and `tlayout.cpp:layoutPedal`.
- **Traditional:** $\mathfrak{Ped.}$ (U+E650) on down-stroke, $\ast$ (U+E655) on release.
- **Modern Bracket:** Continuous line with inverted notch on pedal changes (`___/\___|`), stroke width `space * 0.12`.

### 3. Arpeggios and Glissandi (`arpeggio_layout.dart`)
- **Reference:** MuseScore `arpeggiolayout.cpp`.
- **Arpeggio:** Repeated vertical wave glyph (`wiggleArpeggiato`, U+E634) connecting the bottom and top note of the chord, placed `space * 0.8` to the left of the chord.
- **Glissando:** Diagonal stroke or wave connecting two notes with centered italic label *gliss.*

### 4. Grace Notes & Ornaments (`ornament_layout.dart`)
- **Reference:** MuseScore `tlayout.cpp` and `chordlayout.cpp`.
- **Acciaccatura:** Scaled notehead ($60\%$) with upward stem sliced by a diagonal slash (U+E560).
- **Trills & Turns:** Standard SMuFL glyphs (`ornamentTrill`, `ornamentTurn`, `ornamentMordent`) centered above the notehead.

### 5. Repeats, Voltas & System Breaks (`repeat_layout.dart`)
- **Reference:** MuseScore `measurelayout.cpp` and `barline.cpp`.
- **Repeat Barlines:** Thick-thin dual line with dots in staff spaces 2 and 3.
- **Volta Brackets:** Horizontal line above measure with open/closed right edge and number label ("1.", "2.").
- **Navigation:** Segno, Coda, D.C. al Fine, D.S. al Coda.

### 6. Chord Symbols and Lyrics (`harmony_layout.dart`, `staff_painter.dart`)
- **Reference:** MuseScore `rendering/score/harmonylayout.cpp` (chord symbol as text above the staff; extension raised, bass after a slash lowered), `rendering/score/lyricslayout.cpp` (syllable centred under the note, hyphen between syllables, melisma line). Style values from `data/styles/legacy-style-defaults-v450.mss` where noted.
- **Data:** song JSON directives, see [content-format.md](content-format.md#directives-chord-symbols-and-lyrics). Chords and lyrics are only read from song JSON; no level or content file uses them yet.
- **Chord symbols** (`{chord:"Am7"}`): `ChordSymbol.parse` splits root (`A`-`G`, optional `#` or `b`), suffix (letters, digits and `+ - ( ) # ° ø`, up to 16 characters in total) and bass (`/` then a note). Anything else is ignored (lower-case root, empty bass, spaces, a second slash).
  - Runs: root at 1.5 sp; suffix at 0.7 scale, raised 0.22 root em (superscript, top aligned with the root); `/` on the baseline; bass at 0.7 scale, lowered 0.2 em (subscript).
  - Accidentals are ASCII `#` and `b`. Text uses the app's default sans font, not SMuFL, so no codepoints are involved.
  - Placement: left aligned on the notehead of the hand's note at that beat (any hand's note, or the nominal beat position when none). Baseline 0.8 sp above the top staff line, or above the top of the notes at that onset when they are higher. Anchored to the top staff (treble on a grand staff; bass alone on a bass staff).
  - A chord in both hands at the same beat is drawn once, on the treble.
- **Lyrics** (`{lyric:"Hel-"}`, `{lyric:"lo"}`, `{lyric:"_"}`): `StaffLyric.fromDirective`.
  - A syllable is centred on the notehead centre (0.59 sp, or 0.844 sp for whole notes). Font size 1.4 sp, default sans font.
  - One row per hand. The row sits 1 sp below the bottom line of the hand's staff (`lyricsMinTopDistance`), lowered so it clears the lowest ink (noteheads, down stems) of that hand's onsets by 0.25 sp (`lyricsMinDistance`). The row baseline is computed over all lyrics of the hand, so it does not move while the score scrolls. Left hand on a grand staff sits below the bass staff.
  - Hyphen (syllable ends with `-`): a line of 0.2 to 0.5 sp centred in the gap to the next syllable of that hand, 0.1 sp clearance from each syllable, 0.1 sp thick, 0.35 sp above the baseline. Not drawn when the gap is under 0.4 sp or the next lyric is an extension.
  - Extension (`_`): a line from the previous lyric of that hand (its text edge, or the note centre for an extension) to the next lyric's left edge (or the note centre for an extension), or to the end of its note (centre plus duration in beats times `pixelsPerBeat`, not past the next notehead of that hand). Padded 0.2 sp at each end, not drawn under 0.4 sp (`lyricsMelismaPad`, `lyricsDashMinLength`).
  - A lyric in both hands at the same beat and with the same text is drawn once, on the treble staff.
- **Not implemented (by design or not yet):**
  - Multi-verse stacking (verse 2, verse 3) and verse numbers.
  - Playback, grading or any use of chord and lyric text outside drawing.
  - Core parser and lint checks for chord and lyric text. Core accepts any directive; lint does not check these yet.
  - Chord symbol and lyric collisions with dynamics, hairpins, finger labels and ornaments: no clearance pass beyond the notehead and stem rows above.
  - Lyric lines are not broken across systems (the app paints one scrolling line).
  - `lyricsPosBelow` (3 sp in MuseScore) is not used; the 1 sp row sits in the grand staff gap so the treble row does not reach the bass staff. Dense treble lyrics on a grand staff can still touch bass-staff ledger lines.
  - Chord text is left aligned on the note, not centred or placed by `harmonyPlacement` style.
- **Known limitations (verified, not fixed):**
  - Text widths come from the font loaded at run time. Paint tests use flutter_test's placeholder font, so they check for ink in regions, not exact glyph boxes.
  - No pixel comparison with MuseScore output has been done.
  - Parser (`song_marks_parser.dart`) and geometry (`harmony_layout.dart`) are unit-tested. Paint tests (`harmony_paint_test.dart`) show that each mark adds ink where expected.
