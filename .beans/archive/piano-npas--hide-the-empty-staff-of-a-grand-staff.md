---
# piano-npas
title: Hide the empty staff of a grand staff
status: completed
type: bug
priority: normal
created_at: 2026-10-22T19:45:17Z
updated_at: 2026-10-22T19:45:17Z
parent: piano-bjig
---

## Context

Blocked by: none. User report: a right-hand stage of a two-hand piece (Mikrokosmos) shows an empty bass staff.

## Higher Goal

Clean, readable practice screen.

## Acceptance Criteria

- [x] Grand staff collapses to treble or bass when one staff has no notes in the stage
- [x] Streamed practice keeps the grand staff
- [x] Unit test; practice-screen spec updated

## Out of Scope

Per-bar staff switching.

## Summary of Changes

`fitStaves` in `app/lib/practice/practice_stage.dart`, `app/test/fit_staves_test.dart`, `docs/specs/practice-screen.md`.
