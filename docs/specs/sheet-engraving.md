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
| Dynamics (p, mp, mf, f) & Hairpins| `rendering/score/dynamicslayout.cpp` | Planned (PR 1) | `dynamics_layout.dart` |
| Piano Damper Pedal (Ped., *) | `rendering/score/tlayout.cpp` (pedal) | Planned (PR 2) | `pedal_layout.dart` |
| Arpeggios & Glissandi | `rendering/score/arpeggiolayout.cpp` | Planned (PR 3) | `arpeggio_layout.dart` |
| Grace Notes & Ornaments | `rendering/score/tlayout.cpp` (ornaments)| Planned (PR 4) | `ornament_layout.dart` |
| Repeat signs & Voltas (1st/2nd) | `rendering/score/measurelayout.cpp` | Planned (PR 5) | `repeat_layout.dart` |
| Chord Symbols & Lyrics | `harmonylayout.cpp`, `lyricslayout.cpp` | Planned (PR 6) | `harmony_layout.dart` |
| Ottava (8va/8vb) & Clef Changes | `systemheaderlayout.cpp`, `tlayout.cpp` | Planned (PR 7) | `ottava_layout.dart` |
| Shared Staff Multi-Voice | `rendering/score/stavesharinglayout.cpp`| Planned (PR 8) | `voice_sharing_layout.dart` |
| Static Multi-System Page View | `rendering/score/pagelayout.cpp` | Planned (PR 9) | `score_page_view.dart` |

---

## Module Specifications

### 1. Dynamics and Hairpins (`dynamics_layout.dart`)
- **Reference:** MuseScore `dynamicslayout.cpp`.
- **Glyphs:** SMuFL range U+E520–U+E540 (`dynamicPiano`, `dynamicMezzo`, `dynamicForte`, `dynamicSforzando`, etc.).
- **Hairpins:** Quadratic or linear diverging stroke pairs (`<` and `>`), baseline positioned `space * 2.5` below bottom staff line (treble) or bottom bass line. Avoids collision with low stems.

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
