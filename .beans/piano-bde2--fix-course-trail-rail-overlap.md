---
# piano-bde2
title: Fix course trail rail overlap
status: completed
type: bug
priority: normal
created_at: 2026-10-23T15:08:05Z
updated_at: 2026-10-23T18:47:45Z
---

Context: Blocked by: none. The Learn tab's outer course connector rail showed as a stray vertical stripe beside expanded or hovered course content. The inner node rail could also paint above a scaled marker.

Higher Goal: Keep course progress decoration clear and readable.

Acceptance Criteria:
- [x] The inner connector paints behind course node markers, including the yellow current marker and trophy icon.
- [x] The outer course connector is hidden while its course is expanded and clears the next card bottom-left chamfer during hover lift.
- [x] UI source formatting is clean.

Out of Scope: Redesigning the course map.

## Summary of Changes
- Rendered submodule rails behind node markers and hover scaling.
- Hid the outer course rail while its course is expanded or hovered.
- Documented the rendering behavior in the course-map spec.
- Verified Dart formatting and Flutter analysis.
