---
# piano-dndu
title: 'Practice studio UI: staff, keyboard, falling notes'
status: completed
type: task
priority: normal
created_at: 2026-10-16T04:51:30Z
updated_at: 2026-10-16T05:13:52Z
parent: piano-eeut
blocked_by:
    - piano-eddk
---


## Context
Phase 1 (docs/ROADMAP.md). Builds on staff spike.
## Higher Goal
First playable web version (D9).
## Acceptance Criteria
- [x] Delivered and verified, ROADMAP box ticked (staff + keyboard; falling notes split to a new bean)
## Out of Scope
Other Phase 1 items.

## Summary of Changes

- FRB API `app/rust/src/api/practice.rs` over the core session (`PracticeSession`, `inspect_song`).
- Content as assets: `tools/sync_content.py` → `app/assets/content` (git-ignored) + `ContentRepo` loader with locale strings.
- Screens: `HomePage` (course journey with stars), `LevelPage` (stages in order, scene captions, result card with retry/next), `PracticeStage` (staff with hit/miss colors and finger numbers, keyboard with next-key hint, Web MIDI + touch on one clock, play-along count-in).
- Verified in Chrome: lesson 1 played end to end with touch, 3 stars shown on the result card and the course list. Play-along is covered by core tests; not yet played by hand in the browser.
