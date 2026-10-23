---
# piano-gtgg
title: Add browser URL navigation and back support
status: completed
type: feature
priority: normal
created_at: 2026-10-23T18:45:25Z
updated_at: 2026-10-23T19:25:20Z
parent: piano-eeut
---

Context: Blocked by: none. The web app used Navigator pushes without reflecting destinations in the browser URL.

Higher Goal: Make Easy Piano web navigation compatible with direct links and browser back/forward.

Acceptance Criteria:
- [x] Main tabs update the URL and browser back/forward restore the selected tab.
- [x] Course-node task pages update the URL and open directly.
- [x] Lesson links update the URL, open directly, and preserve the selected stage.
- [x] Free play, endless practice, and developer tools have distinct URLs.
- [x] Navigation URL behavior is documented and covered by tests.

Out of Scope: Persisting learner progress.

## Summary of Changes
Added URL-reflecting GoRouter history for tabs and nested screens; direct routes for nodes, lessons, practice screens, and tools; navigation spec and browser URL tests.

UI repair: restored the arena backdrop and themed back control on the direct course-node task screen; added a regression assertion for its deep background.

Deep-link exit fix: lesson Exit now returns to the previous in-app route when available, and falls back to /learn when the lesson URL was opened directly.
