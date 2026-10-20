---
# piano-rrqj
title: Essentials III course content
status: completed
type: task
priority: normal
created_at: 2026-10-16T19:25:10Z
updated_at: 2026-10-16T19:49:52Z
parent: piano-id7r
---


## Context
Child of piano-id7r. Blocked by: previous Essentials course.

## Higher Goal
Playable Essentials III course per docs/specs/course-map.md.

## Acceptance Criteria
- [x] courses.json entry ready, journey + levels + songs + strings (en, pt-BR)
- [x] Every song has full license fields; PD or original only
- [x] Play-along songs have ACC/DRUMS/BASS
- [x] content lint, cargo test (lessons_playable), flutter analyze/test pass
- [x] Web build shows course; a level plays

## Out of Scope
Engine/format changes; reference-size level count.

Scope: Rhythm review, new LH position, sharps, flats, mixed accidentals, grand staff, C major scale. Songs: Minuet in G (Petzold), Amazing Grace, Greensleeves (PD).

## Summary of Changes

- `essentials-3` ready: 9 nodes / levels (`e3-01` … `e3-09`), boss = Minuet in G both hands. All three Essentials are now ready; no planned courses remain in `courses.json`.
- Songs: 5 original drills (3/4 waltz with dotted notes, LH G position, F♯, B♭, C major scale with thumb under) + Minuet in G (Petzold), Amazing Grace (LH B♭), Greensleeves (G♯ and F♯), PD, our simplified arrangements, ACC/DRUMS/BASS.
- Scenes: e3-three-four, e3-lh-g-position, e3-sharps, e3-flats, e3-thumb-under. Strings en + pt-BR.
- Found: companion hand not drawn on the staff in single-hand stages; new bean filed.

### Expansion (2026-10-19)
- 17 levels in 13 nodes. New PD songs: Auld Lang Syne, Joy to the World (descending scale with thumb-over fingering).
- Song packs: gate-1 (Minuet, Amazing Grace, Auld Lang Syne; 6 stars), gate-2 (Joy to the World, Greensleeves both hands, faster scale; 6 stars).
