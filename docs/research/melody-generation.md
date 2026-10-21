# Constrained melody generation

Checked: 2026-10-16, updated 2026-10-21. Bean: piano-ze9t. Status: partly superseded. The level rubric (D17, `core/src/rubric.rs`), similarity gate (PR #34), listening test (PR #33), Magenta spike (PR #39) and our own model (D20, PRs #41–#48) now exist; this page keeps the evaluation criteria and the rule-based option as a baseline.

Sources:
- Algorithmic composition basics: constraint programming, Markov models, genetic algorithms.
- Magenta / magenta.js: <https://magenta.withgoogle.com/>, <https://github.com/magenta/magenta-js> (code Apache-2.0).
- M(AI)DI / MusicLang: <https://maidi.readthedocs.io/en/latest/>, model card <https://huggingface.co/musiclang/musiclang-v2>. Code: [`MusicLang/maidi`](https://github.com/MusicLang/maidi) is Apache-2.0; [`MusicLang/musiclang_predict`](https://github.com/MusicLang/musiclang_predict) is GPL-3.0 (GitHub licence field, checked 2026-10-21). Model: "specific licenses, contact us" for product use (model card, not re-checked).
- Anticipatory Music Transformer (not checked yet).

No code or data was fetched for this doc. Licence cells come from project pages; only the MusicLang code licences and the Magenta code licence were confirmed via the GitHub licence field (2026-10-21). Treat the rest as unverified.

## Question

Can we generate drill and practice melodies that meet both of these?

- **Level-correct:** use only what the student has learned so far.
- **Pleasant:** singable and memorable.

They should also be deterministic for a given seed and be our own CC0 content.

## What "good" means (evaluation criteria)

| Criterion | Measure |
|---|---|
| Level-correct | 100% pass of `content lint` and the level check (pitches, range, fingers, rhythms, leaps, accidentals) |
| Playable | Fits the lesson's hand position; no finger crossings below the level that teaches them |
| Musical | Listen test: ≥ 7/10 samples rated "would practise this" by 2 listeners |
| Memorable | Motif recurs at least twice per 8 bars |
| Deterministic | Same `--level`, `--seed` → byte-identical JSON |
| Licensed | Output `license: CC0-1.0`, `source: original`; no third-party weights or data shipped |

## Options

| Approach | How | Pros | Cons |
|---|---|---|---|
| Constraint search (CSP) | Notes and rhythms are variables; the level rubric gives the hard constraints | Always valid; seedable; pure Rust | Dull without a musicality score |
| Markov / n-gram | Trained on PD folk tunes, filtered by the constraints | Sounds human; cheap | Clichés; needs a license-clean corpus |
| Genetic algorithm | Population, fitness, mutation | Optimises many soft goals | Slow; hard to tune |
| LLM + validator loop | The LLM writes our note tokens; `content lint` and the level check reject and retry | Creative; themable ("lullaby") | Non-deterministic; costs money; needs review |
| Neural music models | Conditioned sampling | High quality | Weight and data licenses must pass D6 |

## Tools checked

| Tool | What it does | License | Fit |
|---|---|---|---|
| **Magenta** (MusicVAE, MelodyRNN, ImprovRNN; magenta.js in the browser) | Sample, interpolate, continue melodies; ImprovRNN conditions on chords | Code Apache-2.0; checkpoints have **no stated licence** ([magenta-feasibility.md](magenta-feasibility.md)) | Plain sampling ignores hard constraints (0/600 valid), but masked sampling passes every rule (PR #39). Blocked for shipped content by the missing weight licence. The TensorFlow stack is ageing. |
| **M(AI)DI / MusicLang** | Generate ideas and control the chord progression; continue songs; transitions | `maidi` Apache-2.0, `musiclang_predict` GPL-3.0; model needs a separate licence for products | **Not for shipping.** Product use of the model requires contacting the authors (as with MuScriptor's CC BY-NC). It is a heavy Python model and won't run in the app. At most a local reference. |
| Anticipatory Music Transformer | Infilling under constraints | Not checked | Follow-up |

Takeaway: models are good at ideas and bad at rules. None replaces a rule-based generator.

## Proposed design: generate and score

1. **Harmony first.** Pick a simple progression (I–IV–V–I). Strong beats take chord tones. The same chords feed the `ACC` / `BASS` parts.
2. **Motif and form.** Build a one-bar motif into AABA or question/answer form. Vary it by transposition, inversion or a rhythm change.
3. **Hard constraints**, from the level rubric (`docs/research/song-import.md`):
   - allowed pitches and keys;
   - hand position and fingers;
   - rhythm values;
   - maximum leap;
   - accidentals;
   - range;
   - end on the tonic.
4. **Musicality score**, with weights tuned by listening:
   - arch contour;
   - mostly steps;
   - a leap is followed by a step back;
   - a cadence at phrase ends;
   - few repeated notes in a row;
   - controlled rhythmic variety;
   - motif recurrence.
5. **Search.** Seeded sampling or beam search over thousands of candidates; keep the top scores.
6. **Optional idea sources.** These feed motifs and themes only; the generator enforces every rule.
   - An LLM can propose a theme, title or seed motif.
   - Magenta can propose motifs, offline in `tools/`.

## Spike plan (when scheduled)

| Step | Output |
|---|---|
| 1. Machine-readable level rubric (shared with piano-1zn6) | **Done:** `core/src/rubric.rs`, `content/skill-specs/`, D17 |
| 2. `content generate --level N --seed S` (constraints only) | Valid but plain melodies |
| 3. Add harmony, motif and score | Ranked candidates |
| 4. Listen test: 10 samples per level 1–3, rule-based vs. Magenta vs. our model | Tools done: `tools/listening-test/` (PR #33), similarity gate `content-cli similar` (PR #34); ratings pending |
| 5. Proposed decision: generator role, LLM yes/no, Magenta yes/no | `docs/DECISIONS.md`; reconcile with D20 (own compound-token model, proposed), where the rule-based generator becomes the baseline and fallback |

## Fit

- Lives in Rust (`core` or `tools/content-cli`), pure and unit-tested. Output is our song JSON.
- Uses: endless "one more like this" drills, warm-ups, and variations of known songs.
- The official course stays hand-reviewed.

## Implications

- Needs the level rubric in machine-readable form.
- Generated parts reuse the companion and backing pipeline, so no new audio work is needed.
- No model weights ship. Any model use stays offline, and its output passes the same filter.

## Follow-ups

- piano-ze9t: steps 2–3 (rule-based baseline) and step 4 ratings are still open.
- Anticipatory Music Transformer licence: not checked.
- Magenta checkpoint terms: answered (none stated), see magenta-feasibility.md.
