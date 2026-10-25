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
| Grace Notes & Ornaments | `rendering/score/tlayout.cpp` (ornaments)| Planned (PR 4) | `ornament_layout.dart` |
| Repeat signs, Voltas (1st/2nd) & navigation (segno, coda, D.C./D.S.) | `rendering/score/tdraw.cpp` (BarLine), `rendering/score/tlayout.cpp` (barLineWidth, volta segment), `rendering/score/measurelayout.cpp`, `dom/volta.cpp`, `dom/marker.cpp`, `dom/jump.cpp` | Delivered (rendering only: play order is not expanded, mid-piece key/meter not done; see section 5) | `repeat_layout.dart`, `staff_painter.dart` |
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
- **Reference:** MuseScore `tlayout.cpp` and `chordlayout.cpp`.
- **Acciaccatura:** Scaled notehead ($60\%$) with upward stem sliced by a diagonal slash (U+E560).
- **Trills & Turns:** Standard SMuFL glyphs (`ornamentTrill`, `ornamentTurn`, `ornamentMordent`) centered above the notehead.

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
