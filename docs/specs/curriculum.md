# Curriculum

Status: draft. Mirrors Simply Piano's path shape ([teardown](../research/simply-piano-teardown.md)) with original content ([D6](../DECISIONS.md)).

## Structure

Course → Journey (graph of nodes) → Level → Stage.

| Node kind | Purpose |
|---|---|
| `lesson` | 3–8 levels teaching one skill |
| `song` | Reward song, practice sub-levels (RH, LH, both, slow, full) |
| `star_gate` | Song pack of 3–4 songs; pass by earning `stars_needed` stars across any of them (reference uses 2–7 stars, often ≈ two songs). Never locks: all nodes stay open until placement (OQ9) |
| `boss` / `mini_boss` | Review challenge of the course |
| `workout` | Generated daily review from pool levels |

## Course map

Full per-course skills, ranges and PD song picks: [course-map.md](course-map.md).

Same organization as Simply Piano (`DefaultCoursePaths`): touch section → basic section → main section split into two tracks. Course names are generic skill names; content is ours.

| Section | Course | Prereq | Focus |
|---|---|---|---|
| Touch | Touch Intro, Stay in Touch | none | On-screen keyboard, no piano needed |
| Basic | Piano Basics 1 | none | C position, treble staff, first songs |
| Basic | Piano Basics 2 | PB1 | Bass staff, hands together |
| Basic | Piano Basics 3 | PB2 | Eighth notes, G position, sharps/flats |
| Basic | Piano Basics 4 | PB3 | Position shifts, dynamics, first chords |

**Soloist track** (sheet music, sight reading, technique)

| Course | Prereq | Focus |
|---|---|---|
| Essentials I–III | PB4 | Reading fluency, rhythm, scales |
| Intermediate I–IV | Essentials III | Independence, key signatures, pedal |
| Classical I | Intermediate II | PD classical pieces |
| Taste of Bach I–II | Classical I | Counterpoint, two-voice |
| Pre-Advanced I–II | Intermediate IV | Longer pieces, ornaments |
| Advanced I | Pre-Advanced II + Taste of Bach II | Romantic pieces, ornaments, triplets against duplets |
| Showcase pieces (The Entertainer, Turkish March, Moonlight Sonata) | Intermediate II / Pre-Advanced I / Advanced I | Single-piece courses, PD only |

**Chords track** (accompaniment, pop/blues/jazz)

| Course | Prereq | Focus |
|---|---|---|
| Pop Chords I–III | PB4 | Triads, I-V-vi-IV, inversions |
| Chord Styling I–III | Pop Chords II | Broken chords, rhythms, LH patterns |
| Arpeggios I | Pop Chords II | Arpeggio patterns |
| Blues Chords I | Pop Chords III | 7th chords, 12-bar, swing |
| Jazz Chords I–II | Blues I | 7ths/9ths, ii-V-I |
| Lead Sheet I–III | Chord Styling II | Melody + chord symbols |
| Slash Chords | Lead Sheet I | Bass-note chords |

Map layout: 3-column grid (Soloist · shared · Chords), courses unlock by prereq. Built today: `courses.json` sections `basic`, `soloist`, `chords`, listed one after another on the Learn tab; the grid is not built yet. Song showcase courses use PD music only (licensed pop songs in SP are replaced with PD/original equivalents).

## Piano Basics 1 skills (first build target)

- [ ] How to sit, hand shape, finger numbers (animation)
- [ ] Find C; white-key landmarks (2 and 3 black-key groups)
- [ ] RH C-position C D E F G, fingers 1–5
- [ ] Quarter / half / whole notes, counting (animation + quiz)
- [ ] Treble staff reading C4–G4
- [ ] LH C-position, bass staff C3–G3
- [ ] Hands together, simple bass notes
- [ ] Songs (PD): Ode to Joy, Twinkle Twinkle, Jingle Bells, Mary Had a Little Lamb, Au Clair de la Lune
- [ ] Boss: Ode to Joy both hands

## Level template

1. `animation` introducing the skill (replaces video)
2. `wait` stages with `pre_listen`
3. `one_note` drill
4. `play_along` at 70% then 100%
5. `quiz` (theory) where relevant

## Authoring workflow

1. Pick skill from list; check Simply Piano reference for *sequencing* only.
2. Write level JSON + notation; run `content lint`.
3. Preview in app (`--content-dir`).
4. PR with bean id; reviewer plays it.
