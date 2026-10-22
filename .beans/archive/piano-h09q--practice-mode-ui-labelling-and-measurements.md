---
# piano-h09q
title: 'Practice mode: UI, labelling and measurements'
status: completed
type: task
priority: normal
created_at: 2026-10-21T19:32:15Z
updated_at: 2026-10-21T20:23:29Z
parent: piano-c6v1
---


## Context
D28: Practice entry per node; tunes labelled Generated, outside course levels, stars and song slots; nothing saved. Blocked by: the two sibling practice beans.

## Higher Goal
Endless level-fit practice per node (epic piano-c6v1).

## Acceptance Criteria
- [x] Practice button in the node sheet opens the practice page
- [x] loading state with download progress; retry up to N on rubric failure, then friendly error
- [x] Generated badge; no stars or progress written
- [x] another one button
- [x] widget test with a fake generator; unit test that a rubric-failing tune is not shown
- [x] docs/specs/practice-mode.md, ROADMAP checkboxes, research note with timings

## Out of Scope
Copy check, saving tunes, phone measurement if no device is reachable.

## Summary of Changes

GeneratedPracticePage (loading with progress, generating, play, done panel with Another one/Play again/mode chips, error states), Generated badge, Practice tune button in the node sheet, l10n in 6 locales, widget and unit tests, docs/specs/practice-mode.md, ROADMAP, docs/research/practice-mode-timing.md. Follow-ups: piano-x6qt (phone), piano-p8fz (accidental nodes).
