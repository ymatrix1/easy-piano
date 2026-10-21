# Practice mode: generated tunes

Status: web implemented (epic `piano-c6v1`, beans `piano-urcd`, `piano-movl`, `piano-h09q`). Decision: [D28](../DECISIONS.md#d28-practice-mode-generates-tunes-in-the-app-at-runtime). Model: [melody-model.md](melody-model.md). Timings: [research/practice-mode-timing.md](../research/practice-mode-timing.md).

## What the learner sees

| Step | Behaviour |
|---|---|
| Entry | Node sheet (Learn tab) shows **Practice tune** under PLAY when the node has a generation spec. |
| First use | "Getting the tune maker ready…" with a download bar (percent of the runtime files). |
| Later uses | Files come from the browser cache; the bar jumps to 100 %. |
| Generating | "Writing a tune for this lesson…" |
| Playing | The normal stage UI (`PracticeStage`), wait mode first. A **Generated** badge stays on top. The banner says it is practice only, no stars. |
| Finished | "N of M notes", no stars. Mode chips (Wait for me / Play along), **Another one**, **Play again**, close. |
| No passing tune | "Couldn't make a tune that fits this lesson. Try again." with Retry. |
| Download/verify fails | "Couldn't load the tune maker…" with Retry. |
| Native platforms | "Practice tunes only work in the browser for now." No retry. |

## Rules (D28)

- [x] Tunes are generated on device for the chosen node.
- [x] Model files are verified by sha256 against the bundled release manifest before use, cached or not (D24).
- [x] Every tune passes `rubric::check_generated` for the node's taught set and spec before it is shown; failures are dropped, never displayed.
- [x] Retry: up to 4 rounds of 4 candidates (`PracticeService.maxAttempts`, `candidatesPerAttempt`), each bounded by `roundTimeout` (60 s), then the friendly error.
- [x] Tunes are marked `source: generated`, `generator.method: melody-model` and show the **Generated** badge. `check_generated` refuses any song without those marks.
- [x] No stars, no level or gate progress: the page never returns a result to `HomePage` and never touches `Progress`.
- [x] Nothing is saved or shared: the tune lives in page state only.
- [x] No copy check, no human review (user's decision in D28).
- [ ] Native platforms (no ONNX runtime wired yet).
- [ ] Nodes whose required pattern needs an accidental (`essentials-3/flats`, `essentials-3/amazing-grace`) get no passing tune yet ([timing note](../research/practice-mode-timing.md)).

## Pipeline

| Piece | Where | Does |
|---|---|---|
| Practice pack | `content practice-pack` (`tools/content-cli/src/practice.rs`), run by `tools/sync_content.py` into `assets/content/practice.json` | Per node: `practice` = `{taught, spec}` (rubric input), `gen` = generation spec + masks, or `unavailable` with a reason. |
| Manifest | `tools/melody-model/releases/melody-model-v1.json` → `assets/content/melody-model-v1.json` | Trust root: file sizes, sha256, decoder shape. |
| Download | `ModelStore` (`app/lib/practice/generated/model_store.dart`) | Cache Storage first (key = sha256/name), else fetch with progress; sha256 check either way; a bad cache entry is deleted and fetched again; a bad download throws `ModelIntegrityError` and is not cached. |
| Runtime | `app/web/melody/practice.js` (loaded on demand via `window.epMelodyImport`) | onnxruntime-web 1.30.0 (wasm, up to 4 threads when cross-origin isolated), KV-cached decoder + heads, `melody.js` masked decoding and decoding. |
| Gate | `PracticeService` → bridge `check_generated` → `core::rubric::check_generated` | Picks the first candidate (best mean log p) with no rubric errors. |
| UI | `GeneratedPracticePage` | States above. |

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
| `core` `check_generated_round_trips_and_fails_closed` | Taught set serde round trip; pass; untaught pitch fails; non-generated song refused; bad JSON fails. |
| `content-cli` `pack_has_a_rubric_node_and_gen_spec_for_every_spec` | Pack for the repo content; pack node feeds `check_generated`. |
| `tools/melody-model/tests/test_web.py` | Masked JS decoding obeys taught pitches, leap, chord size, rest values, no ties/fingering. |
| `app/test/practice_mode_test.dart` | sha256 check (verified, tampered, corrupt cache, URL), rubric-failing tune never returned, give-up path, page flow with a fake generator, error and not-yet states. |
