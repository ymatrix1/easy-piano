---
# piano-xa35
title: Review imported songs for dynamic and hairpin marks, then test in app
status: todo
type: task
created_at: 2026-10-24T19:39:13Z
updated_at: 2026-10-24T19:39:13Z
parent: piano-bjig
---

## Context
Dynamics and hairpins now render, grade and lint (piano-boat PR 1, piano-rdr4). No content song uses `{dyn}`, `{cresc}`, `{dim}` or `{end}` yet, so the feature has not been checked in the app. The imported Mikrokosmos pieces carry notes but no dynamic letters (piano-tpud, source decision open). Blocked by: piano-tpud source decision for the Mikrokosmos part; the rest can start now.

## Higher Goal
Decide which imported songs need expression marks, add them where they teach something, and test the dynamics feature in the app on real content.

## Acceptance Criteria
- [ ] Review the imported songs (content/songs) and list which ones need dynamic or hairpin marks for their lesson, and why.
- [ ] Pick one lesson (Piano Basics or Mikrokosmos) to carry the first marks as the in-app test case.
- [ ] Add the marks with `content lint` passing, and check them in the practice screen and on the staff.
- [ ] Record the in-app result (what renders, what grades) in the piano-boat bean.

## Out of Scope
- New dynamics lessons with animation scenes (piano-rdr4).
- Articulation, slurs and pedal (piano-gjig is scrapped; new bean if needed).

## Summary of Changes
*(To be completed upon finishing)*
