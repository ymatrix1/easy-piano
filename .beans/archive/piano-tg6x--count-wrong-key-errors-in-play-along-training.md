---
# piano-tg6x
title: Count wrong-key errors in play-along training
status: completed
type: bug
priority: normal
created_at: 2026-10-23T21:43:44Z
updated_at: 2026-10-23T21:45:42Z
parent: piano-eeut
---

## Context

Blocked by: none. Play-along training decided section failures from missed notes only, so repeated wrong pitches could fail to trigger slow practice.

## Higher Goal

Make adaptive play-along practice respond to repeated wrong-key errors as well as missed notes.

## Acceptance Criteria

- [x] Wrong-key errors contribute to the section failure threshold.
- [x] Repeated errors trigger section replay and 75% practice tempo after the configured failures.
- [x] Core tests cover wrong-key-triggered replay and slow practice.
- [x] Exercise-engine spec matches the behavior.

## Out of Scope

Changing timing grading, wait mode, or the slow-practice tempo.

## Summary of Changes

Tracked wrong-key presses per critical section, counted them against the existing early-failure budget with misses, reset the section count on replay, added coverage for full-speed replay and 75% practice, and updated the exercise-engine spec.
