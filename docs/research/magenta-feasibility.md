# Magenta.js feasibility for rule-limited melodies

Checked: 2026-10-20, rerun 2026-10-21. Bean: piano-reo2. Setup: Windows 11, Node 24.6.0 (pinned in `.nvmrc` and `engines`), npm 11.5.1, `@magenta/music` 1.23.1 (lockfile; pulls `@tensorflow/tfjs` 2.8.6), tfjs pure-JS `cpu` backend (no `tfjs-node`). Code: `tools/spikes/magenta/`. Run log and summaries: `tools/spikes/magenta/results/`.

Sources:

- [magenta-js](https://github.com/magenta/magenta-js), [LICENSE](https://github.com/magenta/magenta-js/blob/master/LICENSE) (Apache-2.0, "Copyright 2018 The Magenta Team").
- [Checkpoint list](https://github.com/magenta/magenta-js/blob/master/music/checkpoints/README.md): `basic_rnn` "A 36-class onehot MelodyRNN model. Converted from …basic_rnn.mag"; `melody_rnn` "A 128-class onehot MelodyRNN model"; `chord_pitches_improv` "conditioned on chords … Converted from …chord_pitches_improv.mag". No license line.
- [Melody RNN README](https://github.com/magenta/magenta/blob/main/magenta/models/melody_rnn/README.md): pre-trained "on thousands of MIDI files"; no list, no weights license.
- [Improv RNN README](https://github.com/magenta/magenta/blob/main/magenta/models/improv_rnn/README.md): trained "on lead sheets in MusicXML format"; no list, no weights license.
- Checkpoint folders on `storage.googleapis.com/magentadata/js/checkpoints/music_rnn/<id>/`: `config.json`, `weights_manifest.json`, shards; `…/basic_rnn/LICENSE` returns HTTP 404 (checked 2026-10-20 with `curl -w "%{http_code}"`).
- The minified `MusicRNN.sampleRnn` in `node_modules/@magenta/music/es6/music_rnn.js`.

## Question

Can Magenta.js MusicRNN / ImprovRNN produce melodies that obey a course level's rules (Essentials I example: C4–G4, eighth/quarter/half, 8 bars 4/4, max leap a fifth, end on C) in our song JSON, at acceptable cost and with clean licenses?

## Setup on Windows

| Step | Result |
|---|---|
| `npm install` (`@magenta/music@1.23.1`, exact pin) | 170 packages, 31 s. No native builds. |
| `require('@magenta/music/node/music_rnn')` | Fails on Node 24: Tone.js ESM build does not resolve (`ERR_MODULE_NOT_FOUND ... tone\build\esm\core\Global`). Fixed by `stub-tone.js`, which resolves `tone` to an empty module (we never play audio). |
| Checkpoint load | 1–3 s each over HTTPS from GCS; one run hit `ECONNABORTED`, so loads and hash downloads retry 3 times. |
| Checkpoint pin | URLs are unversioned, so `checkpoints.lock.json` records a sha256 per file and one digest per checkpoint; every run re-downloads and checks them (`--lock` rewrites the file). |
| tfjs backend | Pure JS CPU; tfjs prints a hint to install `tfjs-node`. Not needed at this size. |

Total setup time about 20 min. No Python, no CUDA.

| Checkpoint | sha256 (digest over `file:sha256` lines) |
|---|---|
| `basic_rnn` | `584ef921b7cdf41a7e5709d3a4a2a3d2bd4a7070b683b099d5b74918eb2ae71f` |
| `melody_rnn` | `721cb2ab0990cf36be154873c7ca9655490b44362a04ef013b32e3a31fbc4332` |
| `chord_pitches_improv` | `f9a2b7a8623f819e89ba011523ce46166650a4cb8475f09a8785ae810fd04318` |

## Constrained sampling

The public API (`continueSequence(seq, steps, temperature, chordProgression)`) has no hook for masking; it samples inside `sampleRnn` with `tf.multinomial`. The model's fields are plain JS properties (`lstmCells`, `lstmFcW`, `lstmFcB`, `biasShapes`, `chordEncoder`, `dataConverter`), so `generate()` is a modified copy of the 30-line `sampleRnn` loop (Apache-2.0; modification notice in the file header) that samples on the CPU with a seeded PRNG after setting disallowed logits to −∞. It depends on private fields, so the version pin matters.

Event layout (MelodyConverter, 16th-note steps): 0 = hold, 1 = note off, 2+ = pitch − minPitch. Mask per step:

- Onset only when the current note or rest has an allowed length; pitch in the level's set and within the max leap of the last sounded note. From bar 7 on, only pitches within a leap of the final C (otherwise the forced ending can be unreachable).
- Hold only if some allowed duration can still finish before the next barline.
- Rest (note-off) only after a note, only if an allowed rest length fits before the barline.
- Primer: one C4 step. Last half note forced to C4 (step 120).

### Checks (`node test.js`)

| Check | Result (2026-10-21, `results/run-2026-10-21.log`) |
|---|---|
| Equivalence: our loop, greedy and unmasked, vs the library's `continueSequenceAndReturnProbabilities` (same primer, 127 steps) | max \|p_lib − p_ours\| = 7.4e-8 (`basic_rnn`), 8.2e-8 (`melody_rnn`), 7.9e-8 (`chord_pitches_improv`, with chords); argmax mismatches 0 |
| Same seed twice (`chord_pitches_improv`, e3, seed 7, masked, temp 1) | 128 events identical |
| Mask property: 5000 tunes per level sampled from random logits through the mask | 0 violations, no dead ends (e1 and e3) |
| Full rerun vs first run (2026-10-20) | Same scores and violation counts for every checkpoint; only ms/tune differs |

Sampling at temperature 1 uses our PRNG, not `tf.multinomial`, so sampled tunes can't match the library's tune for tune; the equivalence check covers the distribution the sampler draws from.

### Ranking

Score: 0.35 stepwise share, 0.2 phrase repetition (bars 1–2 back in 5–6, exact or rhythm), 0.15 ending (penultimate D/E/B best), 0.1 eighth-note share, 0.2 variety (half distinct pitches out of 5, half span out of a fifth), minus a penalty for > 30 % repeated notes and 2 × rest share above 15 %. Fewer than 4 distinct pitches or a span under a fourth scores 0.

The first ranker (no variety term, no rest cap) kept looping tunes: in the viewer, 3 of 15 kept e3 tunes were one note plus rests (the top `basic_rnn` tune was C4 + quarter rest for eight bars), because exact bar repetition scored full marks. The current ranker drops them.

### Output

Top 5 per checkpoint as song JSON in `out/` (git-ignored): fingering per bar from the first five-finger position (C, G, F, D) that covers its notes, else the bar's span over 1–5 (readable, not teaching-grade); `source: "generated"`; `generator` uses only the fields in `core/src/song.rs` `Generator`:

```json
"generator": {
  "method": "magenta",
  "tool": "@magenta/music@1.23.1 tools/spikes/magenta/generate.js",
  "model": "https://storage.googleapis.com/magentadata/js/checkpoints/music_rnn/chord_pitches_improv#sha256=f9a2b7a8…",
  "seed": 12,
  "prompt_ref": "level=e1;temperature=1;chords=C-F-G-C-C-F-G-C;ranker=v2;score=0.847"
}
```

`license` and `composition_license` are `NOASSERTION`: the weights have no stated license, so we claim none (see Licenses). `content lint` rejects that, on purpose, so the files can't land in `content/`.

## Results

Temperature 1.0; 20 masked tunes and 200 plain tunes per checkpoint and level; seeds 1–20 (masked), 100001–100200 (plain). Numbers from `results/summary-*.json` (2026-10-21 run). ms/tune varies by up to about 1 s between runs on the same machine (CPU contention); counts and scores do not.

**Essentials I (`--level e1`):** C4–G4, eighth/quarter/half, no rests, max leap a fifth; ImprovRNN chords C F G C C F G C (one per bar).

| Checkpoint | Classes | Load | Masked: ms/tune | Masked: violations | Mean score (20) | Best | Plain: ms/tune | Plain: accepted |
|---|---|---|---|---|---|---|---|---|
| `basic_rnn` | 38 (MIDI 48–83) | 1.7 s | 2440 | 0 in 20 | 0.474 | 0.830 | 2508 | 0/200 |
| `melody_rnn` | 130 (MIDI 0–127) | 1.8 s | 3507 | 0 in 20 | 0.501 | 0.828 | 1712 | 0/200 |
| `chord_pitches_improv` | 38 (MIDI 48–83) | 0.8 s | 451 | 0 in 20 | 0.689 | 0.847 | 496 | 0/200 |

**Harder treble level (`--level e3`):** C4–C5 plus F#4 and Bb4, eighth/quarter/dotted quarter/half, quarter and half rests (never two in a row), max leap a sixth; ImprovRNN chords C Am Dm G C F G7 C.

| Checkpoint | Load | Masked: ms/tune | Masked: violations | Mean score (20) | Best | Plain: ms/tune | Plain: accepted |
|---|---|---|---|---|---|---|---|
| `basic_rnn` | 2.9 s | 1337 | 0 in 20 | 0.529 | 0.770 | 1287 | 0/200 |
| `melody_rnn` | 2.0 s | 1390 | 0 in 20 | 0.452 | 0.830 | 1290 | 0/200 |
| `chord_pitches_improv` | 0.6 s | 455 | 0 in 20 | 0.643 | 0.736 | 514 | 0/200 |

Kept top 5 per checkpoint: 4–9 distinct pitches, span 5–12 semitones, rest share ≤ 0.06. The e3 tunes use F#, Bb, rests and dotted quarters.

Plain-sampling violations out of 200 (a tune can break several):

| Level | Checkpoint | pitch | duration | rest | ending | leap | barline |
|---|---|---|---|---|---|---|---|
| e1 | `basic_rnn` | 182 | 180 | 159 | 175 | 101 | 82 |
| e1 | `melody_rnn` | 195 | 185 | 143 | 176 | 82 | 106 |
| e1 | `chord_pitches_improv` | 194 | 187 | 108 | 143 | 76 | 10 |
| e3 | `basic_rnn` | 155 | 174 | 154 | 175 | 67 | 82 |
| e3 | `melody_rnn` | 191 | 172 | 122 | 176 | 42 | 106 |
| e3 | `chord_pitches_improv` | 152 | 163 | 51 | 159 | 47 | 8 |

Post-hoc rejection is useless: 0 of 1200 accepted. Masked sampling: 0 violations in 120 model tunes (the script throws on any), and the mask property was verified by simulation (5000 random-logit tunes per level, 0 violations).

**Lint** (`results/lint-2026-10-21.txt`): current `main` (960ef8c) `content/` plus the 30 kept tunes. `cargo run -- lint`: exit 1, 90 errors, all license: per tune `license NOASSERTION not in [...]`, `composition_license NOASSERTION not in [...]`, `generated songs must be CC0-1.0, not NOASSERTION`. No generator, bar, pitch or finger errors. As a control, the same copy with the license fields set to CC0-1.0 lints `ok` (exit 0), so the `generator` object matches the schema.

### Viewer

`viewer.html` draws every tune in `out/` on a treble staff (SVG, own renderer: clef, ledger lines, accidentals, dots, flags, rests, fingering), plays it with a WebAudio triangle synth at the song's bpm, filters by level and has a **Show model** toggle. Toggle off: tunes shuffled, only level and bpm shown. On: checkpoint, seed and `prompt_ref`. Run `node generate.js --level e3`, then the `magenta-viewer` launch config (`python -m http.server 8771 --directory tools/spikes/magenta`) and open `/viewer.html`.

Listening impression (not a test): ImprovRNN tunes follow the chords (bar 1 over C: `C4 E4 G4 G4`); the unconditioned models wander more and lean on C–G leaps. Quality needs the blind listening test.

## Licenses

| Item | License | Source |
|---|---|---|
| `@magenta/music` code | Apache-2.0 | [magenta-js LICENSE](https://github.com/magenta/magenta-js/blob/master/LICENSE). `generate.js` modifies `sampleRnn` and says so in its header. |
| `basic_rnn`, `chord_pitches_improv` weights | **None stated** | [Checkpoint README](https://github.com/magenta/magenta-js/blob/master/music/checkpoints/README.md) lists them as converted `.mag` bundles with no license; `…/music_rnn/basic_rnn/LICENSE` is HTTP 404. |
| `melody_rnn` weights | **None stated** | Same README; no source bundle or training data named. |
| Training data | Unknown | [Melody RNN README](https://github.com/magenta/magenta/blob/main/magenta/models/melody_rnn/README.md) ("thousands of MIDI files"), [Improv RNN README](https://github.com/magenta/magenta/blob/main/magenta/models/improv_rnn/README.md) (MusicXML lead sheets); no lists. Could contain copyrighted melodies. |
| Our outputs | `NOASSERTION` | No CC0 claim while the weights license and training data are unknown. Spike/local only. |

No sample outputs are committed; they stay in `tools/spikes/magenta/out/` (git-ignored). Rerun with `npm install && npm test && node generate.js --level e1`.

## Implications

- Technically feasible: setup is short, tunes take 0.5–3.5 s each on CPU, and masked sampling had 0 violations in 120 tunes, with the mask property verified by simulation. Rejection sampling is not an option (0/1200).
- Masking needs private model fields; a Magenta.js update could break it. Magenta.js is in low maintenance (tfjs 2.x, Tone.js ESM break on Node 24).
- The blocker is licensing, not engineering: weights have no license and the training corpus is undisclosed. That conflicts with our clean-room rule and with piano-ze9t's out-of-scope note ("neural models with unclear weight licenses").
- If ever used, generated tunes need the melody similarity check against a large corpus before any license claim.
- ImprovRNN with a chord progression is the fastest and has the highest mean score at both levels; the mask does the level-fitting, the model only picks among allowed notes.
- A ranker must punish loops explicitly; repetition alone rewards degenerate output.

## Follow-ups

- Use the viewer or feed 3–5 masked tunes per model into the blind listening test (local only) to see if they beat the rules generator.
- Ask Magenta (GitHub issue) for the checkpoint license and training-data provenance; until answered, keep Magenta out of shipped content.
- If quality wins, consider the same masking on a model we train ourselves on CC0/PD melodies, so weights and data are clean.
