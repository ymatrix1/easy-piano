# Magenta.js feasibility for rule-limited melodies

Checked: 2026-10-20. Bean: piano-reo2. Setup: Windows 11, Node 24.6.0, npm 11.5.1, `@magenta/music` 1.23.1 (pulls `@tensorflow/tfjs` 2.8.6), tfjs pure-JS `cpu` backend (no `tfjs-node`). Code: `tools/spikes/magenta/`.

Sources: [magenta-js](https://github.com/magenta/magenta-js) (Apache-2.0, `LICENSE`), [checkpoint list](https://github.com/magenta/magenta-js/blob/master/music/checkpoints/README.md), [Melody RNN README](https://github.com/magenta/magenta/blob/main/magenta/models/melody_rnn/README.md), [Improv RNN README](https://github.com/magenta/magenta/blob/main/magenta/models/improv_rnn/README.md), checkpoint `config.json` files on `storage.googleapis.com/magentadata/js/checkpoints/music_rnn/`, the minified `MusicRNN.sampleRnn` in `node_modules/@magenta/music/es6/music_rnn.js`.

## Question

Can Magenta.js MusicRNN / ImprovRNN produce melodies that obey a course level's rules (Essentials I example: C4–G4, eighth/quarter/half, 8 bars 4/4, max leap a fifth, end on C) in our song JSON, at acceptable cost and with clean licenses?

## Setup on Windows

| Step | Result |
|---|---|
| `npm install` (`@magenta/music@1.23.1`, exact pin) | 170 packages, 31 s. No native builds. |
| `require('@magenta/music/node/music_rnn')` | Fails on Node 24: Tone.js ESM build does not resolve (`ERR_MODULE_NOT_FOUND ... tone\build\esm\core\Global`). Fixed by `stub-tone.js`, which resolves `tone` to an empty module (we never play audio). |
| Checkpoint load | 1–3 s each over HTTPS from GCS; one run hit `ECONNABORTED`, so the script retries 3 times. |
| tfjs backend | Pure JS CPU; tfjs prints a hint to install `tfjs-node`. Not needed at this size. |

Total setup time about 20 min. No Python, no CUDA.

## Constrained sampling

The public API (`continueSequence(seq, steps, temperature, chordProgression)`) has no hook for masking; it samples inside `sampleRnn` with `tf.multinomial`. The model's fields are plain JS properties (`lstmCells`, `lstmFcW`, `lstmFcB`, `biasShapes`, `chordEncoder`, `dataConverter`), so `generate.js` re-implements the 30-line loop (adapted from `sampleRnn`, Apache-2.0) and samples on the CPU after setting disallowed logits to −∞. This depends on private fields, so the version pin matters.

Event layout (MelodyConverter, 16th-note steps): 0 = hold, 1 = note off, 2+ = pitch − minPitch. Mask per step:

- Onset only when the current note has length 2, 4 or 8 steps; pitch in {C4 D4 E4 F4 G4} and within 7 semitones of the previous note.
- Hold only if some allowed duration can still finish before the next barline.
- No note-off (no rests). Primer: one C4 step. Last half note forced to C4 (step 120).

Ranking score (0–1): 0.45 stepwise share, 0.25 phrase repetition (bars 1–2 back in 5–6, exact or rhythm), 0.2 ending (penultimate D/E best), 0.1 eighth-note share, minus a penalty for > 30 % repeated notes. Output: top 5 per checkpoint as song JSON with C-position fingering, `source: "generated"`, `license: "CC0-1.0"` and a `generator` object (method, tool, tool_version, checkpoint URL, seed, temperature, chords, rules, score).

## Results

Temperature 1.0; 20 masked tunes and 200 plain tunes per checkpoint; seeds 1–20 (masked), 100001–100200 (plain).

| Checkpoint | Classes | Load | Masked: ms/tune | Masked: rule pass | Mean score | Best score | Plain: ms/tune | Plain: accepted |
|---|---|---|---|---|---|---|---|---|
| `basic_rnn` | 38 (MIDI 48–83) | 2.0 s | 1619 | 20/20 | 0.526 | 0.785 | 1774 | 0/200 |
| `melody_rnn` | 130 (MIDI 0–127) | 2.9 s | 1868 | 20/20 | 0.614 | 0.804 | 1907 | 0/200 |
| `chord_pitches_improv` (C F G C C F G C, one per bar) | 38 (MIDI 48–83) | 2.4 s | 1224 | 20/20 | 0.619 | 0.807 | 654 | 0/200 |

Plain-sampling violations out of 200 (a tune can break several):

| Checkpoint | pitch | duration | rest | ending | leap | barline |
|---|---|---|---|---|---|---|
| `basic_rnn` | 182 | 181 | 159 | 175 | 101 | 82 |
| `melody_rnn` | 195 | 185 | 143 | 176 | 82 | 106 |
| `chord_pitches_improv` | 194 | 187 | 108 | 143 | 76 | 10 |

Post-hoc rejection is useless: 0 of 600 accepted. Masked sampling meets every rule by construction (the script throws if a masked tune fails the post-hoc check; none did).

All 15 written songs pass `content lint` (bar sums, pitch range, finger counts) except `source_url required unless source is original`, which the `generated` source work in another session removes. Command: copy `content/` plus `out/gen-*.json` to a scratch folder, `cargo run -- lint <scratch>`: 15 errors, all that one message.

### Harder treble level (`--level e3`)

Rules: C4–C5 plus F#4 and Bb4, eighth / quarter / dotted quarter / half, quarter and half rests (never two in a row), max leap a sixth, end on C4; ImprovRNN chords C Am Dm G C F G7 C. One mask fix was needed: with a sixth allowed, a note on C5 could make the forced final C4 unreachable, so from bar 7 on only pitches within a sixth of C4 are allowed.

| Checkpoint | Masked: ms/tune | Masked: rule pass | Mean score | Best score | Plain: ms/tune | Plain: accepted |
|---|---|---|---|---|---|---|
| `basic_rnn` | 3322 | 20/20 | 0.530 | 0.705 | 3429 | 0/200 |
| `melody_rnn` | 1141 | 20/20 | 0.598 | 0.828 | 1492 | 0/200 |
| `chord_pitches_improv` | 627 | 20/20 | 0.562 | 0.672 | 665 | 0/200 |

Seen in the viewer: 3 of the 15 kept e3 tunes collapse into a loop (basic_rnn seed 17, the top basic_rnn tune, is C4 + quarter rest eight bars long; basic_rnn 14 and melody_rnn 19 are close). The model loops, and the ranking rewards it because exact bar repetition scores full marks. A real ranker needs a pitch-variety / range term and a cap on rests. The 15 written e3 songs use 25 F#, 18 Bb, 22 rests and 8 dotted quarters, and pass `content lint` apart from the same `source_url` error. Fingering: each bar takes the first five-finger position (C, G, F, D) that covers its notes, else spreads its span over 1–5; good enough to read, not teaching-grade. Rerunning `--level e1` reproduced the e1 table's scores exactly (same seeds); ms/tune varied by up to 0.5 s between runs.

### Viewer

`viewer.html` draws every tune in `out/` on a treble staff (SVG, own renderer: clef, ledger lines, accidentals, dots, flags, rests, fingering), plays it with a WebAudio triangle synth at the song's bpm, filters by level and has a **Show model** toggle. With the toggle off, tunes are shuffled and only show level and bpm; on, each shows checkpoint, seed, score and chords. Run: `node generate.js --level e3`, then the `magenta-viewer` launch config (`python -m http.server 8771 --directory tools/spikes/magenta`) and open `/viewer.html`.

Listening impression (not a test): ImprovRNN tunes follow the chords (bar 1 over C: `C4 E4 G4 G4`), the unconditioned models wander more and lean on C–G leaps. Quality needs the blind listening test.

## Licenses

| Item | License | Notes |
|---|---|---|
| `@magenta/music` code | Apache-2.0 | `LICENSE` in magenta-js. `generate.js` adapts `sampleRnn` from it. |
| `basic_rnn`, `chord_pitches_improv` weights | **None stated** | Converted from `basic_rnn.mag` / `chord_pitches_improv.mag`. Checkpoint README, bucket and `.mag` pages give no license (`LICENSE` in the checkpoint folder: HTTP 404). |
| `melody_rnn` weights | **None stated** | No source or training data given. |
| Training data | Unknown | Melody RNN: "thousands of MIDI files"; Improv RNN: lead sheets (MusicXML), no list. Could contain copyrighted melodies. |
| Our outputs | We tag CC0-1.0 | Only defensible if weights may be used and outputs don't reproduce training melodies. Neither is shown. |

Because no weight license is stated, **no sample outputs are committed**; they stay in `tools/spikes/magenta/out/` (git-ignored). Rerun with `npm install && node generate.js`.

## Implications

- Technically feasible: setup is short, tunes take 0.6–1.9 s each on CPU, and logit masking gives 100 % rule compliance. Rejection sampling is not an option (0/600).
- Masking needs private model fields; a Magenta.js update could break it. Magenta.js is in low maintenance (tfjs 2.x, Tone.js ESM break on Node 24).
- The blocker is licensing, not engineering: weights have no license and the training corpus is undisclosed. That conflicts with our clean-room rule and with piano-ze9t's out-of-scope note ("neural models with unclear weight licenses").
- If used at all, generated tunes need the melody similarity check (other session) against a large corpus before any CC0 claim.
- ImprovRNN with a chord progression gives the most coherent results of the three; the mask does the level-fitting, the model only picks among allowed notes.

## Follow-ups

- Use the viewer or feed 3–5 masked tunes per model into the blind listening test (local only) to see if they beat the rules generator; regenerate with `node generate.js --only chord_pitches_improv`.
- Ask Magenta (GitHub issue) for the checkpoint license and training-data provenance; until answered, keep Magenta out of shipped content.
- If quality wins, consider the same masking idea on a model we train ourselves on CC0/PD melodies, so weights and data are clean.
