# Song difficulty (level evaluator)

Status: proposed ([D26](../DECISIONS.md)). Code: `core/src/difficulty.rs`, `tools/content-cli/src/level.rs` (`content level`, lint warning), `tools/difficulty/calibrate.py`. Weights: `core/data/difficulty-weights.json`. Beans: epic piano-7m8d.

How hard is a song, why, and which journey node fits it. Users: melody-model labels and generated-tune checks, personal song import (D11), placement (OQ9), authors (lint).

## Pipeline

| Step | What | Where |
|---|---|---|
| Features | measurements per hand and per bar, graded hands (`RH`, `LH`) only | `features` |
| Skills | 8 scores in 0..1, each a weighted mean of capped features | `skills` |
| Level | cumulative-logit ordinal model, non-negative weights | `Model` |
| Node fit | earliest node whose taught set the song fits, by the rubric | `node_fit` |
| Exceeds | rubric taught-set violations + skills above the node's envelope | `exceeds` |

## Features and skills

`x/cap` is clamped to 0..1. `*_per_bar` divides by the bar count, never by the note count, so adding notes never lowers a feature. Melodic line: RH top note, LH bottom note (as the rubric).

| Skill | Component (weight, cap) |
|---|---|
| reading | widest range of one hand, semitones (2, 24); distinct pitches (1, 20); ledger-line notes per bar, RH outside E4-F5 staff ±1, LH outside G2-A3 ±1 (0.5, 4); clef crossings per bar, RH below C4 or LH above C4 (1, 1) |
| hand_position | fewest moves out of a 5-finger window (7 semitones, C-G) per bar (2, 1); widest chord (1, 12) |
| intervals | skips (3-4 semitones) per bar (1, 4); leaps (5+) per bar (1, 2); largest leap (1, 12) |
| rhythm | fastest note: quarter 0, eighth 0.5, sixteenth 1 (3); distinct values - 1 (1, 5); dotted per bar (1, 1); syncopations per bar, off-beat onset sounding across the next beat (1, 1); ties per bar (0.5, 1); rests per bar (0.5, 1); tuplets per bar, non power-of-two lengths (1, 1) |
| key | sharps/flats in the signature, from a table of written keys (C-C#, F-Cb majors; A-A#, D-Ab minors); unknown keys read as C and add a `key: unknown key` reason (1, 4); notes outside the key per bar, minor allows the raised 7th (2, 1); black keys per bar (1, 2) |
| coordination | second hand used (1, 1); onsets with both hands per bar (1, 2); moments where either hand starts a note per bar (1, 8); LH notes per bar, the LH pattern's density (1, 4); LH distinct values (1, 3) |
| texture | most notes at once - 1 (1, 3); chords per bar (1, 2); hands with chords (1, 2) |
| speed | onsets per second (2, 4); busiest bar (1, 6). `bpm` counts the meter's beat unit (the denominator note), as the session engine plays it: 6/8 at 120 = 120 eighths a minute, 2/2 at 60 = 60 halves |

`unique_bars` (distinct bars, repeats compressed) is reported but **not scored**: adding a note can make two bars equal and lower it. Coordination counts union onsets rather than "LH onsets without RH", which an added RH note could lower (regression test `an_rh_note_on_an_lh_onset_never_lowers_coordination`).

Hand-position shifts are counted greedily, which is optimal for "fewest segments of span ≤ 7", so an added note can never lower it.

## Level model

`z = Σ w_k · skill_k` with `w_k ≥ 0.25` (every skill counts). `P(level > j) = σ(z − θ_j)` for 9 ascending thresholds. `level_score = 1 + Σ_j σ(z − θ_j)` (expected level, 1..10), `level = round(level_score)`. Non-decreasing in `z`, so in every skill and every feature.

Weights JSON: `weights` (8, `SKILLS` order), `thresholds` (9, ascending), `course_levels` (expected level at the first and last course node), plus a `fit` block with the calibration metrics. `Model::from_json` rejects negative weights and unordered thresholds; core embeds the file (`Model::builtin`).

## Calibration (`tools/difficulty/calibrate.py`)

Skills come from `content level --course` / `--jsonl`, never re-implemented in Python.

| Signal | Use | Weight |
|---|---|---|
| Course anchors | each course song (first node it appears at) gets `course_levels[0] + (course_levels[1] − course_levels[0]) · node_index / (nodes − 1)`, ordinal NLL | 1 per song |
| Course order | pairwise logistic: song at a later node scores higher | 2 / songs per pair |
| Node envelopes | elementwise max of skills up to each node, at that node's level | 0.3 |
| Simplified variants | RH only, chords → top note: original scores higher | 1 per pair |
| PDMX `complexity` 0/1/2/3 → level 3/5/7/9 | ordinal NLL, only if `data/melody/raw/pdmx/PDMX.csv` and `data/melody/dataset/tunes.jsonl` exist locally (git-ignored) | 0.3 × course total |

Regularisation pulls weights toward 1 and threshold gaps toward 0.6 (levels above the course have little data). The fit starts from fixed prior weights, not the previous file.

Evaluation (all in the weights file's `fit` block, with command, seed, row counts and the SHA-256 of `tunes.jsonl` and `PDMX.csv`):

| Check | Meaning |
|---|---|
| `kendall_tau_cv` | 5-fold cross-validation: each song scored by a model that never saw its anchor, pairs, envelope contribution or simplified pair. τ vs node index, 95% bootstrap CI over songs (2000 resamples) |
| `baselines` | same τ for skill sums that never saw course order (uniform sum, speed only, reading only) |
| `kendall_tau_fitted` | in-sample, for reference only |
| `simplified_easier_cv` / `_fitted` | strict `>`: ties fail |
| `pdmx.spearman_course_only` | model fitted without PDMX, scored against PDMX complexity: the only check on labels the fit never used |

Course τ is circular (the fit uses node order); read it with the baselines and the PDMX check. PDMX tunes are only scored, never committed; only the fitted numbers are.

**Assumption, proposed (D26):** the expected level ramps linearly from `course_levels[0]` at the first course node to `course_levels[1]` (1 → 6) at the last. It sets the anchors and the lint yardstick; it is not fitted and needs the user's sign-off.

Run: `python tools/difficulty/calibrate.py [--data <melody data dir>] [--dry-run]`. Current metrics are in the weights file's `fit` block.

## Output (`content level <content_dir> [--node c/n] [song.json ...]`)

```json
[{ "id": "twinkle-twinkle", "level": 4, "level_score": 4.1, "node_fit": "essentials-1/left-hand",
   "skills": { "reading": 0.28, "...": 0 }, "features": { "range": 9, "...": 0 },
   "hardest_bars": [{ "bar": 9, "level_score": 4.4 }],
   "reasons": ["coordination: both hands: 2.0 together and 0.5 independent left-hand notes per bar"],
   "node": "essentials-1/rests", "exceeds": ["RH: pitches not taught: A4", "texture 0.30 above node's 0.00"] }]
```

- `node_fit`: earliest node (learning order) where `rubric::taught_violations` is empty. Taught sets only grow, so every later node fits too; `null` = beyond the course. Same function as the rubric, so the two never disagree.
- `hardest_bars`: up to 3, each bar scored as a one-bar song.
- `reasons`: up to 3 skills with the largest `w · skill` (skill ≥ 0.25), in words.
- `--course`: every course song with node, expected level, skills. `--jsonl <file>`: one line per tune row (`bars`, `time`, `key`, optional `bpm`; missing metadata filled in). The row's own license is kept and echoed with `license_checked: false`: license and provenance rules are skipped because dataset rows are scored, never published.

## Lint

`content lint` warns (never errors) when a course song's level differs from its node's expected level (the linear ramp above, proposed) by more than 2.5. Today this warns on `e3-scale-drill` and `joy-to-the-world` (level 3, node expects ~6).

## Limits

- Calibrated on ~40 course songs; above Essentials III only PDMX weak labels inform the level.
- Features read the notation only: no fingering difficulty, pedalling, dynamics.
- `node_fit` needs the song inside some taught set; imported songs usually get `null` and rely on `level` and `exceeds`.
