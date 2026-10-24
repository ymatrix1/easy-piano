# Course map

Status: draft. Bean: piano-673h. Shape follows Simply Piano's course paths ([teardown](../research/simply-piano-teardown.md)); skills are written in our own words and every song is public domain or our own ([D6](../DECISIONS.md)).

Reference numbers below (nodes, levels, stage mix, ranges) come from a local scan of the reference app's course structure, recorded only as statistics. No reference content is copied.

## Layout

```
Touch Intro ─► Piano Basics ─► Essentials I ─► Essentials II ─► Essentials III ─┬─► SOLOIST track
                                                                               └─► CHORDS track
```

Each course: 10–25 journey nodes, 30–60 levels, a boss at the end. Typical stage mix in the reference: ~80% wait (`note_sequence`), 10–25% play-along (`moving`), 2–6% teaching (video, replaced by our animation scenes), small share of single-note drills. Later courses raise the play-along share (Bach, Jazz ≈ 25–30%).

In the Learn tab, journey connector rails sit behind their node markers and stop at the marker bounds, including while a marker scales on hover. Inner trail hover washes are clipped to the trail panel so they cannot paint over its chamfered edge.

## Basic section

| Course | Prereq | Skills | RH / LH range | bpm | PD songs (ours) |
|---|---|---|---|---|---|
| **Touch Intro** | none | On-screen keys, find C, play along by tapping | C4–G4 / – | 60–90 | Ode to Joy (tap) |
| **Piano Basics** | none | Sitting and hand shape, finger numbers, RH C position (C–G), first staff reading, quarter/half notes | C4–G4 / – | 60–120 | Ode to Joy, Symphony No. 40 theme (Mozart), Mary Had a Little Lamb |
| **Essentials I** | Piano Basics | Rhythm (quarter, half, whole, rests), reading notes on treble, LH basic chords and new notes (C3–G3), both hands, RH intervals, coordination, eighth notes | C4–G4 / C3–G3 | 72–104 | When the Saints, Jingle Bells (Twinkle Twinkle and Oh! Susanna need A4: moved to Essentials II) |
| **Essentials II** | Essentials I | New RH note above G, new LH note, RH F position, shifting positions, coordination in two hands | C4–C5 / C3–A3 | 76–100 | Twinkle Twinkle, Oh! Susanna (Musette in D and Swing Low later; Saints moved to Essentials I) |
| **Essentials III** | Essentials II | Rhythm review, new LH position, sharps, flats, mixed accidentals, intro to full sheet music, C major scale | C4–E5 / G2–D3 | 76–100 | Minuet in G (Petzold, attr. Bach), Greensleeves, Amazing Grace, Auld Lang Syne, Joy to the World |

## Soloist track (sheet music, sight reading, technique)

| Course | Prereq | Skills | RH / LH range | PD songs (ours) |
|---|---|---|---|---|
| **Classical I** | Essentials III | Music periods (Baroque, Classical, Romantic), training-then-piece levels | C4–C#5 / G#2–C#4 | Spring (Vivaldi), Minuet (Bach), Sonata K.331 theme (Mozart), New World Largo (Dvořák), Zarathustra fanfare (Strauss) |
| **Intermediate I** | Classical I | Rhythm, new thumb technique (thumb under), syncopation intro, D position | C4–D#5 / C#3–D#4 | Can-Can (Offenbach), Habanera (Bizet), Morning Mood (Grieg) |
| **Intermediate II** | Intermediate I | Ties, switching positions, extending C position | C4–D#5 / C#3–D#4 | Hall of the Mountain King, Turkey in the Straw |
| **Intermediate III** | Intermediate I | Five-finger coordination, extending F and D positions, coordination in scales | C4–D#5 / C#3–C#4 | Maple Leaf Rag (Joplin, simplified), Scarborough Fair |
| **Intermediate IV** | Intermediate II + III | G position, shifting from G, D and G major scales, high C position, shifting positions | C4–A#5 / A#2–G#4 | Joy to the World, Minuet in G, Simple Gifts |
| **Taste of Bach I** | Intermediate IV | Bach intro, two-round training per piece | C4–G#5 / F2–D#4 | Minuet in G major, Arioso (Cantata 156) |
| **Taste of Bach II** | Taste of Bach I | Minor-key Bach, longer phrases | D#4–A#5 / A#2–D#4 | Minuet in G minor, Air on the G String |
| **Pre-Advanced I** | Intermediate IV | Key signatures (D major, F major), sixteenth notes, theory moments, F major scale | A#3–G#5 / A#2–G#4 | Hallelujah chorus (Handel, simplified), Boléro theme (Ravel*), Ode to Joy in D |
| **Pre-Advanced II** | Pre-Advanced I | LH technique: triads, oom-pah, Alberti bass | C4–G#5 / C3–D#4 | Sonata facile K.545 (Mozart), Für Elise (A section) |
| **Advanced I** | Pre-Advanced II + Taste of Bach II | Romantic pieces: repeated LH chords, wide LH broken chords, triplets against duplets, written-out ornaments, chromatic scale, nocturne style | C4–C6 / F1–E4 | Gymnopédie No. 1 (Satie), Preludes Op. 28 Nos. 4 and 7 (Chopin), Liebestraum No. 3 (Liszt), Nocturne Op. 9 No. 2 (Chopin) |
| **Showcase: The Entertainer** | Intermediate II | Part A/B training, connecting parts, whole piece, performance tips | G#3–C#6 / C#2–C4 | The Entertainer (Joplin) |
| **Showcase: Turkish March** | Pre-Advanced I | Parts A/B/C, connecting, whole piece | G#4–C#6 / A#2–F4 | Rondo alla Turca (Mozart) |
| **Showcase: Moonlight Sonata** | Advanced I | RH triplets, LH octaves, melody on top, parts then whole first movement | E3–G#5 / B1–C#4 | Sonata Op. 27 No. 2, 1st mvt (Beethoven) |

