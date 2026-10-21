# Model card: melody-model-v1

Checked: 2026-10-21. Code: `tools/melody-model/`. Spec: [melody-model](../specs/melody-model.md). Decisions: D17, D18–D21 (PR #44); weights licence D24 and decoding deviation D25 (proposed, PR #44).

## Purpose

Generate short original practice tunes for an Easy Piano course node, conditioned on the node's spec (meter, key, bars, range, taught durations, hands, required patterns, level, style). Generation runs offline in the content pipeline (D17). A tune ships as content only after it passes the rubric (`content check`) and human review. The similarity check (`content similar` against our songs and every training tune) runs and reports matches, but does not block for now (D27, proposed); reviewers see its flags. A browser demo runs the same model with onnxruntime-web (PR #48).

## Model

| | |
|---|---|
| Architecture | compound decoder-only transformer: 4 summed field embeddings (kind, pitch, dur, finger), 6 layers, d 384, 6 heads, RoPE, cascaded heads |
| Parameters | 11,092,620 |
| Context | 1,024 compound steps |
| Vocab | kind 186, pitch 190, dur 14, finger 6 (`tools/melody-model/vocab.json`, sha256 `e12cdd27…`) |
| Release files | `decoder.int8.onnx` 11.7 MB, `heads.int8.onnx` 0.8 MB, `vocab.json`, `meta.json`, `train-config.json`; PyTorch checkpoint `melody-base1.ckpt.pt` 44.4 MB |
| Where | GitHub Release `melody-model-v1` on ymatrix1/easy-piano, **not** in git. Sizes and sha256: `tools/melody-model/releases/melody-model-v1.json`. `python -m melody_model.release fetch --out <dir>` downloads and verifies; a hash mismatch deletes the file and fails |

## Training

| | |
|---|---|
| Run | `base1`, 2026-10-21, seed 1, RTX 4070 SUPER, torch 2.11.0+cu128 |
| Schedule | 20,000 steps, 32,768 padded tokens per batch, AdamW lr 3e-4, warm-up 500, cosine to 10%, bf16 |
| Data seen | 356.9M tokens in 2,211 s (~37 min), peak 3.8 GB |
| Result | best validation loss 0.875 (kind 0.273, pitch 0.446, dur 0.154); train ~0.91, no overfitting |
| Evidence | `releases/melody-model-v1.train-summary.json`, `releases/melody-model-v1.train-log.jsonl`, curve: [melody-v1-loss.svg](melody-v1-loss.svg) |

## Data

Dataset `tunes.jsonl` sha256 `e4279fef…91e4` (`python -m melody_model.build`, stats in `docs/research/melody-dataset.md`): 39,615 tunes (train 35,572, valid 2,017), about 1.0M bars. The user approved the 50-tune review gate on 2026-10-20.

| Corpus | Tunes | Licence notes |
|---|---|---|
| PDMX (MuseScore, Zenodo 15571083) | 38,895 | Dataset CC-BY-4.0; files tagged public domain or CC0 by their uploaders. Flags (D21): no composer, untagged, **licence conflict** (8,981: the file's own licence says copyrighted), pop/film/game genre, pop name or title, third-party arrangement. Flagged tunes are in training |
| Nottingham Music Database | 662 | No licence grant; used under D18 (risk accepted); Ashover excluded |
| Mutopia | 20 | Public domain, CC-BY or CC-BY-SA per piece |
| Easy Piano songs | 38 | ours |

Each tune is tagged with styles: classical, folk, religious, world, children, pop, rock, soundtrack, game, jazz, electronic, chinese. **Chinese music is included and tagged `STYLE_chinese`** (user, 2026-10-20); generation avoids it unless asked.

Not used: Essen, Meertens and The Session (their licences forbid this use), POP909, NES-MDB.

## Licence

Weights: proposed in D24, not decided yet. Generated tunes: CC0-1.0 (D17).

## Evaluation

- **Both gates, 10 lesson nodes, 16 candidates each** (`releases/melody-model-v1.eval-generation.json`): **123 / 160 pass the rubric (77%)**; **0 pass the similarity gate.**
  - Why none pass: every top match is a ~10-note fragment with low information (scale runs, repeated figures) scoring 1.00 against the 39,615-tune corpus.
  - The 0.5 threshold was calibrated on our 40 songs (PR #34), so the gate needs calibration for corpus size before any tune can ship.
  - Blocking is therefore off for now (D27); matches are reported for human review.
  - Earlier rubric-only run, before the gates were made fail-closed: 108 / 155 (70%).
- **Browser:** in Chrome desktop with the int8 model, an 8-bar tune takes about 0.3–0.4 s (PR #48 has the method).
- **Blind listening test:** pending (30 generated tunes + 6 control songs).

## Limits

- One voice per hand (top voice). No tuplets, ornaments, dynamics or pedal. Max 64 bars. Meters: 2/4, 3/4, 4/4, 2/2, 3/8, 6/8, 9/8, 12/8.
- Trained mostly on intermediate material; beginner specs rely on simplified variants and masks.
- Fingering is not learned (sources rarely have it); the arranger fingers tunes.
- Required patterns and finger spans are not masked; the rubric filters (D25).

## Known risks

- **Memorised copyrighted melodies.** Flagged PDMX tunes (pop, film, game, licence-conflict scores) are in training by the user's decision (D21), so the model may reproduce phrases from them.
  - Mitigation: `content similar` runs on every generated tune and its matches go to the reviewer; automatic blocking is off until the gate is calibrated (D27). Human review (D17) is the gate meanwhile.
  - Per-tune provenance allows retraining without any corpus or flag.
- **Untested licence positions:** NMD transcriptions (D18), CC-BY-SA data (Mutopia), CC-BY dataset terms (PDMX). See OQ10 and D24.
- **Style labels** are keyword-based; 12,999 PDMX tunes have none (bean piano-oial).
