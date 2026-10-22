---
# piano-czsj
title: Mic input on Safari and iOS
status: todo
type: task
created_at: 2026-10-21T16:46:28Z
updated_at: 2026-10-21T16:46:28Z
parent: piano-kxi3
---

## Context
Mic input (D24) was built and checked on Chromium only. Safari/iOS differ: AudioWorklet support, getUserMedia device IDs, sample rate, autoplay/resume rules, background suspension. Blocked by: none.

## Higher Goal
Make mic practice work for iPad/iPhone students with acoustic pianos.

## Acceptance Criteria
- [ ] Mic setup, calibration and a Piano Basics level work in Safari macOS and iOS Safari
- [ ] Differences recorded in docs/specs/input.md

## Out of Scope
Native iOS app capture.
