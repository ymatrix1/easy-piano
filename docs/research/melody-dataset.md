# Melody model dataset (first build)

Checked: 2026-10-20

Sources: `data/melody/dataset/stats.json` from `python -m melody_model.build` (own, nottingham, mutopia, pdmx; 1,121 s on 28 processes); corpora per [melody-corpora.md](melody-corpora.md), D18, D19, D21.

Question: how many usable training tunes do the approved corpora give, and what is lost where?

## Kept tunes

| Corpus | Sources | Kept | Unflagged | Train / valid / test | Bars |
|---|---|---|---|---|---|
| own (`content/songs`) | 40 | 39 | 39 | 39 / 0 / 0 | – |
| Nottingham (minus Ashover) | 991 | 663 | 663 | 597 / 26 / 40 | 14,872 |
| Mutopia (Folk/Song/Hymn MIDI) | 57 | 19 | 19 | 15 / 2 / 2 | 570 |
| PDMX | 254,077 | 28,537 | 8,314 | 25,690 / 1,434 / 1,413 | 704,597 |
| **Total** | | **29,258** | **9,035** | | |

PDMX flags (D21, a tune can have several): no-composer 15,338, untagged 10,574, genre 1,224, pop-title 356, arrangement 354, pop-name 207.

PDMX meters: 4/4 14,269 · 3/4 4,056 · 6/8 3,959 · 2/2 2,768 · 2/4 2,696 · 9/8 393 · 3/8 235 · 12/8 161.

## Main losses

| Reason | Where |
|---|---|
| PDMX duplicates / licence conflict (hard rejects) | 145,502 / 31,221 |
| Meter changes, key changes | PDMX, Nottingham |
| Durations outside the table (triplets, tuplets) | all; ~3k PDMX, 138 NMD |
| Playability (leap > octave, range > 2 octaves) | fiddle tunes, art songs |
| Mutopia: 57 pieces passed the style + licence filter at download; 19 survive conversion | small |

## Implications

- ~29k tunes (≈720k bars) before phrase windows and 12 transpositions: enough for a 10–15M-param model. Clean-only (unflagged) ≈ 9k tunes: enough for ~5M.
- Biggest recoverable loss is notation coverage (tuplets, meter changes), not licensing.

## Follow-ups

- Gate: user approves a 50-tune PDMX sample (bean piano-qpyc) before training.
- Composer death-year table for PDMX/Lieder (D19 jurisdiction rule) still to apply.
- Training script and first run (step 4).