Built versions differ from the plan above where noted: Boléro (Ravel, not PD everywhere) is replaced by Toreador Song, La donna è mobile and Pomp and Circumstance; The Entertainer needs Intermediate II (syncopation) instead of Essentials III; Advanced I and Showcase: Moonlight Sonata were added so the path reaches the capstones of adult methods ([method-books-sequence](../research/method-books-sequence.md)).

## Chords track (accompaniment, pop, blues, jazz)

All chord courses use PD melodies (folk, hymns, early jazz/blues standards whose composers died > 70 years ago) or our own originals written to show the progression.

| Course | Prereq | Skills | Songs (ours / PD) |
|---|---|---|---|
| **Pop Chords I** | Essentials III | C, G, D, Em chords; adding LH bass; chords + bass practice; I–V–vi–IV; reading chord symbols with lyrics | Original "Four Chords" études, Oh When the Saints |
| **Chord Styling I** | Pop Chords I | Styling patterns, A minor, same song in different styles | Originals, House of the Rising Sun (trad.) |
| **Pop Chords II** | Chord Styling I | F major, D minor | Originals, Auld Lang Syne |
| **Chord Styling II** | Pop Chords II | Rock pattern, ballad pattern | Originals, Danny Boy (trad.) |
| **Chord Styling III** | Chord Styling II | Alternating bass, ballad style, mixing styles | Originals, Shenandoah |
| **Pop Chords III** | Chord Styling III | E major, A major, B minor | Originals, Wayfaring Stranger |
| **Arpeggios I** | Pop Chords II | RH inversions, upward arpeggio, up-and-down, maj7 arpeggio, LH intervals | Originals, Prelude in C (Bach, BWV 846) |
| **Blues Chords I** | Pop Chords III | G7, C7, D7; swing feel; 12-bar blues; adding bass; rock and roll pattern | Originals, Frankie and Johnny (trad.) |
| **Jazz Chords I** | Blues Chords I | Dm7, Cmaj7, Am7; ii–V–I; jazz comping pattern; turnaround | Originals on standard changes, Bill Bailey (1902) |
| **Jazz Chords II** | Jazz Chords I | More 7th chords, diminished, minor ii–V–i, jazz waltz | Originals, Maple Leaf Rag changes |
| **Lead Sheet I** | Essentials III | LH chords from symbols (C, F, G, Am), melody + chords | Originals, Home on the Range |
| **Lead Sheet II** | Lead Sheet I | D, Em, Dm chords | Originals, Red River Valley |
| **Lead Sheet III** | Lead Sheet II | A, Bm chords | Originals, Camptown Races |
| **Slash Chords** | Jazz Chords II | Pedal bass, moving bass, inversions as slash chords | Originals, Canon in D (Pachelbel) bass line |

## Music Theory (later)

Planned, not built (bean piano-6gpx). A shared course open to both tracks after Essentials III, mostly `quiz` stages plus short play-back drills:

| Node group | Skills |
|---|---|
| Intervals | Name and build 2nds to octaves, major/minor/perfect, by sight and by ear |
| Scales and keys | Major and minor scales, scale degrees (tonic … leading tone), key signatures, circle of fifths |
| Chords | Triad qualities (major, minor, diminished, augmented), 7th chords, inversions, Roman numerals |
| Harmony | Cadences (authentic, plagal, half), common progressions, transposition |
| Rhythm and form | Time signatures, tuplets, phrase, binary/ternary/rondo form |

