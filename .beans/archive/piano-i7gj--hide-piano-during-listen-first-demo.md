---
# piano-i7gj
title: Hide piano during listen-first demo
status: completed
type: task
created_at: 2026-10-21T00:48:56Z
updated_at: 2026-10-21T00:48:56Z
---

## Context
Listen-first demo showed the keyboard with key hints. Blocked by: none.

## Higher Goal
Let learners focus on the staff while listening.

## Acceptance Criteria
- [x] Keyboard hidden while demo plays
- [x] Keyboard returns on demo end or Skip
- [x] Keyboard toggle disabled during demo
- [x] Widget test `app/test/practice_stage_demo_test.dart` covers the above (flutter test: 40 passed)
- [x] flutter analyze: no issues in changed files

## Out of Scope
Reserving layout space to avoid the staff resizing when the keyboard hides (known).

## Summary of Changes
`practice_stage.dart`: keyboard shown only when `!_demo`; toggle button disabled while `_demo`.
`test/practice_stage_demo_test.dart`: widget tests with a stub Rust API.
