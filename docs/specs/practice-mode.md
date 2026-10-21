# Practice mode: generated tunes

Status: web implemented, endless streaming (epic `piano-c6v1`, beans `piano-urcd`, `piano-movl`, `piano-h09q`). Decision: [D28](../DECISIONS.md#d28-practice-mode-generates-tunes-in-the-app-at-runtime). Model: [melody-model.md](melody-model.md). Timings: [research/practice-mode-timing.md](../research/practice-mode-timing.md).

## What the learner sees

Endless practice: the model writes music at the learner's level while they play; the notes keep coming until they leave.

| Step | Behaviour |
|---|---|
| Entry | Practice tab → **Endless practice** card (hidden when the build has no model manifest or practice pack). |
| Setup | Game-style chips (chamfered, yellow when picked). **Level** 1–5: the taught set's difficulty (`level_for`); each level uses the last course node at that level, the widest taught set it allows (default: the level of the learner's next node). **Style**: any, classical, folk, children's, pop, jazz, game (the model's `STYLE_` token). **Hands**: right / left / both, offered only when that hand has taught notes. **Tempo**: 40–160 bpm (default: the node's). **Note values**: the taught values; PLAY is off while they cannot fill a bar. **Mode**: wait for me / play along. |
| First use | "Getting the tune maker ready…" with a download bar (percent of the runtime files). |
| Later uses | Files come from the browser cache; the bar jumps to 100 %. |
| Generating | "Writing a tune for this lesson…" until the first 4-bar chunk passes the rubric. |
| Playing | The normal stage UI (`PracticeStage`) in the chosen mode. New 4-bar chunks are appended while the learner plays (one chunk ahead from the start, then whenever fewer than 24 beats are left). A **Generated** badge stays on top; the banner says practice only, no stars. Close leaves at any time. |
| Stream cannot continue | After a chunk fails every attempt the feed ends; the learner plays to the end and sees "Couldn't write more music with these settings", notes hit, and **Play again**. |
| Accompaniment | Every chunk gets `BASS`, `ACC` and `DRUMS` from `core::accompany` (play-along plays them; never graded). One C-major chord per bar (I, ii, IV, V, vi) picked by how much of the bar's melody it covers, biased toward I/IV/V and toward the previous chord. Patterns by style and meter (4/4, 3/4, 2/4, 6/8): pop/rock/game get drums and driving bass, jazz a light ride pattern, chords on 2 and 4 and a walking bass, classical an Alberti-style broken chord, the rest half-note chords and root–fifth bass. When the learner plays the left hand the piano `ACC` is dropped and a sustained strings `PAD` holds the chord instead; `BASS` (an octave below the left hand) and drums stay. |
| Top bar | Endless mode shows notes hit and the current streak instead of a progress bar (there is no end to measure). |
| No first chunk | "Couldn't make a tune that fits this lesson. Try again." with Retry. |
| Download/verify fails | "Couldn't load the tune maker…" with Retry. |
| Native platforms | "Practice tunes only work in the browser for now." No retry. |

## Rules (D28)

- [x] Tunes are generated on device for the chosen level (course node), streamed in chunks while the learner plays.
- [x] Model files are verified by sha256 against the bundled release manifest before use, cached or not (D24).
- [x] Every chunk passes `rubric::check_generated`, checked as part of the whole song so far, before it is appended; failures are dropped, never displayed. The rubric node is the node's taught set with the learner's hands and tempo, any length, and no required pattern (a 4-bar chunk cannot carry every pattern of a node).
- [x] Retry: up to 4 rounds of 4 candidates per chunk (`PracticeStream.maxAttempts`, `candidates`), each bounded by `roundTimeout` (60 s); then the first chunk shows the friendly error and later chunks end the stream.
- [x] Tunes are marked `source: generated`, `generator.method: melody-model` and show the **Generated** badge. `check_generated` refuses any song without those marks.
- [x] No stars, no level or gate progress: the page never returns a result to `HomePage` and never touches `Progress`.
- [x] Nothing is saved or shared: the tune lives in page state only.
- [x] No copy check, no human review (user's decision in D28).
- [ ] Native platforms (no ONNX runtime wired yet).
- [x] Nodes whose required pattern needs an accidental get tunes too: streaming chunks do not require the node's patterns.

## Pipeline

| Piece | Where | Does |
|---|---|---|
| Practice pack | `content practice-pack` (`tools/content-cli/src/practice.rs`), run by `tools/sync_content.py` into `assets/content/practice.json` | Per node: `practice` = `{taught, spec}` (rubric input), `gen` = generation spec + masks, or `unavailable` with a reason. |
| Manifest | `tools/melody-model/releases/melody-model-v1.json` → `assets/content/melody-model-v1.json` | Trust root: file sizes, sha256, decoder shape. |
| Download | `ModelStore` (`app/lib/practice/generated/model_store.dart`) | Cache Storage first (key = sha256/name), else fetch with progress; sha256 check either way; a bad cache entry is deleted and fetched again; a bad download throws `ModelIntegrityError` and is not cached. |
| Runtime | `app/web/melody/practice.js` (loaded on demand via `window.epMelodyImport`) | onnxruntime-web 1.30.0 (wasm, up to 4 threads when cross-origin isolated), KV-cached decoder + heads, `melody.js` masked decoding and decoding. |
| Stream | `PracticeStream` (`practice_stream.dart`) | Builds each chunk's spec from the setup (`bars` 4, `styles` = the picked style, chosen durations, hands, tempo; masks from the taught set; `mask.start` = each hand's last note so the leap rule holds across chunks), picks the first candidate (best mean log p) that passes the gate, pushes the grown song to a `SongFeed`. |
| Gate | bridge `check_generated` → `core::rubric::check_generated` | Rubric errors for the song so far; empty = append. |
| Accompaniment | `core/src/accompany.rs`, bridge `accompany_bars` | Adds backing parts to each new chunk (only the new bars); a failure leaves the chunk as it is. The stage schedules the new bars' backing (and metronome) as they arrive. |
| Session | `Session::extend` (`core/src/session.rs`), bridge `PracticeSession.extend` | Appends targets for the new bars; judged targets keep their state; a wait-mode learner who already finished the old part continues at the first new note. |
| UI | `StreamSetupPage`, `StreamPracticePage`, `PracticeStage(feed:)` | Setup, states above; the stage extends its session and staff on every push, asks for more through `SongFeed.onDemand`, fixes the wait-mode page scale, and finishes only after the feed ends. |

### Generation spec (`gen`)

Mirrors `generate.py` (`build_prefix`, `Masker`, `level_for`): `time` and `hands` from the skill spec, `bars` = spec max, `bpm` = spec midpoint, `key` C, `range_lo`/`range_hi` from the taught pitches of the node's hands, `durs` = taught durations in model vocabulary, `patterns` = spec `required`, `level` from the taught set, `source` own, course token when the vocabulary has it (else `none`).

Masks (`gen.mask`, applied by `melody.js` `Grammar`): taught pitches per hand matched by spelling (no enharmonics), max leap in semitones from the hand's previous note, chord size up to taught polyphony, rests only with taught rest durations, durations that fit and leave a fillable remainder, no ties, no fingering. A candidate that hits a dead end is dropped, not the batch. Required patterns and anything else are left to the rubric.

## Configuration

| Setting | Default | Notes |
|---|---|---|
| `--dart-define=MELODY_MODEL_URL` | `melody/model/` (same origin) | Directory URL or template with `{file}`. Empty string → manifest URL (GitHub Release). |
| Runtime files | `decoder.int8.onnx`, `heads.int8.onnx`, `vocab.json` (12.5 MB) | Checkpoint and configs are not downloaded. |

The app is cross-origin isolated (COEP `require-corp`, `app/web/_headers`), so a cross-origin model host must send CORS and `Cross-Origin-Resource-Policy: cross-origin`. GitHub Release downloads do not, so the deploy workflow downloads the release files (`stage_app_model.py --release`, sha256 against the manifest) into the build and the app loads them from its own origin; the app re-checks sha256 before use.

## Dev setup

```
python tools/sync_content.py
python tools/melody-model/web/fetch_ort.py --dest app/web/melody/vendor --wasm-only
python tools/melody-model/web/stage_app_model.py --release   # or --from <dir with the .onnx files>
```

`stage_app_model.py` checks each file against the manifest (vocab.json from the repo with LF endings). All three outputs are git-ignored. The deploy workflow runs the same two staging steps.

## Tests

| Test | Covers |
|---|---|
| `core` `accompany` tests | Chords follow the melody; every style × meter validates; left hand not doubled; unknown meters pass through. |
| `core` `extend_appends_targets_and_keeps_state` | Appended targets, kept states, wait cursor moves on, mismatched prefix refused. |
| `core` `check_generated_round_trips_and_fails_closed` | Taught set serde round trip; pass; untaught pitch fails; non-generated song refused; bad JSON fails. |
| `content-cli` `pack_has_a_rubric_node_and_gen_spec_for_every_spec` | Pack for the repo content; pack node feeds `check_generated`. |
| `tools/melody-model/tests/test_web.py` | Masked JS decoding obeys taught pitches, leap (including from `mask.start`), chord size, rest values, no ties/fingering. |
| `app/test/practice_mode_test.dart` | sha256 check (verified, tampered, corrupt cache, URL); rubric-failing chunk never pushed; setup choices reach model and rubric; growth on demand with the last note carried; stream ends after failures; stream page with a fake generator (badge, chunks appended on demand), error and not-yet states; setup choices and the bar-fill guard. |
