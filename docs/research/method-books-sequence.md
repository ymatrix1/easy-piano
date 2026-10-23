# Method-book concept order (intermediate to advanced)

Checked: 2026-10-22.
Sources: tables of contents of five adult all-in-one piano methods (Alfred Adult All-in-One Levels 1–3, Faber Adult Piano Adventures Books 1–2), local scans in git-ignored `references/`. Only the contents pages were read; no music, exercises or text were copied ([content rule](../../.agents/rules/content-and-licensing.md)).
Question: in what order do established methods introduce concepts after the beginner stage, so the Soloist and Chords courses follow a proven sequence?

## Merged order after Essentials III

Starting point (already taught): C, G, F positions, sharps and flats, C major scale, 3/4, eighth notes.

| # | Concept | Our course |
|---|---|---|
| 1 | Dotted quarter + eighth, pickups | Classical I |
| 2 | Primary chords I-IV-V7, inversions as voicings | Intermediate III, Pop Chords I, Lead Sheet I |
| 3 | Lead sheets: chord symbols, block then broken LH | Lead Sheet I–III |
| 4 | 12-bar blues, blues scale, swing eighths | Blues Chords I |
| 5 | G major scale and key signature, D7 | Intermediate II, IV |
| 6 | Syncopation, accents | Intermediate I, Showcase: The Entertainer |
| 7 | F major scale, primary chords in F | Pre-Advanced I, Pop Chords II |
| 8 | Thumb-under / finger-over crossings | Intermediate I |
| 9 | A minor natural and harmonic | Intermediate III |
| 10 | Triads from 3rds, inversions | Pop Chords III, Arpeggios I |
| 11 | I-vi-ii-V and minor progressions | Pop Chords II, Jazz Chords I |
| 12 | Alberti and waltz bass | Pre-Advanced II, Chord Styling III |
| 13 | Eighth-note triplets | Intermediate IV |
| 14 | Imitation, sequence, two-part writing | A Taste of Bach I |
| 15 | D minor, E minor | A Taste of Bach II |
| 16 | 6/8, 3/8, cut time | Intermediate IV |
| 17 | D major scale | Intermediate IV |
| 18 | Arpeggios one octave | Arpeggios I |
| 19 | Sixteenths, dotted eighth + sixteenth | Pre-Advanced I |
| 20 | Seventh chords, V7 inversions | Blues / Jazz Chords |
| 21 | B-flat major, G minor | Pre-Advanced I, A Taste of Bach II |
| 22 | Diminished / augmented, diminished 7th | Jazz Chords II |
| 23 | Scale degrees, circle of fifths | Pre-Advanced I |
| 24 | Ornaments, thirty-second notes | Advanced I |
| 25 | Capstones: Bach Prelude in C, Für Elise, Moonlight Sonata (1st mvt), Chopin Prelude in A, Canon in D | Arpeggios I, Pre-Advanced II, Showcase: Moonlight, Advanced I, Slash Chords |

## Public-domain pieces the methods place at these levels

Used only to pick which PD works fit a level (our arrangements are our own or based on PD Mutopia editions): Ode to Joy, New World Largo, Can-Can, The Entertainer, Brahms Lullaby, Morning Mood, Habanera, Hall of the Mountain King, Trumpet Voluntary, Musette in D, Für Elise, Moonlight Sonata, Bach Prelude in C, Pachelbel Canon, Chopin Prelude in A; traditional: Scarborough Fair, Shenandoah, Danny Boy, House of the Rising Sun, Frankie and Johnny, Aura Lee, Simple Gifts.

## Implications

- The Soloist and Chords course maps ([course-map.md](../specs/course-map.md)) match this order; two courses were added past the map so the path reaches the methods' capstones: Advanced I and Showcase: Moonlight Sonata.
- Pedal and dynamics appear early in all methods, but our notation has no pedal or dynamics yet, so courses skip them.

## Gaps after the first Soloist and Chords pass

| Method-book concept | Status in our courses | Blocker | Bean |
|---|---|---|---|
| Dynamics, crescendo/diminuendo | Missing | No notation | piano-boat |
| Staccato, legato/slurs, accents, tenuto, fermata | Missing | No notation | piano-boat |
| Damper pedal (simple, overlapping) | Missing | No notation, no playback | piano-boat |
| Ties | Worked around (restrike or longer value) | `{tie}` not graded as one note | piano-h90n |
| Repeats, 1st/2nd endings, D.C./D.S. al Fine/Coda | Written out in full | No notation | piano-h90n |
| Key or meter change inside a piece | Avoided (Spanish Romance major strain dropped) | One key/time per song | piano-h90n |
| Two voices in one hand | ACC substitute or simplified | One line per hand (spec in PR #74, D34) | piano-16vk, then piano-5zp3 |
| A, E, Eb, Ab major; B, F#, C#, C minor | Touched in passing only | Content | piano-0caa |
| Augmented triads, transposition | Missing | Content | piano-0caa |
| Scale degrees, interval and key-signature theory | Captions only, no quiz stages | Content | piano-0caa |

### How the gaps reach the courses

No course is rebuilt. Course, node and level ids stay (progress is keyed by them); each gap adds lessons and edits songs in place:

| Bean | Course change |
|---|---|
| piano-boat | New lesson nodes (Classical I, Intermediate I–II); existing songs gain marks, notes unchanged |
| piano-h90n | New lesson nodes (Intermediate II–IV); restruck notes become ties, written-out repeats become signs, Spanish Romance gets its major strain back |
| piano-5zp3 | New lesson node in A Taste of Bach I; ~8–10 pieces re-arranged with RH2/LH2 |
| piano-0caa | New nodes or a new course only |
| piano-bdi4 | Note fixes song by song |

Order: piano-boat and piano-h90n before the by-ear review (piano-bdi4), so each song is reviewed once with its final notation. New lessons go in as new journey nodes; inserting a node keeps learners' progress.

## Follow-ups

- The gap beans above.
- Musical review of every PD arrangement by ear before release (piano-bdi4).
