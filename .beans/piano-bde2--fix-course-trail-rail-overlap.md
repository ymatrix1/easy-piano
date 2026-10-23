---
# piano-bde2
title: Fix course trail rail overlap
status: completed
type: bug
priority: normal
created_at: 2026-10-23T15:08:05Z
updated_at: 2026-10-23T15:25:03Z
---

Context: Blocked by: none. The Learn tab's outer course connector rail showed as a stray vertical stripe beside expanded course content, in addition to the inner node rail overlapping scaled markers.

Higher Goal: Keep course progress decoration clear and readable.

Acceptance Criteria:
- [x] The inner vertical connector is painted behind course node markers, including the yellow current marker and trophy icon.
- [x] The outer connector is hidden while a course is expanded and its submodule tiles are visible.
- [x] UI source formatting is clean.

Out of Scope: Redesigning the course map.

## Summary of Changes
- Rendered submodule rails behind node markers and hover scaling.
- Hid the outer course rail while its course is expanded.
- Documented the rendering behavior in the course-map spec.
- Verified Dart formatting and Flutter analysis.
