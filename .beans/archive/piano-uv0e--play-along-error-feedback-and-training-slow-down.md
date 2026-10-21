---
# piano-uv0e
title: Play-along error feedback and training slow-down
status: completed
type: task
priority: normal
created_at: 2026-10-21T20:11:11Z
updated_at: 2026-10-21T20:46:41Z
parent: piano-eeut
---

## Context
Play-along has no per-note error feedback (wait mode has a wrong-note splash) and no adaptive slow-down when the student struggles. Blocked by: none.

## Higher Goal
Match the reference learning loop: clear feedback on errors, and a training mode that slows down and loops hard sections before returning to full speed.

## Acceptance Criteria
- [x] Reference mechanics researched and recorded with file:line in docs/research/simply-piano-teardown.md
- [x] Rust core emits per-note feedback events (wrong, missed, early, late) and a training suggestion (tempo step, section) with unit tests
- [x] Practice UI shows error animations in play-along and the slow-down flow
- [x] Specs exercise-engine.md and practice-screen.md updated; proposed decision recorded
- [x] cargo test, flutter analyze, flutter test pass; web build screenshots

## Out of Scope
staff_painter.dart rework (PR #56); mic input.

## Summary of Changes
- core: `Feedback`/`Timing` events (`take_feedback`), `Frame::streak`, training mode (`Settings::training`, `SectionEvent`, `take_section_event`): per-section grading, early fail, replay, 75% practice after 2 failures, full tempo again after a passed practice run; assists use the lowest tempo. 5 new unit tests.
- bridge: `take_feedback`, `take_section_event`, `training` flag.
- app: `play_feedback.dart` overlays (wrong-key flash, missed-key outline, early/late tag), training banners and clock restart in `practice_stage.dart`, l10n strings.
- docs: teardown section with file:line, exercise-engine and practice-screen specs, D31 (proposed), ROADMAP.
