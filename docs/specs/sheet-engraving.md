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
| Piano Damper Pedal (Ped., *) | `dom/pedal.cpp`, `rendering/score/tlayout.cpp` (layoutPedal, layoutPedalSegment) | Delivered (down/release marks, bracket line, change notches; hooks approximated) | `pedal_layout.dart` |
| Arpeggios & Glissandi | `rendering/score/arpeggiolayout.cpp` | Delivered (PR 3; straight glissando only) | `arpeggio_layout.dart` |
| Grace Notes & Ornaments | `rendering/score/tlayout.cpp` (`layoutOrnament` 4259, `layoutTrillSegment` 6477, `layoutStemSlash` 5378), `rendering/score/chordlayout.cpp` (grace notes 621, articulations 1048), `dom/trill.cpp` (`symbolLine` 73) | Delivered (PR 4, `piano-rlp3`: trill, mordent, turn, acciaccatura; constants aligned with MuseScore source, rendering not compared to MuseScore output; no appoggiatura, no playback) | `ornament_layout.dart` |
| Repeat signs, Voltas (1st/2nd) & navigation (segno, coda, D.C./D.S.) | `rendering/score/tdraw.cpp` (BarLine), `rendering/score/tlayout.cpp` (barLineWidth, volta segment), `rendering/score/measurelayout.cpp`, `dom/volta.cpp`, `dom/marker.cpp`, `dom/jump.cpp` | Delivered (rendering only: play order is not expanded, mid-piece key/meter not done; see section 5) | `repeat_layout.dart`, `staff_painter.dart` |
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

