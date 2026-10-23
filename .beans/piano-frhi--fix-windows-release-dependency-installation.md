---
# piano-frhi
title: Fix Windows release dependency installation
status: in-progress
type: bug
created_at: 2026-10-23T23:31:48Z
updated_at: 2026-10-23T23:31:48Z
parent: piano-bqkw
---

## Context
- Blocked by: none
- The release Windows job ran `npm ci --prefix tools/windows-packaging` from the repository root; the Windows runner reported no package-lock.json even though the lockfile is in that package directory.

## Higher Goal
- Make tagged releases build and publish the portable Windows executable alongside Android and web assets.

## Acceptance Criteria
- [x] Run npm ci from the Windows packaging project directory so its lockfile is used.
- [x] Document the release dependency installation behavior.
- [x] Validate a clean npm install.
- [ ] Confirm relevant GitHub workflow checks.
- [x] Remove the v0.1.x tags and associated releases to allow clean replacement tags.

## Out of Scope
- Changing release asset contents or redesigning Windows packaging.

## Summary of Changes
- Set `working-directory: tools/windows-packaging` before running `npm ci --ignore-scripts`.
- Documented the package-directory install in `docs/ARCHITECTURE.md`.
- Deleted GitHub Release `v0.1.0` and remote/local tags `v0.1.0` through `v0.1.3`.
