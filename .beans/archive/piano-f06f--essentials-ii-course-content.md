---
# piano-f06f
title: Essentials II course content
status: completed
type: task
priority: normal
created_at: 2026-10-16T19:25:10Z
updated_at: 2026-10-16T19:43:19Z
parent: piano-id7r
---


## Context
Child of piano-id7r. Blocked by: previous Essentials course.

## Higher Goal
Playable Essentials II course per docs/specs/course-map.md.

## Acceptance Criteria
- [x] courses.json entry ready, journey + levels + songs + strings (en, pt-BR)
- [x] Every song has full license fields; PD or original only
- [x] Play-along songs have ACC/DRUMS/BASS
- [x] content lint, cargo test (lessons_playable), flutter analyze/test pass
- [x] Web build shows course; a level plays

## Out of Scope
Engine/format changes; reference-size level count.

Scope: New RH note A4, new LH note A2/B2 below C, F position, shifting positions, two-hand coordination. Songs: Twinkle Twinkle, Oh! Susanna (PD).

## Summary of Changes

- `essentials-2` ready: 7 nodes / levels (`e2-01` … `e2-07`), boss = Twinkle both hands.
- Songs: 4 original drills (A4 reach, LH thumb to A3, F position, shifting) + Twinkle Twinkle, Oh! Susanna (PD, our arrangements) with ACC/DRUMS/BASS.
- Scenes: e2-reach-a, e2-f-position, e2-shifting. Strings en + pt-BR. pubspec lists the new folders.
- Musette in D / Swing Low not built (need D5 and more shifting); left for a later pass.