### 2. Piano Damper Pedal (`pedal_layout.dart`, `staff_painter.dart`)
- **Reference:** MuseScore `dom/pedal.cpp` (`linePos`, `defaultPosSid`, `createLineSegment`) and `rendering/score/tlayout.cpp` (`layoutPedal`, `layoutPedalSegment`).
- **Data:** song JSON `{ped}` presses the pedal (a `{ped}` while it is down is a change) and `{ped-up}` releases it. A span left down runs to the end of the song with no release. See [content-format.md](content-format.md#directives-dynamics-and-hairpins).
- **Glyphs** (`fonts/smufl/glyphnames.json`): `keyboardPedalPed` U+E650 (`Ped.`) at the down; `keyboardPedalUp` U+E655 (`*`) after the release.
- **Horizontal** (`Pedal::linePos`): `Ped.` starts 0.5 sp left of its note; the line starts 0.2 sp after the glyph. A release point sits 0.75 sp before the next note; a change sits 1.25 sp before the note that re-presses.
- **Vertical:** `pedalPosBelow` y 2.5 sp below the bottom staff line. The line moves down past noteheads and stems that overlap its release hook (box 1.2 sp high, the `pedalHookHeight`), keeping `pedalMinDistance` (0.5 sp here, the dynamics clearance).
- **Modern bracket:** line `pedalLineWidth` 0.11 sp (style value). Each change is a `/\` notch 0.35 sp half-wide and 0.6 sp high, approximating MuseScore's two 45-degree hooks. A release ends in a vertical hook 1.2 sp high, with the `*` glyph after it.
- **Not implemented:** half-pedal and una corda / sostenuto marks (`keyboardPedalHalf`, `keyboardPedalSost`), parentheses, and the `pedalText` style overrides (fixed in the layout code, not read from the style file). Pedal is not graded (no CC64 input).
- **Where it shows:** only the practice stage (`practice_stage.dart`) passes `pedals` to `StaffPainter`. The static score page view (`score_page_view.dart`) does not draw dynamics, hairpins or pedals yet. Imported scores (MusicXML, MIDI, ABC, LilyPond) carry no pedal data ([score-import-and-page-view.md](score-import-and-page-view.md)).
- **Demo song:** `content/songs/pedal-demo.json` (original, CC-BY-SA-4.0) has three spans: a change in bar 3, a release in bar 4 and bar 6, and a span left down to the end. No course uses it; it exists to inspect the marks in the app.
- **Known limitations (verified, not fixed):**
  - *Font metrics:* widget tests without the music font paint placeholder boxes, so the pedal paint test checks that ink is present or absent in a region, not exact glyph shapes.
  - *Release star:* the `*` sits after the release hook and may run over the next bass notes. Not checked with the real font on screen.
  - *Notches:* a `/\` polyline, not MuseScore's two 45-degree hooks; no pixel comparison with MuseScore has been done.
  - *Lint:* `{ped}` and `{ped-up}` are not checked by `tools/content-cli` (see [content-format.md](content-format.md#directives-damper-pedal)).

### 3. Arpeggios and Glissandi (`arpeggio_layout.dart`)
- **Reference:** MuseScore `rendering/score/arpeggiolayout.cpp` (`computeHeight`, `calcTop`, `insetDistance`, `clearAccidentals`), `rendering/score/tlayout.cpp` (`layoutArpeggio`, `symbolLine`, `layoutGlissandoSegment`), `rendering/score/tdraw.cpp` (`draw(Arpeggio)`), `rendering/paddingtable.cpp:166-168`, `data/styles/legacy-style-defaults-v450.mss:441-442, 1169-1170`.
- **Status:** Delivered in PR 3 (`piano-i235`), reviewed against the source in the same PR: plain, up and down arpeggios (`{arp}`, `{arp:up}`, `{arp:down}`) and straight glissandi (`{gliss}`). Wavy glissando is not done. Glissando label placement is not yet checked against MuseScore.
- **Column:** the wiggle is `wiggleArpeggiatoUp` (U+EAA9), rotated -90 degrees for plain and up, stacked upwards from the bottom at a 0.88 sp advance (`uniEAA9` advance 220 units). Fill count is `round((h - endAdvance) / 0.88)`, then one end glyph. Up ends with `wiggleArpeggiatoUpArrow` (U+EAAD) rotated -90. Down stacks downwards, rotated +90, and also ends with U+EAAD (MuseScore does not use a separate down-arrow glyph).
- **Vertical span:** from the top head's top edge to the bottom head's bottom edge (head height 1.06 sp, Leland `uniE0A4`). A top note on a space rises 0.4 sp (both ends on spaces) or 0.25 sp (`calcTop`).
- **Horizontal:** right edge at `arpeggioNoteDistance` 0.4 sp left of each notehead, or `arpeggioAccidentalDistance` 0.3 sp left of an accidental (`paddingtable.cpp:166-168`). MuseScore's `insetDistance` refinements are not implemented.
- **Glissando:** straight line from the right edge of the start head to the left edge of the end head (the closest pair in pitch is a local choice, not a MuseScore rule). Line width 0.15 sp (`glissandoLineWidth`). Label text `gliss.` (`glissandoText`).
- **Codepoints:** checked against `references/MuseScore/fonts/smufl/glyphnames.json` and the app's `Leland.otf` cmap. U+E634 is `arpeggiatoUp` (a different glyph), not the wiggle.

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

### 5. Repeats, Voltas & Navigation (`repeat_layout.dart`, `staff_painter.dart`)
- **Status:** rendering delivered (piano-h90n, PR 5). Not done: play-order expansion in core (repeats do not change timing or grading), mid-piece key and time signature changes, lint and lessons for the new directives, re-arranging songs. System breaks are not part of this PR.
- **Reference (MuseScore, `references/MuseScore/src/engraving`):** `rendering/score/tdraw.cpp:668-694` (`drawDots`), `:810-882` (`START_REPEAT`, `END_REPEAT`, `END_START_REPEAT` line and dot offsets); `rendering/score/tlayout.cpp:1025-1070` (`barLineWidth`, the group width the segment reserves), `:5929-5995` (volta and jump text placement); `rendering/score/measurelayout.cpp:947-956` (barline right-aligned in its segment); `dom/volta.cpp:103-120, 316-391, 404, 417-419`; `dom/marker.cpp:42-45, 69-74, 166-183`; `dom/jump.cpp:40-55, 70`; `data/styles/legacy-style-defaults-v450.mss`.
- **Sourced values** (`legacy-style-defaults-v450.mss` line, `v450:n`):
  - Repeat group: `barWidth` 0.18 sp (:91), `endBarWidth` 0.55 sp (:93), `endBarDistance` 0.37 sp (:95, gap thin-thick), `repeatBarlineDotSeparation` 0.37 sp (:96, gap line-dots). `repeatBarTips` 0 (:97), so MuseScore draws no bracket tips; this app matches.
  - Voltas: `voltaPosAbove` y=-3 (:490, line height), `voltaHook` 2.2 (:491, hook length, `volta.cpp:71-72`), `voltaLineWidth` 0.11 (:492), `voltaOffset` x=0.6 y=2.2 (:503, label offset from the line start, `tlayout.cpp:5977`), `voltaFontSize` 11 pt, spatium dependent, bold (:497-500, `types.h:1069`).
  - Jumps and marks: `jumpPosAbove` y=-2 (:643), `markerPosAbove` y=-2 (:644), `repeatRightFontSize` 11 pt normal (:1094-1097), `repeatMinDistance` 0.5 (:1549, `marker.cpp:44`).
  - Spatium 1.74978 mm (:1606) = 4.96 pt. Point sizes become staff spaces with 1 in = 72 pt = 25.4 mm (standard conversion, local).
  - Code, not style: segno and coda `MUSIC_SYMBOL_SIZE` 18 pt, centred on the symbol (`marker.cpp:180-183`); volta line `ABOVE` (`volta.cpp:106`), label `BELOW` the line (`volta.cpp:109`); end hook `HOOK_90` only for a closed ending (`volta.cpp:404`).
- **Repeat signs:** `|:` is thick, thin, dots (`START_REPEAT`). `:|` is dots, thin, thick (`END_REPEAT`). `:|:` is dots, thin, thick, thin, dots (`END_START_REPEAT`), offsets from `tdraw.cpp:813-882`. Dots are `repeatDot` (U+E044) per staff at 1.5 sp and 2.5 sp above the bottom line (spaces 2 and 3, `tdraw.cpp:683-684`). A repeat sign replaces the plain bar line at its beat, including the end barline when it sits at `endBeat` (the group then draws the closing lines).
  - *Local choice:* the group is centred on the x that spacing gives a plain bar line. MuseScore starts the group at the segment origin and reserves its width in the spacing (`tlayout.cpp:1044-1050`, `measurelayout.cpp:956`). This app reserves no width.
- **Voltas:** one line 3 sp above the top staff line (`voltaPosAbove`), 0.11 sp thick, with a 2.2 sp down hook at the left end. The right end has a hook only when the ending closes with a repeat sign (`volta.cpp:404`). The label `1.` or `2.` is bold, 11 pt, below the line at `voltaOffset` (0.6 sp right, 2.2 sp down from the start point). Start and end follow `Volta::linePos` (`volta.cpp:356-391`): after a repeat group, the start is the group's right ink minus half the line width. A plain bar line starts at `barWidth - lineWidth` centred, which is `+0.35 sp` at the bar centre. The end is the bar origin plus half the line width. For `:|` and `:|:` the origin is past the dots (`volta.cpp:387-388`).
  - *Local choice:* the group geometry is taken from the drawn ink, not from MuseScore's segment width. In both cases the result is the same as MuseScore when the segment width equals the group's ink width (`tlayout.cpp:1044-1050`).
  - *Local choice:* Edwin, MuseScore's label font (`voltaFontFace`, :496), is not available; the app's default bold font is used.
- **Navigation:** `segno` (U+E047) and `coda` (U+E048) above the top staff at their beat, centred on the note's x when a note sits on the beat. Glyph size 18 pt (3.63 sp em). Baseline `markerPosAbove` = 2 sp above the top line. Under a volta, the baseline is volta line + `repeatMinDistance` = 3.5 sp above the top line (*local approximation of MuseScore autoplace, which is not replicated*). `D.C. al Fine` and `D.S. al Coda` are text at 11 pt normal (`jump.cpp:51,53`, `v450:1094-1097`), with the same 2 sp baseline.
  - *Local choice:* MuseScore right-aligns jump text to its anchor (`repeatRightAlign` "right,baseline", :1099). This app left-aligns it at the beat x, because the content format puts the mark at a beat, not at the measure end.
- **Codepoints** (checked against `app/assets/fonts/Leland.otf` cmap and `references/MuseScore/fonts/smufl/glyphnames.json`): U+E044 `repeatDot`, U+E047 `segno`, U+E048 `coda` are in Leland and used. U+E040 `repeatLeft`, U+E041 `repeatRight`, U+E045 `dalSegno`, U+E046 `daCapo` are SMuFL names but NOT in Leland, so the bar lines are drawn as lines (MuseScore draws them as lines too, `tdraw.cpp`) and the jump marks as text. U+E043 `repeatDots` exists in Leland but is not used (two `repeatDot` glyphs, as in `drawDots`).
- **Leland metrics** (`leland.otf`, 1000 units per em; 1 em = 4 sp, so 250 units per sp; read with fontTools): `repeatDot` bbox 0..104 x -53..53, so 0.416 sp wide and centred on its baseline. `segno` 0..654 x 0..869, `coda` 0..745 x -113..735 (em widths 0.654 and 0.745).
- **Horizontal:** a volta end that meets a repeat sign stops at that sign's own origin (`volta.cpp:387-390`), past the dots for `:|`. A volta start after `|:` begins at the group's right ink (`volta.cpp:376`). Scrolling marks (voltas, navigation) go through the same edge-fade layer as notes; repeat signs are drawn with the bar lines.
- **Limitations (verified, not fixed):**
  - *Tight gaps:* with no spacing added for repeat signs, a group that falls in a gap of less than about 2 sp can touch the notes next to it. A start repeat on the first bar is drawn only when it clears the clef.
  - *Text labels:* volta numbers and D.C./D.S. text use the default font, not Leland or Edwin. Widget tests paint them as placeholder boxes.
  - *Single line:* the app paints one scrolling line, so a volta never breaks across systems (MuseScore `isAtSystemStart` branch in `volta.cpp:327,376` not used).
  - *Autoplace:* other items above the staff do not push a volta or a navigation mark up (MuseScore autoplace is not replicated). `repeatMinDistance` is used as a fixed 0.5 sp gap only for marks under a volta.
  - *Play count:* `playCount` text (`repeatPlayCountPreset`) is not drawn.
  - *No pixel comparison* with MuseScore output has been done.
- **Data:** song JSON directives, see [content-format.md](content-format.md#directives-repeats-voltas-and-navigation).

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
