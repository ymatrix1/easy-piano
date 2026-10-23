---
# piano-bde2
title: Fix course trail rail overlap
status: completed
type: bug
priority: normal
created_at: 2026-10-23T15:08:05Z
updated_at: 2026-10-23T15:10:12Z
---

Context: Blocked by: none. The Learn course-map connector line was painting over the lower edge of animated node markers, visibly crossing the yellow current marker and trophy overlay.

Higher Goal: Keep course progress decoration clear and readable.

Acceptance Criteria:
- [x] The vertical connector is painted behind course node markers, including the yellow current marker and trophy icon.
- [x] The same rendering works for normal and hovered/animated markers.
- [x] UI source formatting is clean.

Out of Scope: Redesigning the course map.

## Summary of Changes
- Reordered the Learn tab node rendering so connector rails paint behind the node marker and its hover scale.
- Documented the rail and marker layering in the course-map spec.
- Verified Dart formatting and Flutter analysis.
