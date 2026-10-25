---
# piano-i235
title: ""
status: completed
type: task
priority: normal
created_at: 2026-10-25T02:37:36Z
updated_at: 2026-10-25T02:38:03Z
---

# piano-i235: Engraving: arpeggio squiggles and glissandi (MuseScore arpeggiolayout.cpp)

**Status:** completed  
**Type:** feature  
**Parent:** piano-r9p5  

## Context
Piano arrangements frequently employ rolled/arpeggiated chords (e.g. Chopin Nocturnes, Debussy Arabesques) and glissandi. MuseScore renders arpeggios as vertical undulating wiggle paths adjacent to chords and glissandi as connecting diagonal lines (`docs/specs/sheet-engraving.md`).

Algorithmic reference: MuseScore `references/MuseScore/src/engraving/rendering/score/arpeggiolayout.cpp` and `tlayout.cpp`.

Blocked by: none.

## Higher Goal
Render expressive chord arpeggiation and glissandi with precise SMuFL glyphs and layout.

## Acceptance Criteria
- [x] Arpeggio squiggle: vertical repeating wave line (`wiggleArpeggiatoUp`, U+EAA9; the bean's U+E634 is `arpeggiatoUp`) spanning the chord noteheads (head edges padded by 0.5 sp).
- [x] Arpeggio direction arrows: upward and downward arrowheads for directed arpeggios.
- [x] Clearance: arpeggio path positioned `space * 0.8` left of leftmost accidental or notehead. Collision with preceding beats is not checked (the wiggle sits in the gap before its chord).
- [x] Glissando: diagonal straight line between two notes with centered italic "gliss." label. Wavy line not done.
- [x] Dedicated helper `arpeggio_layout.dart` under `app/lib/ui/staff/`.
- [x] Unit tests under `app/test/ui/staff/arpeggio_layout_test.dart`.

## Out of Scope
- Microtonal pitch bends.

## Summary of Changes
- pp/lib/ui/staff/arpeggio_layout.dart: geometry (wiggle stack, arrows, clearance, glissando ends, label, closest-pitch pair) and SMuFL codepoints.
- song_marks_parser.dart: {arp}, {arp:up}, {arp:down}, {gliss} (gliss ends at the next note of its hand, rests skipped).
- staff_painter.dart: draws arpeggios and glissandi; practice_stage.dart passes them in.
- Tests: rpeggio_layout_test.dart (geometry and paint-diff), song_marks_parser_test.dart (directives).
- Not done: wavy glissando, core lint for the new directives, content using them.
