---
# piano-p8fz
title: 'Practice mode: tunes for nodes that require an accidental'
status: scrapped
type: task
priority: normal
created_at: 2026-10-21T20:23:12Z
updated_at: 2026-10-21T21:18:51Z
parent: piano-c6v1
---

## Context
essentials-3/flats and essentials-3/amazing-grace got 0 rubric-passing candidates in 12 (missing required accidental pattern; gen spec key is always C). Blocked by: none.

## Higher Goal
Every node with a skill spec offers practice tunes (epic piano-c6v1).

## Acceptance Criteria
- [ ] Pick the spec key from the taught keys, or mask toward the required pattern
- [ ] Both nodes yield passing tunes in a benchmark round

## Out of Scope
Model retraining.

## Reasons for Scrapping

Streaming chunks are checked against the taught set without the node required patterns, so these nodes now get tunes.
