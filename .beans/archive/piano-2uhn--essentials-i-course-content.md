---
# piano-2uhn
title: Essentials I course content
status: completed
type: task
priority: normal
created_at: 2026-10-16T19:25:09Z
updated_at: 2026-10-16T19:37:22Z
parent: piano-id7r
---


## Context
Child of piano-id7r. Blocked by: none.

## Higher Goal
Playable Essentials I course per docs/specs/course-map.md.

## Acceptance Criteria
- [x] courses.json entry ready, journey + levels + songs + strings (en, pt-BR)
- [x] Every song has full license fields; PD or original only
- [x] Play-along songs have ACC/DRUMS/BASS
- [x] content lint, cargo test (lessons_playable), flutter analyze/test pass
- [x] Web build shows course; a level plays

## Out of Scope
Engine/format changes; reference-size level count.

Scope: Rhythm and rests, LH C position (C3-G3), hands together, RH intervals, eighth notes. Songs: When the Saints, Jingle Bells (PD, our arrangements).

## Summary of Changes

- `essentials-1` is ready in `courses.json`: 8 journey nodes, 8 levels (`e1-01` … `e1-08`), boss = When the Saints both hands.
- Songs: 5 original drills (rests, LH C position, hands together, intervals, eighths) + When the Saints, Jingle Bells (PD, our arrangements) with ACC/DRUMS/BASS.
- Scenes: e1-rests, e1-left-hand, e1-hands-together, e1-eighth-notes. Strings en + pt-BR.
- pubspec bundles the new asset folders; new app test fails if any content folder is missing from pubspec.
- lessons_playable grades both hands so LH-only drills are covered.
- Twinkle / Oh! Susanna need A4: moved to Essentials II (course-map updated).
