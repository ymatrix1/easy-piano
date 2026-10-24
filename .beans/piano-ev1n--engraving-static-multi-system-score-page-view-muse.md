# piano-ev1n: Engraving: static multi-system score page view (MuseScore pagelayout.cpp)

**Status:** todo  
**Type:** feature  
**Parent:** piano-r9p5  

## Context
Easy Piano's practice studio renders a continuous horizontally scrolling grand staff tied to the audio playhead. Learners and teachers also need a static, paginated score view to study the piece beforehand or export/print sheet music. MuseScore solves score line breaking, system justifications, and page margins in `references/MuseScore/src/engraving/rendering/score/pagelayout.cpp` and `scorepageviewlayout.cpp` (`docs/specs/sheet-engraving.md`).

Blocked by: none.

## Higher Goal
Provide a book/sheet mode displaying full compositions broken across multi-system vertical pages with justified measure spacing.

## Acceptance Criteria
- [ ] Measure line-breaking algorithm (Knuth-Plass or greedy break) fitting balanced measure counts per system line.
- [ ] System justification: measures within each horizontal system stretch proportionally to fill page width.
- [ ] Multi-system vertical scrolling or paginated page preview UI.
- [ ] Dedicated helper `score_page_layout.dart` under `app/lib/ui/staff/`.
- [ ] Unit tests verifying measure distribution and horizontal system justification under `app/test/ui/staff/score_page_layout_test.dart`.

## Out of Scope
- Interactive MIDI playback while in static print view (practice screen handles interactive scrolling).

## Summary of Changes
*(To be completed upon finishing)*
