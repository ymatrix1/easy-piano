---
# piano-wo7k
title: 'Soloist and Chords tracks: 27 courses up to advanced'
status: completed
type: task
priority: normal
created_at: 2026-10-22T19:09:42Z
updated_at: 2026-10-22T19:40:30Z
parent: piano-bjig
---

## Context
Essentials I-III are playable; the course map (docs/specs/course-map.md) plans a Soloist track and a Chords track after them. User asked to complete every course module up to the most advanced, using the local method-book references for concept order only. Blocked by: none.

## Higher Goal
A full learning path from first notes to advanced pieces (Moonlight Sonata, Rondo alla Turca, Canon in D) with clean-room content.

## Acceptance Criteria
- [x] 13 Soloist courses playable (Classical I, Intermediate I-IV, Bach I-II, Pre-Advanced I-II, Advanced I, three showcase courses)
- [x] 14 Chords courses playable (Pop Chords I-III, Chord Styling I-III, Arpeggios I, Blues I, Jazz I-II, Lead Sheet I-III, Slash Chords)
- [x] Every song has license fields; PD compositions only, own arrangements or PD/CC Mutopia editions
- [x] Strings in en, pt-BR, es, fr, de
- [x] content lint ok; app content tests pass
- [x] course-map, curriculum, ROADMAP updated; research note on concept order

## Out of Scope
- Touch Intro course
- Pedal, dynamics, ties, key-signature rendering in notation/app
- Recalibrating the difficulty model for levels above 6

## Summary of Changes

- 27 courses playable: 13 Soloist (Classical I, Intermediate I-IV, A Taste of Bach I-II, Pre-Advanced I-II, Advanced I, showcases The Entertainer, Turkish March, Moonlight Sonata) and 14 Chords (Pop Chords I-III, Chord Styling I-III, Arpeggios I, Blues Chords I, Jazz Chords I-II, Lead Sheet I-III, Slash Chords): 473 levels, 311 new songs, 135 scenes, strings in 5 locales.
- courses.json sections basic / soloist / chords; pubspec bundles new course folders; app test covers every ready course; Learn tab caps the module entrance stagger.
- PD pieces are our own arrangements; 13 are based on Mutopia PD / CC-BY-SA editions (`source: mutopia`).
- Docs: course-map built table and known limits, curriculum, ROADMAP, content-format (`source: mutopia`), OPEN-QUESTIONS OQ12-13, research note on method-book concept order and gaps.
- Follow-ups: piano-bdi4 (by-ear review), piano-5zp3 (RH2/LH2 re-arrangement), piano-boat, piano-h90n, piano-0caa, piano-6gpx, piano-j1jn.
