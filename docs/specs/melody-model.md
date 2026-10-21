# Melody model

Status: draft. Practice-tune model, steps 2–5 (beans piano-lkg2, piano-bgqv). Corpora and design: [melody-corpora.md](../research/melody-corpora.md), [D18–D21](../DECISIONS.md). Code: `tools/melody-model/`.

## Converters (`melody_model/convert.py`)

| Input | Path | Keeps | Loses |
|---|---|---|---|
| MusicXML (PDMX) | music21 | spelling, single-note fingering, ties inside a bar | chord fingering (music21 loses its note order), lower voices |
| ABC (Nottingham) | music21, multi-tune files | spelling | chord symbols |
| MIDI (Mutopia) | music21 `quantizePost` | pitch, rhythm | spelling (re-inferred), fingering |

There is no LilyPond (`.ly`) parser: Mutopia pieces are read from the MIDI that Mutopia renders from the same LilyPond source under the same licence.

Output: `{title, composer, time, key, bars: [{RH, LH}]}` in the [content format](content-format.md) note grammar.

| Rule | Behaviour |
|---|---|
| Hands | two parts: higher mean pitch → RH; one part: LH if bass clef or mean pitch below G3; `melody_only` reads only the first part as RH (voice + piano scores, MIDI) |
| Parts | more than two (and not `melody_only`) → rejected |
| Voices | in a multi-voice bar, the voice with the highest mean pitch |
| Chords | pitches low to high; fingering kept only when stored per note |
| Ties | merged inside a bar when the chain sums to one duration; otherwise kept as the content grammar's `{tie}` token after the note (also across barlines); a tie into a different pitch is rejected; a dangling tie on the last note is dropped |
| Pickups | opening and section-end short bars padded with rests; strain end + next pickup written as two short measures are joined |
| Meter | one meter; a shorter bar (3/8 or 2/4 in 6/8) is a short bar; any other change → rejected |
| Key | one signature size and one stated mode (a bare signature agrees with a `Key` of the same sharps); a same-signature mode change (C → Am) is a key change → rejected; with no stated mode, music21 analysis must reach correlation ≥ 0.6, else rejected |
| Durations | `1 1. 2 2. 2.. 4 4. 4.. 8 8. 16 16. 32`; tuplets and others → rejected |
| Failures | parser exceptions → `Unsupported("parse error: …")`, never a crash; `convert_file_lenient` returns `Unsupported` objects |
| Files with several scores | an Opus of movements is not one tune → rejected (`N scores in one file`), except multi-tune ABC files, which the builder splits per tune first |

Rejected tunes raise `Unsupported` and are counted by the dataset builder.

`melody_model/timed.py` converts performed MIDI (no usable tempo map): onsets on a 16th grid of given or estimated beats, highest note wins, gaps up to one beat treated as articulation.

## Tokens (`melody_model/tokenizer.py`, `vocab.json`)

Compound steps: each step is `(kind, pitch, dur, finger)`. Fields that do not apply are `<none>` (id 0).

| Field | Values | Size |
|---|---|---|
| kind | structure, spec, style, pattern, plan, FIM tokens (below) | 181 |
| pitch | spelled `C0`…`B8` with `''`, `#`, `b` | 190 |
| dur | the 13 durations above | 14 |
| finger | 1–5 | 6 |

### Left-to-right sample

```
BOS
SPEC [STYLE_x…] [SRC_x] COURSE_x TIME_x KEY_x BARS_n RANGE_LO(pitch) RANGE_HI(pitch) DUR_ALLOW(dur)… HANDS_x [PAT …]… SPEC_END
PLAN (SEC_x CAD_x CON_x) per bar PLAN_END
BAR RH <events> [LH <events>]  BAR …
END
```

