---
# piano-jist
title: 'Spike: Bravura staff rendering at 60 fps'
status: completed
type: task
priority: normal
created_at: 2026-10-16T02:43:04Z
updated_at: 2026-10-16T03:38:17Z
parent: piano-bqkw
---

## Context
See docs/ROADMAP.md Phase 0 and docs/specs/curriculum.md. Blocked by: none.
## Higher Goal
De-risk Phase 1.
## Acceptance Criteria
- [x] Result recorded in docs/ (research file, spec or decision)
## Out of Scope
Production code.

## Summary of Changes

Scrolling Bravura grand staff in `app/lib/ui/staff/`; ~180 fps, 0% jank, raster p95 0.52 ms with 456 notes. Results: `docs/research/staff-render-spike.md`.
