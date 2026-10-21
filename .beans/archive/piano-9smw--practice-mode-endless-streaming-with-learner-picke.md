---
# piano-9smw
title: 'Practice mode: endless streaming with learner-picked level and rules'
status: completed
type: task
priority: normal
created_at: 2026-10-21T21:12:05Z
updated_at: 2026-10-21T21:18:50Z
parent: piano-c6v1
---

## Context
User asked (2026-10-21) for practice mode to stream in real time: pick constraints and level, then play an endless generated stream. Chose a true endless stream (core session append) and a Practice tab card. Blocked by: none.

## Higher Goal
Endless level-fit practice (epic piano-c6v1).

## Acceptance Criteria
- [x] Practice tab card opens a setup: level (1-5), style, hands, tempo, note values, mode; game-style controls
- [x] Core Session::extend appends targets; bridge PracticeSession.extend
- [x] PracticeStage plays a growing song (SongFeed), asks for more ahead of the playhead
- [x] Each 4-bar chunk rubric-checked as part of the song so far; leap rule across chunks (mask.start)
- [x] Node-sheet Practice tune button removed
- [x] Tests (core, JS mask, Dart stream and pages); verified in the real web UI; spec and timing note updated

## Out of Scope
Native runtime, phone measurement (piano-x6qt).

## Summary of Changes

Practice tab card -> setup (level 1-5, style, hands, tempo, note values, mode; game-style chips). Core Session::extend + bridge PracticeSession.extend; PracticeStage(feed:) extends session and staff, asks for more via SongFeed.onDemand. PracticeStream writes 4-bar chunks, rubric-checks the song so far, carries the last note (mask.start). Node-sheet button removed. Verified in the release web UI (6 chunks, 0.27-0.48 s each).