Needs new quiz types (name the interval, key signature, chord quality, ear training) in [exercise-engine](exercise-engine.md). Keys and augmented triads in playing lessons are bean piano-0caa.

## Profile variants

Accepted in [D12](../DECISIONS.md). The reference app ships the same skill path in several variants: of 48 courses, 10 are Kids versions, plus locale (JP), licensed-character and difficulty-fix variants; Piano Basics 1 alone has 8. We formalize this as a fixed skill backbone with swappable content.

**Backbone (fixed per module):** the ordered list of skills, their journey nodes and their pass rules. Progress, stars and unlocks are keyed by skill node, so switching variant never loses progress.

**Variant axes (swappable content):**

| Axis | Values | What changes |
|---|---|---|
| Audience | `kids` (≈ 6–11), `teen_adult` | Kids: shorter levels (≤ 3 min), more scenes and mascot, fewer words, larger UI, no streak pressure, parent gate for settings. Adult: direct tone, theory moments, longer play-alongs |
| Taste | `classical`, `folk_world`, `jazz_blues`, `hymns_spirituals`, `originals_pop` | Song picks per node: each node lists 2–4 PD/original songs that train the same skill; the profile picks one |
| Locale | any | Strings, scene captions, and folk songs from that culture where PD (e.g. Brazilian *cantigas de roda* for pt-BR) |

**Resolution:** `variant = backbone node + audience overrides + taste song choice + locale strings`. A node declares defaults; variants only override. Authors add a taste by filling song slots, not by forking a course.

**Onboarding:** asks age band and up to two favourite styles; the user can change both in settings at any time.

Example, Piano Basics node "RH C position, first song":

| Taste | Song slot (PD) |
|---|---|
| classical | Ode to Joy (Beethoven) |
| folk_world | Au Clair de la Lune / Ciranda Cirandinha (pt-BR) |
| jazz_blues | Original 5-note blues riff étude |
| hymns_spirituals | Amazing Grace (first phrase, simplified) |
| originals_pop | Original "First Steps" pop étude |

## Built (playable)

| Course | Levels | Nodes | Songs | Scenes | Bean |
|---|---|---|---|---|---|
| Essentials I | 19 in 12 nodes | rests, intervals, lightly-row, left-hand (+ first LH chords), saints, gate-1, hands-together, eighths, jingle, gate-2, boss | 7 original drills + When the Saints, Jingle Bells, Lightly Row, Go Tell Aunt Rhody, Au Clair de la Lune (PD, our arrangements, ACC/DRUMS/BASS). 2 star gates of 3 songs, `stars_needed: 5` | e1-rests, e1-left-hand, e1-hands-together, e1-eighth-notes | piano-2uhn |
| Essentials II | 18 in 12 nodes | new-note-a, twinkle, london-bridge, left-hand-a, frere-jacques, gate-1, f-position (+ waltz), shifting, susanna, camptown, gate-2, boss | 5 original drills + Twinkle, London Bridge, Frère Jacques, Oh! Susanna, Camptown Races (PD, our arrangements, ACC/DRUMS/BASS). Gates: 3 songs / 5 stars, 4 songs / 7 stars | e2-reach-a, e2-f-position, e2-shifting | piano-f06f |
| Essentials III | 17 in 13 nodes | waltz, left-hand-g, sharps, minuet, flats, amazing-grace, auld-lang-syne, gate-1, greensleeves, scale, joy-to-the-world, gate-2, boss | 5 original drills (3/4, LH G position, F♯, B♭, C major scale) + Minuet in G, Amazing Grace, Auld Lang Syne, Greensleeves, Joy to the World (PD, our simplified arrangements, ACC/DRUMS/BASS). Gates: 3 songs / 6 stars each | e3-three-four, e3-lh-g-position, e3-sharps, e3-flats, e3-thumb-under | piano-rrqj |

Soloist and Chords tracks (bean piano-wo7k). Each course has 12–15 nodes, 16–19 levels, 3–5 scenes, two star gates of 3 songs (`stars_needed` 6, Chord Styling III gate 2: 7) and a boss. PD pieces are our own simplified arrangements; (M) marks those based on a public-domain or CC-BY-SA Mutopia edition (`source: mutopia`, `source_url` in the song).

