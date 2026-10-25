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
| Chord Symbols & Lyrics (single verse) | `harmonylayout.cpp`, `lyricslayout.cpp`, `data/chords/chords_legacy.xml` | Delivered (PR 6, `piano-r16m`: rendering only, sizes and offsets from MuseScore style; sans font instead of Edwin; multi-verse, playback and lint not included) | `harmony_layout.dart` |
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
- **Reference:** MuseScore `rendering/score/harmonylayout.cpp` (chord symbol as text, placed above the staff; extension and bass runs), `data/chords/chords_legacy.xml` (the bass and slash render commands), `rendering/score/lyricslayout.cpp` (syllable centring, hyphens, melisma lines). Style values from `style/styledef.cpp` (MuseScore master) and `data/styles/legacy-style-defaults-v450.mss` (4.50). Where the two disagree, the value used is noted below.
- **Local choice** means the value is not from MuseScore. Every constant in `harmony_layout.dart` is either cited (file:line) or marked local. The docs below repeat the same labels.
- **Data:** song JSON directives, see [content-format.md](content-format.md#directives-chord-symbols-and-lyrics). Chords and lyrics are only read from song JSON; no level or content file uses them yet.
- **Font.** MuseScore uses Edwin 10 pt for both chord symbols (`chordSymbolAFontSize` 10, styledef.cpp:433; v450 mss:290-291) and lyrics (`lyricsOddFontSize` 10, styledef.cpp:141; v450 mss:57-58), spatium dependent (styledef.cpp:143 and 435). At the default spatium of 1.75 mm (styledef.cpp:804) 10 pt is 2.016 sp. The app draws both with its default sans font at that em size (`HarmonyLayout.chordSizeSp`, `lyricSizeSp`). Glyph shapes and widths differ from Edwin. Not SMuFL, so no codepoints.
- **Chord symbols** (`{chord:"Am7"}`): `ChordSymbol.parse` splits root (`A`-`G`, optional `#` or `b`), suffix (letters, digits and `+ - ( ) # ° ø`, up to 16 characters in total) and bass (`/` then a note). Anything else is ignored (lower-case root, empty bass, spaces, a second slash). Accidentals are ASCII `#` and `b`; MuseScore's chord-token parser is more general and is not ported (local simplification).
  - Runs, left to right, all at the root size (`chordExtensionMag` 1.0, styledef.cpp:551; `chordBassNoteScale` 1.0, styledef.cpp:558):
    - Root: at the baseline.
    - Extension: at the baseline, not raised (`chordExtensionAdjust` 0.0, styledef.cpp:552; `chordlist.cpp:1580-1581`). MuseScore raises modifiers as superscripts only in the JAZZ chord style (`chordlist.cpp:1625`, `1707-1713`); not implemented.
    - Slash `/`: 0.2 sp below the baseline and 0.04 sp left of the pen (`chords_legacy.xml:411`, renderBase `m:-0.2:1 / m:0.2:1`; legacy units of 1/5 sp converted by `compat/compatutils.cpp:594-606` for file version 1.24, `chordlist.cpp:2105`, `357-362`).
    - Bass: 0.4 sp below the baseline (`chords_legacy.xml:411`, `m:0.2:1 :n`, a total of 2/5 sp).
  - Placement: left aligned on the notehead of the hand's note at that beat (`chordSymbolAAlign` left, v450 mss:296; styledef.cpp:438 says HCENTER, see the conflict note). Any hand's note, or the nominal beat position when none. Baseline 2.5 sp above the top staff line (`chordSymbolAPosAbove` y -2.5, styledef.cpp:420; v450 mss:282). If notes at its onset rise above that, the baseline goes up so their top keeps 0.5 sp clear (`minHarmonyDistance` 0.5 sp, styledef.cpp:407; autoplace, `systemlayout.cpp:1101-1108`). Only noteheads count; stems and other elements are ignored (local simplification). Anchored to the top staff (treble on a grand staff; bass alone on a bass staff). MuseScore places a chord on its own staff. This is a deliberate deviation.
  - A chord in both hands at the same beat is drawn once, on the treble.
- **Lyrics** (`{lyric:"Hel-"}`, `{lyric:"lo"}`, `{lyric:"_"}`): `StaffLyric.fromDirective`.
  - A syllable is centred on the notehead centre (`ChordLayout::centerX` for a notehead: width/2 of the `noteheadBlack` 1.18 sp or `noteheadWhole` 1.688 sp, chordlayout.cpp:2440-2452; `note.cpp:1224`). **Open:** MuseScore's `lyricslayout.cpp:121-158` centres the text on the ChordRest origin, not the notehead centre. The chord origin is the notehead's left edge (`bsymbol.h:69` symbol align LEFT, `chordlayout.cpp:2801` noteX). I could not resolve from source alone whether that matches the visual centre. The app keeps the notehead centre until a visual check against MuseScore output.
  - One row per hand. The row baseline sits 3 sp below the bottom line of the hand's staff (`lyricsPosBelow` y 3, styledef.cpp:109; v450 mss:35; added to the staff height in `lyricslayout.cpp:612-614`). The row is lowered when its text top would come within 1 sp of the staff or of the lowest ink of the hand's onsets (noteheads, down stems): `lyricsMinTopDistance` 1 sp (styledef.cpp:110; v450 mss:36; collisions in `lyricslayout.cpp:630-660`). `lyricsMinDistance` (0.25 sp, styledef.cpp:112) is not used by MuseScore's lyric layout, and it is not used here. The row baseline is computed over all lyrics of the hand, so it does not move while the score scrolls. Left hand on a grand staff sits below the bass staff.
  - Grand staff: the bass staff top is `staffGap` 3 sp below the treble bottom line (`staff_painter.dart`, `staffGap`, an app value, not MuseScore's `staffDistance` 6.5 sp, styledef.cpp:55). A treble row at 3 sp therefore lands on the bass staff's top line, and the next lyric row can collide with bass ledger lines. Open item: a larger grand-staff gap or a shorter lyric row needs a decision.
  - Hyphen (syllable ends with `-`): from 0.05 sp after the syllable to 0.05 sp before the next one (`lyricsDashPad` 0.05 sp, styledef.cpp:124; `lyricslayout.cpp:831`). A gap under 0.4 sp is widened symmetrically to 0.4 sp (`lyricsDashMinLength`, styledef.cpp:114; `lyricslayout.cpp:329-340`). The line is at most 0.6 sp long (`lyricsDashMaxLength`, styledef.cpp:115; `lyricslayout.cpp:342`), centred in its part. One more hyphen per 16 sp of gap (`lyricsDashMaxDistance`, styledef.cpp:116; `lyricslayout.cpp:317-323`). Always drawn, even in a short gap (`lyricsDashForce` true, styledef.cpp:117). Thickness 0.1 sp (`lyricsDashLineThickness`, styledef.cpp:125). Height above the baseline: 0.5 of the x-height (`lyricsDashYposRatio` 0.5, styledef.cpp:126). X-height is a local choice of 0.5 em (Edwin metrics are not in the repo). Not drawn when the next lyric is an extension (local simplification).
  - Extension (`_`): a melisma line from 0.2 sp after the syllable before the run (`lyricsMelismaPad`, styledef.cpp:123; `lyricslayout.cpp:777`) to the right edge of the notehead of the last extension of the run (`lyricslayout.cpp:782-841`, melisma end at the end note's head). Not drawn when shorter than 1 sp (`lyricsMelismaMinLength`, styledef.cpp:130; `lyricsMelismaForce` false, styledef.cpp:129; `lyricslayout.cpp:246-254`). Thickness 0.1 sp (`lyricsLineThickness`, styledef.cpp:120). The run ends at the last `_` in the hand; MuseScore's melisma end is its tick span (`lyricslayout.cpp:392-486`), which is not modelled.
  - A lyric in both hands at the same beat and with the same text is drawn once, on the treble staff.
- **Deliberate deviations (not MuseScore behaviour):**
  - Chord and lyric rows are anchored to one staff (see above); chords of the bass hand go above the top staff.
  - Grand-staff gap (`staffGap` 3 sp, not `staffDistance` 6.5 sp): with the lyric row at 3 sp, the treble lyric row touches the bass staff's top line. Not fixed here.
  - Sans font for Edwin, and a local x-height of 0.5 em.
- **Not implemented (by design or not yet):**
  - Multi-verse stacking (verse 2, verse 3) and verse numbers.
  - Playback, grading or any use of chord and lyric text outside drawing.
  - Core parser and lint checks for chord and lyric text. Core accepts any directive; lint does not check these yet.
  - Chord symbol and lyric collisions with dynamics, hairpins, finger labels and ornaments: no clearance pass beyond the notehead rows above.
  - Lyric lines are not broken across systems (the app paints one scrolling line).
  - JAZZ chord style (superscript modifiers), chord-token parser (`chords_legacy.xml`), `harmonyPlacement` below, stacked modifiers.
- **Conflict between sources:** `chordSymbolAAlign` is `left,baseline` in the v450 file (mss:296) and `HCENTER,BASELINE` in `styledef.cpp:438`. The app follows v450, as the user's reference. Raise this before changing either.
- **Known limitations (verified, not fixed):**
  - Text widths come from the font loaded at run time. Paint tests use flutter_test's placeholder font, so they check for ink in regions, not exact glyph boxes.
  - No pixel comparison with MuseScore output has been done. The lyric centring above is an open item.
  - Parser (`song_marks_parser.dart`) and geometry (`harmony_layout.dart`) are unit-tested. Paint tests (`harmony_paint_test.dart`) show that each mark adds ink where expected.
