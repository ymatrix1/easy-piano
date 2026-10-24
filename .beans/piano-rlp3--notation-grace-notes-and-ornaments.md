# piano-rlp3: Notation: grace notes and ornaments

**Status:** todo  
**Type:** feature  
**Parent:** piano-bjig  

## Context
The song format currently drops grace notes (Mikrokosmos Nos. 62 and 134: 4 notes lost), and the Soloist course Advanced I works around ornaments. Gould and MuseScore define precise geometric scaling and slash angles for acciaccaturas and placement rules for trills and turns (`docs/specs/sheet-engraving.md`).

Algorithmic reference: MuseScore `references/MuseScore/src/engraving/rendering/score/tlayout.cpp` (ornaments & trills) and `chordlayout.cpp` (grace notes).

Blocked by: none.

## Higher Goal
Play the exact ornamental notes composers wrote with standard professional engraving.

## Acceptance Criteria
- [ ] Syntax for acciaccatura, appoggiatura, trill, mordent, turn (written out vs symbolic).
- [ ] Engraving rendering (`ornament_layout.dart`):
  - Grace notes rendered with scaled notehead ($\approx 60\%$) and stem.
  - Acciaccatura diagonal stem slash (\uE560).
  - Trill symbols with wavy continuation line, mordents, and turns centered above noteheads.
- [ ] Core parser, lint, and playback audio handling (grace notes steal small fractional time before beat).
- [ ] Converter keeps them; Mikrokosmos Nos. 62 and 134 re-imported.
- [ ] Teaching lessons (scene, drill, song) for grace notes, trills, and mordents.

## Out of Scope
- Dynamics and pedal lines (`piano-boat`).

## Summary of Changes
*(To be completed upon finishing)*
