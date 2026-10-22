---
# piano-s21f
title: Grand staff brace/clef gap
status: completed
type: bug
priority: normal
created_at: 2026-10-21T19:55:54Z
updated_at: 2026-10-21T19:56:37Z
---

## Context
Brace on grand staff nearly touches clefs and the left edge. Blocked by: none.

## Higher Goal
Readable, conventionally engraved practice staff.

## Acceptance Criteria
- [x] System line drawn; brace just left of it, not clipped
- [x] Clefs start ~1 space after the line; notes clear of clefs
- [x] Single-staff layout unchanged
- [x] flutter analyze + flutter test pass

## Out of Scope
Bar line / note spacing changes.

## Summary of Changes
StaffPainter.systemLayout sets system line, clef x and clef clearance per Staves; staff lines start at the system line on grand staff; unit test; practice-screen spec documents spacing.
