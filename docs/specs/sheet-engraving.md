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
| Grace Notes & Ornaments | `rendering/score/tlayout.cpp` (`layoutOrnament` 4259, `layoutTrillSegment` 6477, `layoutStemSlash` 5378), `rendering/score/chordlayout.cpp` (grace notes 621, articulations 1048), `dom/trill.cpp` (`symbolLine` 73) | Delivered (PR 4, `piano-rlp3`: trill, mordent, turn, acciaccatura; constants aligned with MuseScore source, rendering not compared to MuseScore output; no appoggiatura, no playback) | `ornament_layout.dart` |
| Repeat signs & Voltas (1st/2nd) | `rendering/score/measurelayout.cpp` | Planned (PR 5) | `repeat_layout.dart` |
| Chord Symbols & Lyrics | `harmonylayout.cpp`, `lyricslayout.cpp` | Planned (PR 6) | `harmony_layout.dart` |
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
- **Reference:** MuseScore source under `references/MuseScore/src/engraving/`: `rendering/score/tlayout.cpp` (`layoutOrnament` 4259, `layoutTrillSegment` 6477, `layoutStemSlash` 5378), `rendering/score/chordlayout.cpp` (grace chords 621, articulation placement 1048 to 1143), `dom/trill.cpp` (`symbolLine` 73, trill end 300), `rendering/score/stemlayout.cpp` (stem length 60). Style values are from `data/styles/legacy-style-defaults-v450.mss` (`v450`). Every constant in `ornament_layout.dart` cites its line, or is marked as a local choice.
- **Status:** Delivered in PR 4 (`piano-rlp3`), rendering only. The constants and approaches were aligned with the MuseScore source in the `fix(engraving)` commit on PR #107. Syntax in [content-format.md](content-format.md#directives-ornaments-and-acciaccaturas).
- **Trill:** the start glyph `ornamentTrill` (U+E566) sits at the chord origin (left ink of the chord's heads, `trill` segment `x1 = 0`), and the line is `wiggleTrill` (U+EAA4) fills, as `TrillSegment::symbolLine` builds it (`dom/trill.cpp:73`). Number of fills: `lrint((w - w1) / w2)`, with `w1` = 1.732 sp and `w2` = 0.88 sp (Leland advances). `w` runs from the chord origin to one spatium before the next onset (`dom/trill.cpp:300`). Baseline: the default `trillPosAbove` is -0.5 sp from the staff top line (`v450:266`). Autoplace (`autoplace.cpp:109-141`) lifts it so it clears the chord ink by `trillMinDistance` 0.5 sp (`v450:1552`). The line is a glyph sequence: no generated path, no sine. No later onset: only the start glyph is drawn.
- **Mordent and turn:** `ornamentMordent` (U+E56D) and `ornamentTurn` (U+E567), centred on the top head's bbox (MuseScore centres on the optical centre, not modelled). Baseline: the higher (smaller y) of two clearances (`chordlayout.cpp:1051`, `:1111`, `:1138`). (a) Above the top head by `propertyDistanceHead` 0.4 sp (`v450:193`), or above a stem-up chord's stem tip by `propertyDistanceStem` 0.4 sp (`v450:194`). (b) Above the top staff line by `propertyDistance` 0.4 sp (`v450:195`), so a low chord keeps the ornament above the staff. The 0.35 sp `vertMargin` of `layoutOrnament` (`tlayout.cpp:4269`) is for the ornament's own accidentals, not for the glyph.
- **Acciaccatura:** a grace note, `NoteType::ACCIACCATURA` with `showStemSlash` (`dom/chord.cpp:296`). Notehead `noteheadBlack` at `graceNoteMag` 0.7 (`v450:376`, `chord.cpp:2071`). Its right edge sits `max(minNoteDistance 0.5, graceToMainNoteDist 0.45)` sp left of the main chord's leftmost ink (`v450:156`, `v450:377`, `chordlayout.cpp:626`, `horizontalspacing.cpp:1517`). The main chord's ink includes an accidental: `accidentalNoteDistance` 0.25 sp (`v450:174`, `tdraw.cpp:2618`) plus the accidental's width (Leland bbox). Stem: `stemLength` 3.5 sp x 0.7 (`v450:151`, `stemlayout.cpp:60`), stroke `stemWidth` 0.1 sp x 0.7 (`tdraw.cpp:2608`), attached at the right edge of the head (local choice: the font's `stemUpSE` anchor is not in the repository). **Slash:** a line, not a glyph (the earlier glyph `graceNoteSlashStemUp` U+E564 was wrong). `TLayout::layoutStemSlash` (`tlayout.cpp:5378`): from `stemRight - 0.7 * 1.3 / 2` sp, starting `0.7 * 2 sp * 0.66` below the tip (`v450:170`, `tlayout.cpp:5394`, `:5409`), rising at `stemSlashAngle` 40 degrees (`v450:171`, `:5404`) to `stemRight + 0.7 * 1.3 / 2 - stemWidth` (`:5437`), stroke `stemSlashThickness` 0.125 sp x 0.7 (`v450:172`, `:5443`). Grace notes take no time: the timeline does not move. A written accidental (`#`, `b`, `n`) is drawn left of the grace head at 0.7 scale.
- **Local choices (not MuseScore constants):** a 1 px floor on the grace stem and slash strokes; the chord's stem is taken as up for all acciaccaturas; ornaments are always placed above the chord (MuseScore picks above or below from the track for a trill, `tlayout.cpp:6512`, and from the ornament `anchor`); no appoggiatura.
- **Verified against the source** (read in the `fix(engraving)` commit): the constants and the formulas above. **Not verified:** the rendered result against MuseScore output (no pixel comparison); the `stemUpSE` anchor of Leland's `noteheadBlack`; the ink-to-origin relation of mordent and turn (the origin is the baseline, the glyph is drawn with its SMuFL bbox); the staff-top reference (taken as the MuseScore y 0 = top line, `staff_painter.dart` uses the same `trebleBottomY - 4 sp`); MuseScore's `noteHeadWidth` for the font in use (taken from the Leland bbox).
- **Codepoints:** checked against `references/MuseScore/fonts/smufl/glyphnames.json` and the cmap of `app/assets/fonts/Leland.otf`. U+E560 is `graceNoteAcciaccaturaStemUp` (a whole acciaccatura glyph with its own stem), so the earlier "U+E560 slash" was wrong.
- **Not done (out of scope for PR 4):**
  - Appoggiatura syntax and drawing (`graceNoteAppoggiaturaStemUp`, U+E562).
  - Playback: grace notes do not steal time from the main note.
  - Grace notes are not in the bar sum, so lint does not check them.
  - Ledger lines of a grace note are drawn at its scaled head width, which is approximate.
  - No collision check against the previous note or beams: a grace note at a dense rhythm can touch the note before it, and an ornament can touch a beam. Verified only by a rendered image of a test score, not against MuseScore output.

### 5. Repeats, Voltas & System Breaks (`repeat_layout.dart`)
- **Reference:** MuseScore `measurelayout.cpp` and `barline.cpp`.
- **Repeat Barlines:** Thick-thin dual line with dots in staff spaces 2 and 3.
- **Volta Brackets:** Horizontal line above measure with open/closed right edge and number label ("1.", "2.").
- **Navigation:** Segno, Coda, D.C. al Fine, D.S. al Coda.