- Event: `NOTE(pitch, dur, finger?)`; chord = `NOTE` then `CHORD(pitch, finger?)` per extra pitch (same onset, no dur); `REST(dur)`; `TIE` after a note's steps = tied into the next note (`{tie}` in song JSON).
- Style (`styles.py`): `STYLE_classical|folk|religious|world|children|pop|rock|soundtrack|game|jazz|electronic|chinese`, several allowed, sorted. From corpus (NMD → folk, own → children, Mutopia style) and PDMX genres, tags, groups and title keywords (e.g. zelda → game, anime → soundtrack). Free-text tags never enter the vocab. Training drops them at random so the model also runs without; generation picks the styles the app allows.
- Source: `SRC_own|nottingham|mutopia|pdmx|local`; training only (lets the model separate corpus habits), omitted at generation.
- Pattern (skill-spec `required`, [skill-specs.md](skill-specs.md)): `PAT` then one step per key in fixed order: `PAT_rhythm(dur)`, `PAT_interval_min_2…8`, `PAT_accidental(pitch class at octave 4)`, `PAT_pitch(pitch)`, `PAT_hand_RH|LH`, `PAT_share_25|50|75|100` (`min_bar_share` rounded up), `PAT_rest`, `PAT_chord`, `PAT_hands_together`. A test encodes every pattern in `content/skill-specs/*.json`.
- Plan: one triple per bar, bar count = `BARS_n`. `SEC_A…H`: same letter = same or near-same bar (rhythm equal and ≥ half the intervals equal; letters after H fold into H). `CAD_STABLE`: last melody note is in the tonic triad, else `CAD_OPEN`. `CON_UP|DOWN|FLAT`: last minus first melody pitch, `FLAT` within ±2 semitones (`labels.py`).
- No `NODE` token: training tunes have no node; nodes condition through spec and patterns. Backing parts are not tokenized.

### Fill-in-the-middle sample

Same spec and plan prefix, then the bars split into prefix P, middle M, suffix S (M = 1–4 whole bars):

```
BOS SPEC … SPEC_END PLAN … PLAN_END
FIM_PRE <bars of P>  FIM_SUF <bars of S>  FIM_MID <bars of M>  END
```

At inference the model is given everything up to `FIM_MID` and generates M. The plan always covers all bars, so M's plan triples are known.

### Decoding

`decode(steps)` returns `{time, key, bars}` and raises `InvalidSequence` on anything `encode_song` cannot produce (ids out of range, notes outside a hand, missing fields, `CHORD` without `NOTE`, partial chord fingering, a hand twice in a bar, spec tokens after the first bar, empty bars, no time/key). Bar lengths are left to the rubric.

Round trip: `decode(encode_song(song))` returns `time`, `key` and RH/LH bars exactly, for every song in `content/songs/`. Longest current song: 142 steps (ctx 1,024).

## Checks

`cd tools/melody-model && uv sync && uv run pytest` (training deps: `uv sync --extra train`).

## Dataset (`melody_model/build.py`, step 3)

```
python -m melody_model.download nottingham pdmx mutopia   # into data/melody/raw (git-ignored)
python -m melody_model.build                               # -> data/melody/dataset/tunes.jsonl + stats.json
python -m melody_model.sample --corpus pdmx --n 50         # review sample (gate bean piano-qpyc)
```

