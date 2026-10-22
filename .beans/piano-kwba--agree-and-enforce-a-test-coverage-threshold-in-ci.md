---
# piano-kwba
title: Agree and enforce a test coverage threshold in CI
status: todo
type: task
created_at: 2026-10-22T00:12:26Z
updated_at: 2026-10-22T00:12:26Z
---

## Context

Rule 9 requires tests with every code change, but CI only fails on failing tests, not on missing ones. Blocked by: none.

## Higher Goal

Make "every change has tests" checkable, not only a convention.

## Acceptance Criteria

- [ ] Coverage tools run in CI for Dart (flutter test --coverage), Rust (cargo llvm-cov) and Kotlin (JaCoCo)
- [ ] User picks thresholds (overall or changed lines)
- [ ] CI fails below them

## Out of Scope

Backfilling tests for old code.
