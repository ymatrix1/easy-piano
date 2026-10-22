---
# piano-2uz9
title: 'Melody model: seed-variation and style-strength knobs'
status: todo
type: task
tags:
    - melody-gen
created_at: 2026-10-22T00:18:35Z
updated_at: 2026-10-22T00:18:35Z
parent: piano-bovj
---

## Context
User asked for knobs: how close to a known song, how strongly in a style.
Roadmap: docs/research/melody-model-roadmap.md. Blocked by: none.

## Higher Goal
Better generated practice tunes from our own model.

## Acceptance Criteria
- [ ] Seed variation from a PD/our song (closeness 0-1 via kept plan and bars + FIM)
- [ ] Style strength via classifier-free guidance (scale 0-2+)
- [ ] Both exposed in generate.py and the demo; listening samples

## Out of Scope
Copyrighted seed songs.

## Summary of Changes
