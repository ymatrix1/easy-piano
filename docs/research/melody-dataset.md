# Melody model dataset

Checked: 2026-10-20

Sources: `data/melody/dataset/stats.json` from `python -m melody_model.build` (corpora own, nottingham, mutopia, pdmx; music21 10.5.0; 1,307 s on 28 processes; `tunes.jsonl` sha256 `e4279fef…91e4`). Rules: [melody-model spec](../specs/melody-model.md), decisions D18, D19, D21.

Question: how many usable training tunes do the corpora give, with what styles, and what is lost where?

## Kept tunes

| Corpus | Sources | Kept | Unflagged | Train / valid / test | Bars |
|---|---|---|---|---|---|
| own (`content/songs`) | 40 | 38 | 38 | 38 / 0 / 0 | 345 |
| Nottingham (minus Ashover) | 991 | 662 | 662 | 596 / 26 / 40 | 14,855 |
| Mutopia | 57 | 20 | 20 | 16 / 2 / 2 | 617 |
| PDMX | 254,077 | 38,895 | 8,749 | 34,922 / 1,989 / 1,984 | 1,000,788 |
| **Total** | | **39,615** | **9,469** | | **1,016,605** |

Tunes over 64 bars are cut to 64 (PDMX 6,043, Nottingham 4, Mutopia 3).

## Styles (PDMX; a tune can have several)

classical 20,088 · folk 3,457 · religious 995 · soundtrack 945 · pop 665 · rock 571 · game 413 · jazz 272 · children 241 · electronic 138 · world 80 · chinese 63 · none 12,999.

Nottingham: folk 662. Own: children 38. Mutopia: classical 11, folk 6, religious 3.

## Flags (PDMX, D21; a tune can have several)

no-composer 16,014 · untagged 12,482 · licence-conflict 8,981 · genre 1,874 · pop-title 555 · arrangement 521 · pop-name 340.

## Main losses (PDMX)

| Reason | Count |
|---|---|
| PDMX's own duplicate flag | 151,442 |
| Bar length does not add up | 12,497 |
| Durations outside the table (tuplets) | 12,207 |
| Meter not in the vocab | 5,505 |
| Range > 2 octaves / leap > octave | 4,437 / 4,392 |
| Meter change | 4,369 + |
| Our duplicate check | 3,894 |

## Implications

- About 1M bars (≈ 13M tokens before windows and transpositions): enough for a 10–15M-param model.
- Ties (`{tie}`) recovered the tunes the strict converter had dropped (PDMX 18,584 → 38,895 kept, together with licence-conflict scores now flagged).
- Next recoverable loss: tuplets and odd bar lengths (~25k PDMX).

## Follow-ups

- 50-tune gate (bean piano-qpyc) on this dataset hash before training.
- Tuplet support; composer death-year table.
