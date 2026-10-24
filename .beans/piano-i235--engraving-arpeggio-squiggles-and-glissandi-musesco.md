# piano-i235: Engraving: arpeggio squiggles and glissandi (MuseScore arpeggiolayout.cpp)

**Status:** todo  
**Type:** feature  
**Parent:** piano-r9p5  

## Context
Piano arrangements frequently employ rolled/arpeggiated chords (e.g. Chopin Nocturnes, Debussy Arabesques) and glissandi. MuseScore renders arpeggios as vertical undulating wiggle paths adjacent to chords and glissandi as connecting diagonal lines (`docs/specs/sheet-engraving.md`).

Algorithmic reference: MuseScore `references/MuseScore/src/engraving/rendering/score/arpeggiolayout.cpp` and `tlayout.cpp`.

Blocked by: none.

## Higher Goal
Render expressive chord arpeggiation and glissandi with precise SMuFL glyphs and layout.

## Acceptance Criteria
- [ ] Arpeggio squiggle: vertical repeating wave line (`wiggleArpeggiato`, U+E634) spanning the exact vertical bounds of the chord noteheads.
- [ ] Arpeggio direction arrows: upward and downward arrowheads for directed arpeggios.
- [ ] Clearance: arpeggio path positioned `space * 0.8` left of leftmost accidental or notehead without colliding with preceding beats.
- [ ] Glissando: diagonal straight or wavy line between two notes with centered italic "gliss." label.
- [ ] Dedicated helper `arpeggio_layout.dart` under `app/lib/ui/staff/`.
- [ ] Unit tests under `app/test/ui/staff/arpeggio_layout_test.dart`.

## Out of Scope
- Microtonal pitch bends.

## Summary of Changes
*(To be completed upon finishing)*
