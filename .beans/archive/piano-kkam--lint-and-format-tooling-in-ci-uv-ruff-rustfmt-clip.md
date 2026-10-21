---
# piano-kkam
title: Lint and format tooling in CI (uv, ruff, rustfmt, clippy, dart format)
status: completed
type: task
priority: normal
created_at: 2026-10-21T17:46:42Z
updated_at: 2026-10-21T17:46:47Z
---

## Context
CI ran only cargo test, content lint and flutter analyze/test. No Python tests, no formatters or linters. Blocked by: none.

## Higher Goal
Catch style and lint regressions before review; reproducible Python env.

## Acceptance Criteria
- [x] tools/melody-model uses pyproject.toml + uv.lock; torch only in optional `train` extra
- [x] ruff check/format configured and clean
- [x] CI python job (uv sync, ruff, pytest), cargo fmt/clippy, dart format
- [x] AGENTS.md checks updated

## Out of Scope
Behaviour changes; reformatting beyond mechanical fixes.

## Summary of Changes
pyproject.toml + uv.lock replace requirements.txt; ruff format + fixes; cargo fmt + 4 clippy fixes; CI python job, fmt/clippy steps, dart format step; AGENTS.md and melody-model spec updated.