| Course | Levels | PD pieces (plus original drills and études) |
|---|---|---|
| Classical I | 18 in 14 | Spring, Surprise Symphony, Eine kleine Nachtmusik, New World Largo, K.331 theme |
| Intermediate I | 18 in 13 | Can-Can, Habanera, Morning Mood, Skaters' Waltz |
| Intermediate II | 17 in 13 | Hall of the Mountain King, Turkey in the Straw, William Tell Overture |
| Intermediate III | 18 in 12 | Scarborough Fair, Brahms' Lullaby, O Sole Mio, Maple Leaf Rag A strain (M) |
| Intermediate IV | 16 in 12 | Simple Gifts, Musette in D, Trumpet Voluntary, Barcarolle |
| A Taste of Bach I | 17 in 13 | Minuet in G (two voices), March in D, Arioso, Jesu Joy of Man's Desiring |
| A Taste of Bach II | 17 in 13 | Minuet in G minor, Air on the G String, Polonaise in G minor, Bourrée in E minor |
| Pre-Advanced I | 18 in 14 | Hallelujah Chorus, Ode to Joy in D, La donna è mobile, Toreador Song, Pomp and Circumstance |
| Pre-Advanced II | 19 in 15 | Sonata facile K.545 (M), Sonatina Op. 36 No. 1 (M), Waltz Op. 39 No. 15 (M), Für Elise (M) |
| Advanced I | 18 in 14 | Gymnopédie No. 1 (M), Chopin Preludes Op. 28 Nos. 4 and 7 (M), Liebestraum No. 3, Nocturne Op. 9 No. 2 abridged (M) |
| Showcase: The Entertainer | 18 in 14 | The Entertainer, intro and parts A–D, then whole (M) |
| Showcase: Turkish March | 16 in 12 | Rondo alla Turca, parts A–C and runs, then whole (M) |
| Showcase: Moonlight Sonata | 16 in 12 | Sonata Op. 27 No. 2, 1st mvt, three parts then whole (M) |
| Pop Chords I | 18 in 14 | Kumbaya, Michael Row the Boat Ashore, He's Got the Whole World, When the Saints |
| Chord Styling I | 19 in 13 | Lavender's Blue, Drunken Sailor, House of the Rising Sun (two styles) |
| Pop Chords II | 17 in 13 | Aura Lee, Down in the Valley, Silent Night |
| Chord Styling II | 17 in 13 | Sloop John B, Swing Low Sweet Chariot, Danny Boy |
| Chord Styling III | 17 in 13 | Shenandoah (two styles), Clementine, Streets of Laredo |
| Pop Chords III | 19 in 15 | Loch Lomond, Wayfaring Stranger, The Water Is Wide |
| Arpeggios I | 19 in 15 | Prelude in C BWV 846 (M), Spanish Romance (M) |
| Blues Chords I | 17 in 13 | Frankie and Johnny, Careless Love, Joshua Fit the Battle |
| Jazz Chords I | 18 in 14 | Down by the Riverside, Bill Bailey, When the Saints |
| Jazz Chords II | 17 in 13 | St. James Infirmary, Hard Times Come Again No More (M), After the Ball |
| Lead Sheet I | 17 in 13 | Yankee Doodle, This Old Man, Home on the Range, Oh! Susanna, When the Saints |
| Lead Sheet II | 17 in 13 | Polly Wolly Doodle, Buffalo Gals, Red River Valley |
| Lead Sheet III | 19 in 15 | Skip to My Lou, Oh Dear What Can the Matter Be, Beautiful Dreamer |
| Slash Chords | 16 in 12 | Canon in D, Ave Maria (Bach/Gounod) (M) |

Known limits of this first pass: melodies not based on Mutopia were written from memory or checked against public transcriptions and need a by-ear review; the notation has one rhythm per hand, no ties, pedal or dynamics, so two-voice textures (Moonlight Sonata melody over triplets, the nocturne) give one layer to the app (`ACC`) passage by passage; content levels of most songs (3–7) sit below the intended 6–9 for late courses because the difficulty model's course ramp stops at 6. Gaps vs Alfred/Faber and their beans: [method-books-sequence](../research/method-books-sequence.md#gaps-after-the-first-soloist-and-chords-pass).

Reference shape (local scan, stats only): Essentials I 25 nodes / 50 levels with 9 song nodes and 5 star gates (3–4 songs each, 2–5 stars needed); Essentials II 14 / 41, 2 gates (7 stars of 4 songs); Essentials III 19 / 55, 3 gates (5–6 stars). Ours is smaller and grows by adding songs to gates. No accidentals yet in Essentials I and II; F position avoids B♭ until Essentials III (beginner rubric in [song-import.md](../research/song-import.md)).

## Build order

1. Piano Basics (Phase 2, ~25 levels)
2. Essentials I–III (Phase 4)
3. Soloist and Chords tracks, all courses (first pass, piano-wo7k)
4. Touch Intro; review and deepen arrangements once the notation has multiple voices per hand

## Open points

- Exact PD status per country for 20th-century composers (Ravel; Handy is US-PD but not life+70). Joplin (d. 1917), Satie (d. 1925), Elgar (d. 1934) are fine.
- Original "étude" songs for chord courses need a composer/arranger contributor flow.
