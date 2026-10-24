---
# piano-ev1n
title: ""
status: completed
type: task
priority: normal
created_at: 2026-10-24T20:31:58Z
updated_at: 2026-10-24T20:32:04Z
---

# piano-ev1n: Engraving: static multi-system score page view (MuseScore pagelayout.cpp)

**Status:** completed  
**Type:** feature  
**Parent:** piano-r9p5  

## Context
Easy Piano's practice studio renders a continuous horizontally scrolling grand staff tied to the audio playhead. Learners and teachers also need a static, paginated score view to study the piece beforehand or export/print sheet music. MuseScore solves score line breaking, system justifications, and page margins in `references/MuseScore/src/engraving/rendering/score/pagelayout.cpp` and `scorepageviewlayout.cpp` (`docs/specs/sheet-engraving.md`).

Blocked by: none.

## Higher Goal
Provide a book/sheet mode displaying full compositions broken across multi-system vertical pages with justified measure spacing.

## Acceptance Criteria
- [x] Measure line-breaking algorithm (Knuth-Plass or greedy break) fitting balanced measure counts per system line.
- [x] System justification: measures within each horizontal system stretch proportionally to fill page width.
- [x] Multi-system vertical scrolling or paginated page preview UI.
- [x] Dedicated helper `score_page_layout.dart` under `app/lib/ui/staff/`.
- [x] Unit tests verifying measure distribution and horizontal system justification under `app/test/ui/staff/score_page_layout_test.dart`.

## Out of Scope
- Interactive MIDI playback while in static print view (practice screen handles interactive scrolling).

## Summary of Changes
- Implemented `ScorePageLayout` in `app/lib/ui/staff/score_page_layout.dart` matching MuseScore `pagelayout.cpp` & `scorepageviewlayout.cpp`:
  - `buildMeasures`: partitions notes into discrete measures with intrinsic minimum widths calculated using segment spacing density.
  - `breakSystems`: balanced line breaking packing measures into systems within printable width bounds.
  - `justifyMeasures`: proportional expansion distributing remaining line whitespace so right barlines align to margin.
  - `paginate`: vertically stacks systems onto standard multi-page sheets based on page heights and margins.
- Created `ScorePageView` and `ScorePageSheet` in `app/lib/ui/staff/score_page_view.dart`:
  - Sheet music paper styling (ivory tint, page drop shadows, title, composer, page numbering).
  - Zoom controls (+ / -) and page navigation (`Page X / Y`).
  - Integrated book icon action button in PracticeStage top bar to switch into static study mode.
- Added comprehensive unit and widget tests:
  - `app/test/ui/staff/score_page_layout_test.dart`: verifies measure partitioning, system packing, proportional justification, pagination.
  - `app/test/ui/staff/score_page_view_test.dart`: widget test verifying full UI rendering, pagination controls, zoom controls.
- All Flutter and Rust tests passing cleanly without warnings.
