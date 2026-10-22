---
# piano-zeje
title: Staff note cover like reference
status: completed
type: task
created_at: 2026-10-21T20:12:24Z
updated_at: 2026-10-21T20:12:24Z
---

## Context
User rejected generic edge-alpha fades (PR #56); match reference mechanics. Blocked by: none.

## Higher Goal
Practice staff feel matching the reference learning flow.

## Acceptance Criteria
- [x] Reference mechanics recorded with file:line (teardown doc)
- [x] Background cover over notes, opaque at clefs, clear at play bar / page start
- [x] Right-edge fade removed
- [x] flutter analyze + test pass

## Out of Scope
Dim overlay, page-slide animation timing (already exists).

## Summary of Changes
StaffPainter paints background + play bar again over notes in a dstIn-masked layer (coverRange); test; spec + teardown section.
