---
# piano-rxm2
title: 'Monorepo CI: Flutter, Rust, content lint'
status: completed
type: task
priority: normal
created_at: 2026-10-16T04:51:30Z
updated_at: 2026-10-20T21:38:40Z
parent: piano-eeut
---


## Context
Phase 1 (docs/ROADMAP.md). Blocked by: none.
## Higher Goal
First playable web version (D9).
## Acceptance Criteria
- [x] Delivered and verified, ROADMAP box ticked
## Out of Scope
Other Phase 1 items.
## Summary of Changes
`.github/workflows/ci.yml`: rust job (cargo test in core, content lint) and flutter job (sync_content, analyze, test), cached, Flutter 3.47.7. Web build stays in deploy-web.yml. README and ROADMAP updated. PR #29.
