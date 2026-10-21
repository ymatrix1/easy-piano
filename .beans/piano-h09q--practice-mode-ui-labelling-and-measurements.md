---
# piano-h09q
title: 'Practice mode: UI, labelling and measurements'
status: in-progress
type: task
created_at: 2026-10-21T19:32:15Z
updated_at: 2026-10-21T19:32:15Z
parent: piano-c6v1
---

## Context
D28: Practice entry per node; tunes labelled Generated, outside course levels, stars and song slots; nothing saved. Blocked by: the two sibling practice beans.

## Higher Goal
Endless level-fit practice per node (epic piano-c6v1).

## Acceptance Criteria
- [ ] Practice button in the node sheet opens the practice page
- [ ] loading state with download progress; retry up to N on rubric failure, then friendly error
- [ ] Generated badge; no stars or progress written
- [ ] another one button
- [ ] widget test with a fake generator; unit test that a rubric-failing tune is not shown
- [ ] docs/specs/practice-mode.md, ROADMAP checkboxes, research note with timings

## Out of Scope
Copy check, saving tunes, phone measurement if no device is reachable.
