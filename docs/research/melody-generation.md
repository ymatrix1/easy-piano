# Constrained melody generation

Checked: 2026-10-16. Bean: piano-ze9t. Status: documented, not started.

Sources: general knowledge of algorithmic composition (constraint programming, Markov models, genetic algorithms), Magenta MusicVAE, Anticipatory Music Transformer; no code or data fetched yet.

## Question

Can we generate drill and practice melodies that are both **level-correct** (only what the student has learned) and **pleasant** (singable, memorable), deterministically, as our own CC0 content?

## Options

| Approach | How | Pros | Cons |
|---|---|---|---|
| Constraint search (CSP) | Notes/rhythms are variables; level rubric gives hard constraints | Always valid; seedable; pure Rust | Dull without a musicality score |
| Markov / n-gram | Trained on PD folk tunes, filtered by constraints | Sounds human; cheap | Clichés; needs a license-clean corpus |
| Genetic algorithm | Population + fitness + mutation | Optimises many soft goals | Slow, hard to tune |
| LLM + validator loop | LLM writes our note tokens; `content lint` + level check reject and retry | Creative, themable ("lullaby") | Non-deterministic; cost; needs review |
| Neural music models | Conditioned sampling (MusicVAE, AMT) | High quality | Weight/data licenses must pass D6 (cf. MuScriptor CC BY-NC) |

## Proposed design: generate and score

1. **Harmony first.** Pick a simple progression (I–IV–V–I); strong beats take chord tones. The same chords feed `ACC` / `BASS` parts.
2. **Motif and form.** One-bar motif, built into AABA or question/answer; variants by transposition, inversion, rhythm change.
3. **Hard constraints** (from the level rubric, `docs/research/song-import.md`): allowed pitches and keys, hand position and fingers, rhythm values, max leap, accidentals, range; end on the tonic.
4. **Musicality score:** arch contour; mostly steps; a leap is followed by a step back; cadence at phrase ends; few repeated notes in a row; controlled rhythmic variety; motif recurrence.
5. **Search:** seeded sampling or beam search over thousands of candidates; keep the top scores.
6. **LLM optional:** suggests theme, title and seed motif; the generator enforces rules.

## Fit

- Lives in Rust (`core` or `tools/content-cli generate`), pure and unit-tested; output is our song JSON, `license: CC0-1.0`, `source: original`.
- Uses: endless "one more like this" drills, warm-ups, variations of known songs. The official course stays hand-reviewed.

## Implications

- Needs the level rubric in machine-readable form (shared with song import's level arranger, piano-1zn6).
- Generated parts reuse the companion/backing pipeline, so no new audio work.

## Follow-ups

- piano-ze9t: prototype, listen tests, proposed decision.
