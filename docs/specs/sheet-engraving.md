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
| Chord Symbols & Lyrics | `harmonylayout.cpp`, `lyricslayout.cpp` | Planned (PR 6) | `harmony_layout.dart` |
| Ottava lines (8va/8vb) | `dom/ottava.cpp`, `rendering/score/tlayout.cpp` (`layoutTextLineBaseSegment`), `rendering/score/tdraw.cpp` (`drawTextLineBaseSegment`) | Delivered (dashed line, end hook, displayed pitch; no `8va` text label, no collision avoidance) | `ottava_layout.dart` |
| Mid-system small clef | `rendering/score/segmentlayout.cpp:44-48`, `dom/clef.cpp:109-115` | Not delivered (see module 6) | - |
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

### 6. Ottava Lines (`ottava_layout.dart`, `staff_painter.dart`)
- **Reference:** `dom/ottava.cpp` and `dom/ottava.h:67-74` (`ottavaDefault`: 8va shift +12 at `ottava.h:68`, 8vb shift -12 at `ottava.h:69`); `dom/staff.cpp:1278-1299` (spanner covers its tick range); `dom/note.cpp:2653-2674` (`ppitch`, sounding = written + shift); `rendering/score/tlayout.cpp:5929-6200` (`layoutTextLineBaseSegment`, hook sign at `:6102-6103`); `rendering/score/tdraw.cpp:1576-1599` and `:1805-1935` (dash setup and drawing).
- **Style values** (`data/styles/legacy-style-defaults-v450.mss`, same values in `style/styledef.cpp`):

| Value | Style key | Source | Used as |
|---|---|---|---|
| Line width 0.11 sp | `ottavaLineWidth` | mss:544, styledef.cpp:727 | stroke width |
| Dash 6, gap 6 | `ottavaDashLineLen`, `ottavaDashGapLen` | mss:546-547, styledef.cpp:729-730 | pattern in line widths (tdraw.cpp:1593-1598) |
| Hook 1 sp | `ottavaHookAbove` / `ottavaHookBelow` | mss:542-543, styledef.cpp:725-726 | hook end; the .mss `-1` for 8vb is normalised to `+1` on load for files before 460 (style.cpp:391-392) |
| Line at -2 sp / +2 sp | `ottavaPosAbove` / `ottavaPosBelow` | mss:540-541, styledef.cpp:723-724 | line y from the top / bottom staff line (ottava.cpp:450-452) |
| HOOK_90 end, no begin hook | `END_HOOK_TYPE` default | ottava.cpp:237, 239, 361 | hook at the end only |
| 8va above (0), 8vb below (1) | `ottava8VAPlacement` / `ottava8VBPlacement` | mss:510-511 | staff side |

- **Pitch display:** a note under a spanner (same hand, `start <= beat < end`) is drawn at `pitch - shift`: an octave lower under 8va, higher under 8vb. The sounding MIDI pitch is unchanged, so audio and grading read the same pitches. The shift is applied in the `StaffPainter` constructor (`OttavaLayout.displayNotes`), so accidentals, stems, ledgers and burst rings all use the displayed pitch. Indices into `notes` do not change.
- **Geometry:** the line runs from the note at the start beat to the note at the end beat (left edges, as hairpins). 8va sits 2 sp above its staff's top line, 8vb 2 sp below its staff's bottom line. Hooks point towards the staff (down for 8va, up for 8vb).
- **Local choices (no source):**
  - The hook is drawn solid. MuseScore draws it dashed with `distributedDashPattern(6, 6, hookLength / lineWidth)`. For a 1 sp hook at 0.11 sp width that gives a gap of about -2.9 line widths, so the hook is solid. A line too short for the pattern is also drawn solid (`OttavaLayout.dashSpans`).
  - The spanner ends at the `{ottava_end}` beat (or the song end). MuseScore finds the end element instead (`ottava.cpp:445-448`).
- **Not implemented:**
  - The `8va` / `8vb` text label. MuseScore uses the `ottava` symbol when `ottavaNumbersOnly` is set (`ottava.cpp:201`, mss:528-531). The line has no label.
  - Collision avoidance with dynamics and hairpins (`ottavaMinDistance` 0.7 sp: mss:1546, styledef.cpp:2053). Marks are not moved.
  - 15ma and 22ma.
  - Left-hand `8va` (or right-hand `8vb`) uses the same offsets on that hand's staff. In a grand staff a left-hand `8va` sits 2 sp above the bass top line, which is 1 sp below the treble bottom line, so it can collide with treble notes.
- **Mid-system small clef (not delivered):** MuseScore's mid-measure clef is small with `smallClefMag` = 0.8 (mss:380, styledef.cpp:528), applied in `dom/clef.cpp:109-115`; `rendering/score/segmentlayout.cpp:44-48` marks such clefs small. The bean's "about 70%" does not match the source. A clef change also re-reads the following notes, so every note path (`_noteY`, ledgers, stems, accidentals) would need the clef in effect. That is deferred to a follow-up.
- **Verification:** unit tests cover the constants, the pitch shift, the notes list, the line and hook positions, and the dash coverage (`ottava_layout_test.dart`). Parser tests cover the directives (`song_marks_parser_test.dart`). A paint test checks that ink appears at the computed line and hook positions, by difference from a render without the ottava (`staff_ottava_paint_test.dart`). No pixel comparison with MuseScore has been done, and the 8vb hook direction has not been checked visually.
