---
# piano-ndp2
title: 'Web load: splash until first frame, bundle content'
status: completed
type: bug
priority: normal
created_at: 2026-10-21T20:53:12Z
updated_at: 2026-10-21T20:56:51Z
---

## Context
Web app showed a blank navy screen for seconds while loading. Blocked by: none.

## Higher Goal
Fast, reliable first load on web previews and production.

## Acceptance Criteria
- [x] Splash stays until Flutter's first frame; shows an error and reload on failure
- [x] Content loads in one request instead of ~125 sequential fetches
- [x] Boot steps (Rust init, locale, content) run in parallel
- [x] Before/after numbers recorded in docs/research/web-load-performance.md

## Out of Scope
Font subsetting (Bravura 373 KB), renderer switch, service worker.

## Summary of Changes
Splash waits for first frame with failure/reload; content bundled into one request; parallel boot. Requests 142 to 16, last boot resource 7.3 s to 2.2 s (PR #61).
