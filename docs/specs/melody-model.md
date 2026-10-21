# Melody model

Status: draft. Step 2 of the practice-tune model (bean piano-lkg2). Corpora and design: [melody-corpora.md](../research/melody-corpora.md) (PR #37). Code: `tools/melody-model/`.

## Converters (`melody_model/convert.py`)

| Input | Path | Keeps | Loses |
|---|---|---|---|
| MusicXML (OpenScore, PDMX) | music21 | spelling, fingering, ties inside a bar | voices after the first |
| ABC (Nottingham) | music21, multi-tune files | spelling | – |
| LilyPond (Mutopia) | Mutopia's MIDI of the same source, music21 `quantizePost` | pitch, rhythm | spelling (re-inferred), fingering |

Output: `{title, composer, time, key, bars: [{RH, LH}]}` in the [content format](content-format.md) note grammar. First part → RH, second → LH; a lone bass-clef part → LH. Pickup and short final bars are padded with rests.

Rejected (`Unsupported`, counted by the dataset builder): tuplets, durations outside the table below, double accidentals, meter or key changes, keys/meters outside the vocab, hands with different bar counts.

## Tokens (`melody_model/tokenizer.py`, `vocab.json`)

Compound steps: each step is `(kind, pitch, dur, finger)`; the model sums four embeddings and predicts four heads. Fields that do not apply are `<none>` (id 0).

| Field | Values | Size |
|---|---|---|
| kind | structure, spec, plan, FIM tokens (below) | 150 |
| pitch | spelled `C0`…`B8` with `''`, `#`, `b` | 190 |
| dur | `1 1. 2 2. 2.. 4 4. 4.. 8 8. 16 16. 32` | 14 |
| finger | 1–5 | 6 |

Layout:

```
BOS SPEC COURSE_x TIME_x KEY_x BARS_n RANGE_LO(p) RANGE_HI(p) DUR_ALLOW(d)… HANDS_x [PAT_x…] SPEC_END
[PLAN … PLAN_END]
BAR RH <events> [LH <events>]  BAR …  END
```

- Note: `NOTE(pitch, dur, finger)`. Chord: `NOTE` then `CHORD(pitch, finger)` per extra pitch, same onset. Rest: `REST(dur)`.
- Spec values ride in the pitch/dur fields (`RANGE_LO` pitch, `DUR_ALLOW` dur). Pattern kinds mirror skill-spec pattern keys (PR #38): `PAT_rhythm`, `PAT_interval`, `PAT_accidental`, `PAT_pitch`, `PAT_rest`, `PAT_chord`, `PAT_hands_together`.
- Reserved for later steps: plan (`SEC_A`…`SEC_H`, `CAD_STABLE/OPEN`, `CON_UP/DOWN/FLAT`), fill-in-the-middle (`FIM_PRE`, `FIM_SUF`, `FIM_MID`).
- Backing parts (`ACC`, `DRUMS`, …) are not tokenized.
- No `NODE` token: training tunes have no node; nodes condition through their spec and patterns.

Round trip: `decode(encode_song(song))` returns the song's `time`, `key` and RH/LH bars exactly (whitespace-normalized). Tested on every file in `content/songs/`. Longest current song: 142 steps (ctx 1,024 leaves room for spec, plan and FIM).

## Checks

`cd tools/melody-model && python -m pytest` (venv: `pip install -r requirements.txt`).

## Dataset (`melody_model/build.py`, step 3)

```
python -m melody_model.download nottingham pdmx mutopia   # into data/melody/raw (git-ignored)
python -m melody_model.build                               # -> data/melody/dataset/tunes.jsonl + stats.json
python -m melody_model.sample --corpus pdmx --n 50         # review sample (gate bean piano-qpyc)
```

- One JSON line per source tune: `id, corpus, split, license, title, composer, time, key, bars, plan, flags`.
- `plan`: per bar `(section A–H, STABLE|OPEN, UP|DOWN|FLAT)` (`labels.py`).
- `flags` (D21): PDMX clean-data risks (`genre`, `untagged`, `no-composer`, `pop-name`, `pop-title`, `arrangement`) and any flags of a local dataset. Train a clean model by dropping flagged tunes.
- Filters (`filters.py`): PDMX hard rejects (licence conflict, duplicates, length), NMD named composer, playability (range ≤ 24 semitones per hand, leap ≤ 12, ≤ 16 events/bar, chord size), vocab coverage, transposition-invariant dedupe.
- Split 90/5/5 by source tune (or by group for local datasets), deterministic.
- Phrase windows (4/8/16 bars, step 4) and spelled transposition run at training time (`augment.py`).

### Local MIDI datasets

Any folder of `.mid` files can be plugged in without code changes: add an entry to `data/melody/local-datasets.json` (git-ignored; template `tools/melody-model/local-datasets.example.json`) with `name`, `path`, `source`, `license`, `flags`, and optionally `timing` (`score`: tempo-mapped, quantized by music21; `performed`: tempo estimated from onsets, `timed.py`), `track` and `group_by` (`file`/`folder`). Local datasets are opt-in: `python -m melody_model.build --corpora own nottingham mutopia pdmx <name>`. None are registered by default.
