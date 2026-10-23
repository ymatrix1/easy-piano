---
# piano-5zp3
title: Re-arrange two-voice pieces with RH2/LH2 (after piano-16vk)
status: todo
type: task
priority: normal
created_at: 2026-10-22T19:29:41Z
updated_at: 2026-10-22T19:31:23Z
parent: piano-bjig
---

## Context
PR #74 specs two voices per hand (RH2/LH2, spacer s:, D34 proposed); implementation bean piano-16vk. First-pass courses (piano-wo7k) worked around one line per hand: Moonlight Sonata gives melody or triplets to ungraded ACC passage by passage, Prelude in C restrikes the held inner voice, Ave Maria and Canon reduce arpeggios, Advanced I nocturne-style pieces simplify. Blocked by: piano-16vk (two voices per hand implementation).

## Higher Goal
Real two-voice right hand in the advanced courses.

## Acceptance Criteria
- [ ] Moonlight Sonata (scm parts + whole): RH melody in RH2 over RH triplets, no ACC substitute
- [ ] Prelude in C BWV 846: held inner voice in LH2/RH2
- [ ] Advanced I pieces (nocturne, Liebestraum, Chopin preludes) reviewed for second voices
- [ ] Ave Maria, Canon in D, Bach II suspensions reviewed
- [ ] content lint ok; course-map known limits updated
- [ ] Teaching lesson on reading two voices in one hand (stems up/down, holding one voice while the other moves): scene + drills in A Taste of Bach I before the re-arranged pieces

## Out of Scope
- Implementing RH2/LH2 (piano-16vk)