- One JSON line per source tune: `id, corpus, split, license, title, composer, time, key, bars, plan, flags`.
- `plan`: per bar `(section A–H, STABLE|OPEN, UP|DOWN|FLAT)` (`labels.py`).
- `flags` (D21): PDMX clean-data risks (`licence-conflict`, `genre`, `untagged`, `no-composer`, `pop-name`, `pop-title`, `arrangement`) and any flags of a local dataset. Licence-conflict scores (the file's internal licence disagrees with the public tag) are included, flagged (user, 2026-10-20).
- `styles`: style labels (see Tokens).
- Flagged tunes **are** used in training (D21; user, 2026-10-20: "no i want to use the flagged tunes"). Known risk: weights may memorise copyrighted melodies. Flags and provenance let any corpus or flag be dropped and the model retrained.
- **Chinese music** is included and tagged `STYLE_chinese` (user, 2026-10-20, on the agent's recommendation; earlier "i just dont want chinese music"), detected by metadata (`filters.is_chinese`: Chinese tags, Han script without kana after repairing PDMX mojibake, Chinese instrument/genre words, known Chinese artists). Generation avoids it unless asked.
- Provenance per tune: `source_url`, `sha256` (source file, or the tune's ABC text for NMD), `license`, `composition_license`, `arranger`, `flags`.
- Deterministic: fixed job order, results consumed in order, first tune of a duplicate group kept (own songs first). `stats.json` records corpora, music21 version and the sha256 of `tunes.jsonl`; tunes over 64 bars are cut at the last phrase end (stable cadence on a 4-bar boundary) in bars 32–64, or rejected when there is none; both counted.
- PDMX downloads are checked against pinned sha256 (`download.PDMX_SHA256`).
- Review gate: `melody_model.train` refuses to run until `python -m melody_model.gate approve …` records the user's approval of a 50-tune sample for the current `tunes.jsonl` hash.
- Filters (`filters.py`): PDMX hard rejects (duplicates, length), NMD named composer, playability (range ≤ 24 semitones per hand, leap ≤ 12, ≤ 16 events/bar, chord size), vocab coverage, transposition-invariant dedupe.
- Split 90/5/5 by source tune (or by group for local datasets), deterministic.
- Phrase windows (4/8/16 bars, step 4) and spelled transposition run at training time (`augment.py`).

### Local MIDI datasets

Any folder of `.mid` files can be plugged in without code changes: add an entry to `data/melody/local-datasets.json` (git-ignored; template `tools/melody-model/local-datasets.example.json`) with `name`, `path`, `source`, `license`, `flags`, and optionally `timing` (`score`: tempo-mapped, quantized by music21; `performed`: tempo estimated from onsets, `timed.py`), `track` (part/track index or name), `meter` (performed only: `2/4`, `3/4`, `4/4`) and `group_by` (`file`/`folder`). Bad types or values are rejected; licence and source are recorded as given. Local datasets are opt-in: `python -m melody_model.build --corpora own nottingham mutopia pdmx <name>`. None are registered by default.

## Training (`melody_model/train.py`, step 4)

```
python -m melody_model.train --name base1 --steps 20000 --workers 8   # refuses without the review gate or an existing run dir
```

- Model (`model.py`): compound decoder, sum of four field embeddings, pre-norm blocks with RoPE attention, cascaded heads kind → pitch → dur → finger (teacher-forced in training). Default 6 layers, d 384, 6 heads, ctx 1,024: 11.09M params.
- Samples (`samples.py`), drawn on the fly from `tunes.jsonl` train split: phrase window (whole tune or 4/8/16 bars), plan relettered from A, random spelled transposition (−6…+11), 30% easier variant (`simplify.py`: RH-first, coarser rhythm grid, range folded to one octave), spec computed from the result plus `LEVEL_1…5` (`difficulty.level_of`, dropped 20%), 0–3 patterns it satisfies (`difficulty.patterns_of`), styles (dropped 20%), source. 25% FIM (1–4 middle bars). Loss: plan and bars after `SPEC_END` (left to right), middle bars after `FIM_MID` (FIM).
- Batches by token budget (32,768 padded tokens; similar-length samples grouped). AdamW (0.9, 0.95), weight decay 0.1, lr 3e-4, 500 warm-up steps, cosine to 10%, bf16, grad clip 1.0.
- Output in git-ignored `data/melody/runs/<name>/`: `config.json` (args, command line, git sha/branch/dirty, params, dataset and vocab sha256, gate), `log.jsonl`, `ckpt.pt` (best validation loss), `summary.json`. An existing run directory is never reused.
- Source tokens are dropped in 50% of samples (from runs after `base1`), so generation may omit `SRC`; `base1` always saw one, so generation passes `--source own` by default.

Smoke runs (RTX 4070 SUPER, 2026-10-20, dataset `e4279fef…`): 2 min, 8 workers → 1,087 steps, 19.4M tokens, ~160k tokens/s, 3.8 GB peak, validation loss 2.17 → 1.40 (kind 0.35, pitch 0.79, dur 0.25, finger 0.003; fingering is almost always absent in the data).

## Browser export (`melody_model/export.py`, `web/`, step 5)

```
uv sync --extra train --extra export          # torch + onnx/onnxruntime 1.30.0
python -m melody_model.export --run base1      # -> tools/melody-model/web/model/ (git-ignored)
python tools/melody-model/web/fetch_ort.py     # onnxruntime-web 1.30.0 -> web/vendor/ (git-ignored, sha256-pinned)
python tools/melody-model/web/serve.py         # http://localhost:8780/ (COOP/COEP: needed for wasm threads)
```

- `decoder.onnx`: one decoding call with a KV cache. `x (B,T,4)`, `past_k/past_v (L,B,H,P,hd)` → `h (B,d)` of the last step, `present_k/present_v`. Prefill with the spec prefix and `P = 0`, then one step per call. Chosen over a full-sequence graph, which re-runs the prefix every step (O(n²)).
- `heads.onnx`: `h, kind, pitch, dur` → four logit vectors. Head *i* reads only earlier fields, so the caller samples kind, reruns for pitch with that kind, and so on.
- `*.int8.onnx`: onnxruntime dynamic quantization of MatMul/Gemm weights (int8); embeddings and LayerNorm stay fp32. Exported with the TorchScript exporter (opset 17).
- `meta.json`: run, step, val loss, config, sizes, sha256 of every other file, parity, validation NLL (PyTorch / ONNX fp32 / ONNX int8 on 200 held-out tunes). `vocab.json`: field vocabularies. `parity.json`: Ode to Joy steps and PyTorch logits for the in-browser parity check.
- Acceptance for a checkpoint: fp32 max abs logit diff < 1e-4 (KV-cache path = full sequence), int8 validation NLL within 1% of fp32. Max prob diff is reported, not gated: on base1 it is 0.082 for +0.12% NLL ([melody-browser.md](../research/melody-browser.md)).
- Tests (`tests/test_export.py`): toy model (fp32 < 1e-4, int8 max prob diff < 0.05, NLL fp32 = PyTorch) and the shipped shape with random weights (`slow` marker: 11.09M params, fp32 parity, int8 NLL within 2%).
- Python onnxruntime and onnxruntime-web are pinned to the same version (1.30.0). The page loads the runtime and wasm only from `vendor/` and checks each model file's sha256 against `meta.json` before creating a session; `?model=<base URL>` loads from another host (needs CORS and CORP headers). `meta.json` itself is not yet pinned.
- `web/melody.js` (no DOM): `encodeSpec` (= `encode_spec`, durations sorted as `spec_from_song`), `Grammar` masks, `generate`, `decode` (= `tokenizer.decode`). `web/check.mjs` + `tests/test_web.py` check it against Python under Node: spec encoding and decoding are equal; generation (random logits) yields sequences the Python decoder accepts and that satisfy the spec. They do not compare chosen ids with Python (different RNGs, different masks in `generate.py`).
- With `CI` or `MELODY_REQUIRE_ALL` set, a missing node or onnxruntime fails these tests instead of skipping them.

Masks at each step:

| Rule | Mask |
|---|---|
| Plan | `PLAN`, then `BARS_n` triples (`SEC_` lettered from A, no letter skipped; `CAD_`; `CON_`), `PLAN_END` |
| Bars | `BAR`, then the spec's hands in order (`BOTH` = RH then LH, both required); `END` only after bar `n` |
| Bar fill | `NOTE`/`REST` dur ≤ remaining and the rest fillable with allowed durations; hand closes only at exactly full |
| Pitch | `NOTE` within `RANGE_LO…RANGE_HI`; `CHORD` above the last chord pitch, ≤ 12 semitones over the root, ≤ 4 notes |
| CHORD/TIE | only after `NOTE`/`CHORD`; no `REST` after `TIE`; no `TIE` at the tune's last slot; chord fingering all or none |
| Unused fields | `<none>` |

Candidates are ranked by mean log probability under the masked distributions. Chrome desktop timings: [melody-browser.md](../research/melody-browser.md).

## Generation (`melody_model/generate.py`)

```
python -m melody_model.generate --run base1 --node essentials-1/rests -n 16 --key C --style folk --out data/melody/gen/rests
```

- Spec from the node: taught set (`content specs`: pitches per hand, durations, rest durations, accidentals, max interval, polyphony, times) and its skill spec (bars, bpm, hands, time, `required`). Level from the taught set (same scale as training), styles optional.
- Masked decoding at every step: grammar (plan triples per bar, `PLAN_END`, `BAR`, hands in order, events, `END`), taught pitches per hand, no leap over the taught interval, taught durations that still fit the bar, chord size ≤ taught polyphony with rising chord notes; no ties, no fingering (the arranger fingers later).
- Candidates become song JSON with D17 fields (`source: generated`, `license: CC0-1.0`, `generator.method: melody-model`, `spec_node`). Two gates, both **fail closed** (a tool error, missing output or a candidate without a result aborts the run):
  1. Rubric: `content check <content> <course/node> <files>` (`core/src/rubric.rs`); also proves each file parses as a `Song`.
  2. Similarity: `content similar <files> --corpus content/songs --corpus data/melody/similarity-corpus [--corpus references/melody-corpus] --threshold 0.5`. **Report-only for now** (D27, proposed; user, 2026-10-21: "lets not block for now and decide later"): flagged ids go to `report.json` (`similar`, `kept_flagged_similar`); `--block-similar` drops them. At this corpus size the 0.5 threshold flags every simple tune (short low-information fragments score 1.00), so it needs calibration before it can block. The corpus is every dataset tune exported by `python -m melody_model.simcorpus` (39,615 songs; one check of a node's candidates takes ~3 min on this machine).
- Kept tunes are ranked by mean log-probability plus a bonus for ending on the tonic. Sampling must reach `END` (no truncated candidates); the duration head is conditioned on the pitch field exactly as in training (`<none>` for rests).
- `report.json` per run: candidates, rubric passes, similarity passes, kept files, rubric errors, ids rejected as similar.
- The content CLI is found via `$CONTENT_CLI`, a built `tools/content-cli/target/{release,debug}/content`, or `cargo run`.

**Deviation from D20 (masked decoding):** finger spans are not masked (no fingering is generated; the arranger adds it) and `required` patterns are not forced (a mask cannot know early that a later bar will add the required note). Both are left to the rubric gate; candidates that miss a pattern are dropped. Proposed decision: D25 (PR #44).

First try (2-minute smoke checkpoint, essentials-1/rests, 8 candidates): 5 passed the rubric; the 3 failures missed the required rest (and one leap, from a mask fallback since fixed).

Full run `base1` (2026-10-21, RTX 4070 SUPER): 20,000 steps, 356.9M tokens, 2,211 s (~37 min), peak 3.8 GB, best validation loss 0.875 (kind 0.273, pitch 0.446, dur 0.154 at step 19,500; train ~0.91, no overfitting). Evidence: `tools/melody-model/releases/melody-model-v1.train-summary.json`, `…train-log.jsonl`, loss curve `docs/models/melody-v1-loss.svg`. Generation before the gates were made fail-closed, 16 candidates per node, 10 lesson nodes from Piano Basics to Essentials III, GPU: **108 / 155 decoded candidates passed the rubric (70%)**, from 14/16 (c-d-e, f-and-g) and 15/15 (hands-together) down to 6/16 (shifting). All remaining failures are unmet `required` patterns (a required pitch 26, F# 6, rhythm share 6, rest 4, dotted rhythm 4, interval 3); taught-set rules (pitches, durations, leaps, chords) always pass. Follow-up: steer decoding toward unmet required patterns near the end of the tune.
