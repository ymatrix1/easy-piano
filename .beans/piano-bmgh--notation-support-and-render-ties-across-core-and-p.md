---
# piano-bmgh
title: 'Notation: support and render ties across core and practice stage'
status: completed
type: task
priority: high
created_at: 2026-10-24T18:59:25Z
updated_at: 2026-10-24T19:13:19Z
parent: piano-bjig
---

Context
Easy Piano supports {tie} directive in JSON and has rendering primitives in engraving_decorations.dart, but TargetView, session engine and PracticeStage do not preserve or render ties for songs with {tie} (e.g. Mikrokosmos, Satie).

Higher Goal
Authentic score reading and visual playback of ties (ligaduras de prolongamento) matching MuseScore slurtielayout.cpp standards and method books.

Acceptance Criteria
- [x] easy_piano_core exposes tie flags on targets (Target and TargetView).
- [x] PracticeStage maps tie flags to StaffNote(tie: true).
- [x] StaffPainter properly connects tied notes across beats and barlines.
- [x] Core unit tests verify tie parsing and target propagation.
- [x] App unit/widget tests verify ties are preserved and rendered.

Out of Scope
- Repeats, voltas and mid-piece key/meter changes (piano-h90n).
- Slurs/legato expression marks (piano-boat).

Summary of Changes
(To be completed upon finishing)

## Summary of Changes
- Propagated {tie} token in asy_piano_core::song::Song::timeline to set TimedNote.tie = true.
- Extended Target and TargetView structs with 	ies: Vec<bool> in core/src/session.rs and pp/rust/src/api/practice.rs.
- Regenerated Flutter Rust Bridge bindings (lutter_rust_bridge_codegen generate).
- Updated PracticeStage._addTargets in pp/lib/practice/practice_stage.dart to instantiate StaffNote with 	ie: hasTie.
- Added Rust tests in core/src/song.rs and core/src/session.rs, plus widget test in pp/test/practice/practice_stage_demo_test.dart verifying ties are rendered.
- All 110 core unit tests, 155 Flutter tests, clippy and formatting checks pass cleanly.
