# Mic input: detector accuracy and latency

Checked: 2026-10-20, re-scored 2026-10-21, score-informed redesign 2026-10-22, noise rejection 2026-10-23, trained model 2026-10-22. Beans: piano-mlyf, piano-goe3. Decisions: [D29](../DECISIONS.md), [D32](../DECISIONS.md). Code: `app/lib/input/mic/`, `app/web/mic_worklet.js`, `app/tool/mic_eval.dart`, `tools/mic_fixtures.py`; trained model: `app/web/mic_model_core.js`, `app/web/mic_model_worker.js`, `app/web/models/`, `tools/mic-model/`.

Sources: app piano samples (`app/assets/piano`): Salamander Grand Piano V3 by Alexander Holm, CC-BY 3.0, used for the current scores; the first run (2026-10-20) used the app's earlier midi-js-soundfonts set (FluidR3_GM renders, MIT). Fixtures are generated locally and never committed. Methods: Klapuri, "Multiple fundamental frequency estimation by summing harmonic amplitudes" (ISMIR 2006) for the salience/removal idea; Bello et al., "A tutorial on onset detection in music signals" (2005) for spectral flux; [song-import.md](song-import.md) for Basic Pitch.

## Question

Can a small, dependency-free detector find beginner-level piano notes and chords from a laptop/phone mic well enough to grade lessons with core's mic window (early 150 ms, late 430 ms)? How late are notes reported?

## Options considered

| Option | Chords | Size / cost | License | Verdict |
|---|---|---|---|---|
| YIN / MPM | No (mono only) | Tiny | Algorithm, own code | Fails Piano Basics chords |
| Basic Pitch (Spotify) | Yes | ~20 MB ONNX runtime + model on web, ~0.5–1 s windows | Apache-2.0 | Later, for "My songs" (D11), too heavy/slow for live grading |
| Harmonic-salience matcher + onset gating (chosen) | Up to 4 notes | ~400 lines Dart, no deps | Own code | Ship now, measure, revisit |
| Own small onset+frame CNN, ONNX in a Web Worker (see [Trained model](#trained-model-2026-10-22-bean-piano-goe3)) | Polyphonic, 88 keys | 21k parameters, 102 KiB model, onnxruntime-web 1.27.0 (13.5 MB wasm, loaded on demand) | Own code and weights; MIT runtime; training data licences in the section | Beats DSP on every held-out set; DSP stays as fallback |

## Reference app (structure only)

Checked 2026-10-22 in the local, git-ignored teardown (`references/`), for mechanics and numbers only; no code or assets reused.

| Aspect | Reference | Ours now |
|---|---|---|
| Detection | Score-informed: the game sends expected notes; expected notes use looser thresholds, others stricter ones plus ~3 frames of persistence | Score-informed, same idea (thresholds our own) |
| Model | Small onset+frame CNN (88 keys, 16 kHz, 1024-pt FFT hop 256, log-frequency filterbank), downloaded; NMF fallback with the backing track as an extra template | DSP harmonic salience + per-note partial tracking, no model |
| Capture | Unprocessed mic source, own AGC (up to ~27 dB) and echo cancellation fed with the backing track | Raw getUserMedia, own gain (≤8×), app sound muted |
| Latency | Fixed default ~0.13 s plus per-device table and automatic calibration by correlating the backing track | Sample-timed onsets, optional visual calibration |
| UX | Asks for a quiet room, pushes headphones, troubleshooting tips; MIDI sold as "perfect recognition" | Setup panel with level meter and last note heard |

## Method

**Detector** (`NoteDetector`): spectral flux on 21 ms frames finds onsets; a 2 ms energy envelope refines the onset sample. 12 ms after the onset, an ~85 ms Hann frame (4096 samples at 48 kHz, zero-padded 2×) is compared to the frame just before the onset; only bins that grew ≥1.3× count, so ringing notes are ignored. Spectral peaks are scored per MIDI pitch 36–96 by a weighted sum of 8 partials (±45 cent windows, mild inharmonicity); the best pitch is taken, its partials removed, repeated while the next scores ≥30 % of the first. Octave/twelfth/semitone relatives of a found note are not added (octaves can't be told from partials). Releases come from the fundamental falling to 12 % of its onset level, or after 0.6 s.

**Score-informed path** (2026-10-22). The practice screen tells the detector which notes the lesson expects (wait mode: the target at the cursor and the next; play-along: pending targets from half a beat back to 0.6 s ahead). Every ~20 ms, each expected pitch's first four partials are measured on the latest 85 ms frame. It fires when all hold:
- the partial energy rose ≥3× over its minimum in the last ~170 ms;
- it is ≥12 % of the frame's strongest pitch and ≥6× the room's noise floor;
- at least two partials are sharp peaks (4× the median of their semitone band);
- it beats both semitone neighbours by 15 %.

The onset path also judges expected notes leniently (20 % of the top salience, no octave/fifth exclusion); unexpected notes there need 60 % of the top. Expected notes are reported ~20–110 ms after the onset instead of ~110 ms.

**Piano-note checks** (2026-10-23, after a student reported typing and background noise being heard as notes). A candidate must look like a struck piano string, not room noise:
- **Rings:** 30 ms after the onset its partials are still ≥3× what they were before it (short ~43 ms frame; long frame below E3, whose partials the short one can't resolve; 1.5× for a re-struck key). Clicks and knocks are gone by then. This is the check that removes most noise.
- **Pitched:** at least two of its first four partials are sharp peaks, ≥3× the median of a semitone band of at least ±5 bins (≥5× for unexpected notes).
- **Not a lower voice:** an expected note is rejected when the octave or twelfth below holds ≥80 % of its partial energy (a voice an octave down fills the same partials).
- **Unexpected notes** (when the lesson expects others) are also checked again 90 ms after the onset and only then reported, with no unexpected notes in the first 250 ms. This mirrors the reference app's holdback: an unexpected sound that has stopped by then never reaches the game.
- A 2 ms attack jump ≥2× is required; a stricter attack test (≥4×) removed no extra noise and cost melody recall.

**Fixtures** (`python tools/mic_fixtures.py`, output git-ignored, ~17 MB): 52 clips × 3 conditions = 156 WAVs, 24 kHz mono, 357 truth notes. Every third clip in list order (all kinds, all conditions) is the **held-out test set**; only the rest (**tune**) may be used to pick thresholds.

| Kind | Clips | Content |
|---|---|---|
| single | 31 | every 2nd semitone C2–C7 |
| chord | 12 | 7 triads, 5 dyads (thirds, fifths, octave, mixed hands), keys within 20 ms |
| doubled | 6 | octave and fifth doublings (C4+C5, C3–G3–C4, C4–G4–C5, …) |
| melody | 2 | Ode to Joy, Twinkle Twinkle (PD), legato with repeated notes |
| two-hands | 1 | Ode to Joy melody over held bass |
| noise | 4 | no notes, 8 s each: computer-keyboard typing (3–8 ms bright bursts), chatter (voiced buzz with gliding 100–250 Hz pitch through two formants, syllable-rate envelope), fan + 50 Hz mains hum, desk/door knocks. Every detection is a false note; in score mode the lesson waits for C–E–G the whole time |

Conditions: **clean** band-pass 120 Hz–7 kHz, 50 dB SNR; **room** + synthetic room tail (70 ms decay, direct-to-reverb +3 dB), 35 dB SNR; **noisy** same with 20 dB SNR. Notes come from the app's own piano samples (Salamander Grand, natural decay), pitch-shifted ≤1.5 semitones, random velocity 0.5–1.

**Scoring** (`cd app && dart run tool/mic_eval.dart`): a detected note-on is a hit if pitch matches and onset is within ±50 ms of a truth note (each matched once). Onset error = detected onset − truth. Report delay = time the detector had the note − truth onset. **Computed** from the algorithm on files, not measured on a device: it excludes mic hardware, browser buffering and display.

## Results

### Score-informed (the app's mode), held-out set

`dart run tool/mic_eval.dart --mode=score`, 2026-10-23 with the piano-note checks. The lesson expects the notes due from 0.3 s ago to 0.6 s ahead, as the wait-mode cursor does. P on the `all` and condition rows now includes false notes from the noise clips.

| Group | Notes | P | R | F1 | Onset error mean / p95 (ms) | Computed report delay p50 / p95 (ms) |
|---|---|---|---|---|---|---|
| all | 120 | 0.815 | 0.917 | 0.863 | 12.8 / 23 | 87 / 112 |
| clean | 40 | 0.844 | 0.950 | 0.894 | 12.1 / 23 | 87 / 110 |
| room | 40 | 0.766 | 0.900 | 0.828 | 12.4 / 19 | 88 / 116 |
| noisy | 40 | 0.837 | 0.900 | 0.867 | 13.9 / 25 | 88 / 112 |
| single | 30 | 1.000 | 1.000 | 1.000 | 12.3 / 15 | 86 / 110 |
| chord | 33 | 1.000 | 0.818 | 0.900 | 9.9 / 19 | 87 / 114 |
| doubled | 15 | 1.000 | 0.933 | 0.966 | 11.1 / 25 | 94 / 116 |
| noise | 0 | false notes: 24 in 24 s = 60.0/min | | | | |
| melody | 42 | 0.975 | 0.929 | 0.951 | 15.7 / 25 | 87 / 116 |

Tune split (includes the typing, hum and knock clips; the held-out noise clip is chatter):

| Group | Notes | P | R | F1 | Onset error mean / p95 (ms) | Computed report delay p50 / p95 (ms) |
|---|---|---|---|---|---|---|
| all | 237 | 0.881 | 0.937 | 0.908 | 12.5 / 19 | 91 / 113 |
| clean | 79 | 0.905 | 0.962 | 0.933 | 12.1 / 17 | 91 / 113 |
| room | 79 | 0.843 | 0.949 | 0.893 | 12.8 / 23 | 92 / 113 |
| noisy | 79 | 0.899 | 0.899 | 0.899 | 12.5 / 19 | 89 / 112 |
| single | 63 | 0.925 | 0.984 | 0.954 | 13.2 / 16 | 87 / 112 |
| chord | 60 | 1.000 | 0.967 | 0.983 | 10.7 / 16 | 102 / 112 |
| doubled | 33 | 1.000 | 0.909 | 0.952 | 8.4 / 15 | 107 / 112 |
| noise | 0 | false notes: 25 in 72 s = 20.8/min | | | | |
| melody | 45 | 1.000 | 0.867 | 0.929 | 14.7 / 22 | 87 / 113 |
| two-hands | 36 | 1.000 | 0.917 | 0.957 | 15.2 / 31 | 107 / 128 |

**Noise.** Before the piano-note checks the same detector reported 457–575 false notes per minute on these clips (score and blind modes), matching the student's report. Now: ~21/min on the tune split (typing, hum, knocks) and 60/min on held-out chatter. **Expected-pitch phantoms on noise** (a C/E/G reported while the lesson waits for it, which would pass the step): 7 in the 24 s of chatter (all three conditions); none from typing, hum or knocks. Steady talking near the mic can still pass a step occasionally; the setup panel asks for a quiet room, as the reference app does.

### Wrong notes, held-out set

`--mode=wrong`: the lesson expects a whole tone above what is played, so every played note goes through the strict path. **Phantom** = an expected (unplayed) note reported.

| Group | Notes | P | R | F1 | Onset error mean / p95 (ms) | Computed report delay p50 / p95 (ms) |
|---|---|---|---|---|---|---|
| all | 120 | 0.767 | 0.742 | 0.754 | 12.6 / 19 | 145 / 188 | phantom 0/120 |
| clean | 40 | 0.805 | 0.825 | 0.815 | 12.3 / 23 | 145 / 186 | phantom 0/40 |
| room | 40 | 0.725 | 0.725 | 0.725 | 12.5 / 19 | 145 / 188 | phantom 0/40 |
| noisy | 40 | 0.771 | 0.675 | 0.720 | 12.9 / 19 | 146 / 188 | phantom 0/40 |
| single | 30 | 0.933 | 0.933 | 0.933 | 12.4 / 15 | 145 / 188 | phantom 0/30 |
| chord | 33 | 1.000 | 0.545 | 0.706 | 8.5 / 16 | 145 / 186 | phantom 0/33 |
| doubled | 15 | 1.000 | 0.400 | 0.571 | 7.5 / 13 | 140 / 146 | phantom 0/15 |
| noise | 0 | false notes: 24 in 24 s = 60.0/min | | | | |
| melody | 42 | 0.974 | 0.881 | 0.925 | 15.5 / 23 | 147 / 156 | phantom 0/42 |

### Blind transcription (no expected notes)

Scored 2026-10-21, Salamander piano, `NoteDetector` defaults (γ=100, ratio 1.5, δ=3), `cd app && dart run tool/mic_eval.dart`:

test set (held out):
| Group | Notes | P | R | F1 | Onset error mean / p95 (ms) | Computed report delay p50 / p95 (ms) |
|---|---|---|---|---|---|---|
| all | 120 | 0.851 | 0.808 | 0.829 | 13.1 / 23 | 110 / 121 |
| clean | 40 | 0.895 | 0.850 | 0.872 | 12.3 / 23 | 110 / 121 |
| room | 40 | 0.850 | 0.850 | 0.850 | 14.0 / 25 | 111 / 123 |
| noisy | 40 | 0.806 | 0.725 | 0.763 | 13.0 / 19 | 111 / 116 |
| single | 30 | 0.675 | 0.900 | 0.771 | 12.2 / 15 | 110 / 112 |
| chord | 33 | 0.857 | 0.727 | 0.787 | 9.9 / 18 | 110 / 116 |
| doubled | 15 | 1.000 | 0.533 | 0.696 | 8.5 / 15 | 105 / 112 |
| melody | 42 | 1.000 | 0.905 | 0.950 | 16.8 / 25 | 112 / 123 |

tune set:
| Group | Notes | P | R | F1 | Onset error mean / p95 (ms) | Computed report delay p50 / p95 (ms) |
|---|---|---|---|---|---|---|
| all | 237 | 0.832 | 0.772 | 0.801 | 12.7 / 22 | 110 / 119 |
| clean | 79 | 0.838 | 0.848 | 0.843 | 12.3 / 19 | 110 / 117 |
| room | 79 | 0.844 | 0.823 | 0.833 | 13.3 / 25 | 111 / 122 |
| noisy | 79 | 0.810 | 0.646 | 0.718 | 12.4 / 17 | 111 / 115 |
| single | 63 | 0.654 | 0.810 | 0.723 | 12.8 / 15 | 110 / 112 |
| chord | 60 | 0.887 | 0.783 | 0.832 | 10.3 / 15 | 110 / 112 |
| doubled | 33 | 0.900 | 0.545 | 0.679 | 7.6 / 15 | 108 / 112 |
| melody | 45 | 0.949 | 0.822 | 0.881 | 15.6 / 26 | 112 / 123 |
| two-hands | 36 | 1.000 | 0.833 | 0.909 | 15.6 / 25 | 111 / 122 |

Against PRD targets (mono F1 ≥ 0.9, 3-note chords ≥ 0.75), held-out set: melodies 0.950 (above), single notes 0.771 (below: octave errors on bass), chords 0.787 (above). **Chord F1 excludes the doubling limit**: `doubled` clips (octave/fifth doublings) score F1 0.696 with recall 0.533, because a note an octave or a twelfth above an already-found note is never reported (`_related()` in `note_detector.dart`). Lessons that double notes should not rely on the mic hearing both.

The thresholds were chosen on 2026-10-21 over the previous, unsplit fixture set; the held-out split was added afterwards, and regenerating fixtures re-draws velocities and noise, so the held-out clips are new audio. Future tuning must use the `tune` split only.

**Tuning history.** The first run (2026-10-20, midi-js samples, γ=1000, ratio 1.8, δ=4) scored F1 0.891. Re-scored on the Salamander piano with those settings it fell to 0.777, noisy recall 0.330: the stronger log compression let background noise raise the flux median so real attacks stayed under the threshold. Same failure a student saw with a real mic ("didn't hear enough notes"). Grid over γ ∈ {10, 30, 100, 300, 1000}, ratio ∈ {1.3–1.8}, δ ∈ {0.5–4} picked the current values (`dart run tool/mic_eval.dart --gamma= --ratio= --delta=`).

Previous fixture set (138 clips, no split, no doubled kind):

| Settings | All F1 | Noisy R | Noisy F1 |
|---|---|---|---|
| γ1000 r1.8 δ4 (old) | 0.777 | 0.330 | 0.466 |
| γ100 r1.5 δ3 (new) | 0.865 | 0.786 | 0.806 |
| γ30 r1.5 δ1.5 | 0.867 | 0.864 | 0.840 (lower clean/chord precision) |

Onset error now has a +13 ms bias: the Salamander files start with ~13 ms of silence. Calibration absorbs a constant offset.

**Where it failed** (first run, midi-js samples, from `-v`; same classes remain):

| Error | Count (of 138 clips) | Cause |
|---|---|---|
| Bass single notes C2–A#2 reported as an upper partial (e.g. 36 → 70) | 11 clips | weak fundamentals below the 120 Hz mic band-pass; all bass outside Piano Basics range |
| One chord note missing (the 5th, or the octave in `48-60`) | 15 clips | shares partials with the root; removal halves it below 30 % (octaves are excluded by design) |
| Re-struck note in noisy melodies → its upper partials (e.g. E4 → 76/83/92) | 2 clips | growth gate passes only upper partials when the note is still loud |

Onset times are accurate (p95 ≤ 16 ms), far inside the 150/430 ms window. Notes are reported ~100 ms after the onset (analysis frame); core grades on the onset timestamp, so the lag only delays feedback, not the grade.

**End-to-end latency** (mic hardware + browser buffer + detector) was **not measured** on a real device: no physical piano or measurement rig was available. All delay figures above are computed. The calibration step measures and subtracts the total per input device; device measurement is bean piano-m4r9.

**Web demo (pipeline, not acoustics)**: Chromium in the Claude desktop browser pane, release web build. `getUserMedia` was stubbed to a `MediaStream` playing the app's own C4 sample, so the run exercises worklet → detector → core, not a microphone. Calibration finished ("247 ms"; the fake loop's phase is arbitrary) and "Find middle C" (wait mode, 4 notes) completed 4/4 by mic.

## Trained model (2026-10-22, bean piano-goe3)

The DSP detector above hit diminishing returns: users reported voices and typing heard as notes and occasional double notes, and each new rule cost recall. This section trains a small piano-only model and scores it against the DSP detector on the same held-out clips. **Every clip is synthetic or a Disklavier concert recording; nothing is a microphone recording of a student's piano in a room. Real-recording and real-device evaluation is still needed (bean piano-m4r9).**

### Data and licenses

| Set | Use | Source | License (checked on the source page, 2026-10-22) |
|---|---|---|---|
| Salamander Grand Piano V3 (Yamaha C5) | train, fixtures | [freepats.zenvoid.org](https://freepats.zenvoid.org/Piano/acoustic-grand-piano.html); the app's own `app/assets/piano` | CC-BY 3.0 |
| FreePats Upright Piano KW (Kawai upright, Zoom H1 in a living room, 2 velocity layers) | train, fixtures | same page; [github.com/freepats/upright-piano-KW](https://github.com/freepats/upright-piano-KW); pinned (sha256) in `tools/mic-model/fetch_pianos.py` | CC0 1.0 |
| FreePats YDP Grand (Zenph Yamaha Disklavier Pro multisamples from the OLPC library) | **held-out piano**: fixtures and validation only, never trained on | same page | CC-BY 3.0 |
| MAESTRO v3.0.0, 120 train files (18.1 h) | training (real Yamaha Disklavier audio, MIDI-exact labels) | [magenta.withgoogle.com/datasets/maestro](https://magenta.withgoogle.com/datasets/maestro) | **CC BY-NC-SA 4.0** |
| MAESTRO v3.0.0, 24 test-split files (2.5 h) | held-out real-audio evaluation | same | CC BY-NC-SA 4.0 |
| eSpeak NG speech (12 voices: English, Portuguese, Spanish, German, French) | held-out noise test | local install; `tools/mic-model/export_noise.py` | GPL-3.0 tool; the audio is generated locally and never committed |

Not used: VSCO-2 CE (CC0, orchestral library; its upright piano was not extracted) and the University of Iowa MIS piano (terms not checked). Salamander and KW fixture clips are rendered from the same samples the model trains on, so only the **YDP** rows measure a piano the model has never heard. All audio lives in git-ignored `data/` and `tools/mic-fixtures*/`; the repo gets code, docs and the 102 KiB model, nothing else.

**MAESTRO licence.** The shipped weights were trained partly on CC BY-NC-SA audio. The user accepted this on 2026-10-22 ("we can use MAESTRO, i dont mind"). It conflicts with `.agents/rules/content-and-licensing.md`, so [D32](../DECISIONS.md) records it as `proposed`, with the alternative: retrain on synthetic data only (`train.py --no-maestro`; not run, so its accuracy is unknown).

### Method

- **Generator** (`tools/mic-model/gen.py`, endless, 14 ms per 6 s clip): beginner-style melodies, chords, two-hand patterns, random dense notes and sparse long notes (C1-C8, velocity 0.04-1, re-strikes, optional pedal ring) rendered from Salamander and KW with random detune (±30 cents), bass inharmonicity and per-note jitter, plus random 6 s crops of MAESTRO train recordings. Mix: 45 % synthetic piano, 25 % MAESTRO, 15 % noise or voice only (labelled empty), 15 % synthetic piano under speech, humming, typing, clinks and claps. Every clip goes through a random room and mic chain: reverb (RT60 0.1-0.8 s), high/low-pass, tilt, clipping, level (peak -44 to -4 dBFS) and background noise (5-45 dB SNR). Negative generators: typing, knocks, claps, clinks, mains hum, rumble, formant speech, hummed or sung tones in the piano range, beeps.
- **Labels:** per 16 ms frame and 88 keys: onset (1 on the frame centred on the attack, its neighbours ignored) and frame (key down).
- **Model** (`model.py`): 16 kHz audio, Hann 1024 / hop 256 STFT, 264 log-frequency bands (3 per semitone), a 7-channel harmonic stack (0.5 to 6th harmonic of each band), three time-symmetric conv layers (look-ahead 3 frames = 48 ms), five causal dilated temporal convs shared across keys, a small cross-key conv and onset/frame heads. The streaming form takes one new frame plus explicit state tensors and is **numerically identical to the training form** (`tests/test_model.py`), so ONNX inference is one cheap step per 16 ms. Shipped: widths 16/16/24/24, **20,842 parameters, 3.5 M multiply-adds per step, 102 KiB ONNX** (`app/web/models/piano_net.onnx`).
- **Training** (`train.py`): AdamW, one-cycle learning rate 2e-3, 15,000 steps of 32 clips on an RTX 4070 SUPER (about 1 h); two sizes trained on the same batches. Validation: YDP and MAESTRO test clips. A first 111k-parameter model (12.8 M MAC per step) took **13-15 ms per frame in Chrome** (budget 16 ms) and was rejected; its step-10k checkpoint is only a reference.
- **Decoder** (`mic_model_core.js`, mirrored in `eval_model.py`, parity-tested): score-informed like the DSP detector. An expected pitch fires at onset ≥ 0.25. Any other pitch needs ≥ 0.9, must still sound (frame head ≥ 0.5) at the end of a 3-frame hold, and is dropped when it sits an octave below a key that just fired or is expected (octave-ghost guard). With nothing expected (free play, calibration) it uses ≥ 0.6, a 3-frame hold and no guard. A key retriggers after 6 frames; it is released when its frame probability stays under 0.3 for 3 frames, or after 0.6 s. Parameters were swept **on the synthetic tune split only**; every other set below is held out from the sweep.
- **Scoring:** same rules as the DSP scorer (`app/tool/mic_eval.dart`): pitch match, onset within ±50 ms, each truth note once. `tools/mic-model/eval_model.py` is the Python port, `report.py` runs every set and mode, `compare.py` joins the results with the DSP output. Report delay is computed (frame completed plus look-ahead), not measured on a device.

### Results

DSP per piano and per variant is scored for the first time here. Fixtures were regenerated with three pianos and four variants, so DSP numbers differ slightly from the single-piano tables above.

**synthetic fixtures (3 pianos), score mode** (held-out test split)

| Group | Notes | DSP P / R / F1 | model (shipped, 21k) P / R / F1 | model (larger, 37k) P / R / F1 |
|---|---|---|---|---|
| all | 360 | 0.929 / 0.942 / 0.935 | 0.989 / 0.992 / 0.990 | 0.986 / 0.992 / 0.989 |
| single | 90 | 0.978 / 1.000 / 0.989 | 0.978 / 1.000 / 0.989 | 0.989 / 0.989 / 0.989 |
| chord | 99 | 1.000 / 0.879 / 0.935 | 1.000 / 1.000 / 1.000 | 1.000 / 1.000 / 1.000 |
| doubled | 45 | 1.000 / 0.956 / 0.977 | 0.977 / 0.933 / 0.955 | 1.000 / 0.956 / 0.977 |
| melody | 126 | 0.992 / 0.944 / 0.967 | 0.992 / 1.000 / 0.996 | 0.984 / 1.000 / 0.992 |
| piano=salamander | 120 | 1.000 / 0.925 / 0.961 | 0.983 / 0.983 / 0.983 | 1.000 / 0.992 / 0.996 |
| piano=kw | 120 | 0.974 / 0.950 / 0.962 | 1.000 / 1.000 / 1.000 | 0.983 / 0.992 / 0.988 |
| piano=ydp | 120 | 1.000 / 0.950 / 0.974 | 0.983 / 0.992 / 0.988 | 0.992 / 0.992 / 0.992 |
| variant=plain | 216 | 0.995 / 0.926 / 0.959 | 0.995 / 1.000 / 0.998 | 0.986 / 1.000 / 0.993 |
| variant=detune | 72 | 1.000 / 0.931 / 0.964 | 1.000 / 0.972 / 0.986 | 1.000 / 0.972 / 0.986 |
| variant=inharm | 36 | 0.947 / 1.000 / 0.973 | 1.000 / 1.000 / 1.000 | 1.000 / 1.000 / 1.000 |
| variant=speaker | 36 | 1.000 / 1.000 / 1.000 | 0.921 / 0.972 / 0.946 | 1.000 / 0.972 / 0.986 |
| noise: false notes/min | | 57.5 | 0.0 | 5.0 |
| report delay p50 / p95 (ms), all | | 83 / 108 | 76 / 90 | 76 / 87 |

**synthetic fixtures (3 pianos), blind mode** (held-out test split)

| Group | Notes | DSP P / R / F1 | model (shipped, 21k) P / R / F1 | model (larger, 37k) P / R / F1 |
|---|---|---|---|---|
| all | 360 | 0.756 / 0.792 / 0.773 | 0.936 / 0.897 / 0.916 | 0.958 / 0.944 / 0.951 |
| single | 90 | 0.777 / 0.889 / 0.829 | 0.967 / 0.967 / 0.967 | 0.977 / 0.956 / 0.966 |
| chord | 99 | 0.867 / 0.727 / 0.791 | 0.923 / 0.848 / 0.884 | 0.960 / 0.980 / 0.970 |
| doubled | 45 | 1.000 / 0.644 / 0.784 | 0.929 / 0.578 / 0.712 | 1.000 / 0.689 / 0.816 |
| melody | 126 | 0.990 / 0.825 / 0.900 | 0.940 / 1.000 / 0.969 | 0.940 / 1.000 / 0.969 |
| noise: false notes/min | | 142.5 | 5.0 | 2.5 |
| report delay p50 / p95 (ms), all | | 101 / 112 | 124 / 138 | 126 / 139 |

**synthetic fixtures (3 pianos), wrong mode** (held-out test split)

| Group | Notes | DSP P / R / F1 | model (shipped, 21k) P / R / F1 | model (larger, 37k) P / R / F1 |
|---|---|---|---|---|
| all | 360 | 0.878 / 0.719 / 0.791 | 0.974 / 0.819 / 0.890 | 0.985 / 0.889 / 0.934 |
| noise: false notes/min | | 57.5 | 0.0 | 5.0 |
| report delay p50 / p95 (ms), all | | 135 / 158 | 127 / 140 | 144 / 156 |
| phantom passes (all) | | phantom 1/360 | phantom 0/360 | phantom 0/360 |

**Real piano.** 24 held-out MAESTRO test files, one random 30 s excerpt each after the first minute, as is (`clean`) and through a fixed-seed room, EQ and noise chain (`room`). Dense concert repertoire (about 12 notes/s), much harder than beginner lessons; it measures acoustics, not beginner use.

**real piano (MAESTRO test excerpts), score mode** (held-out test split)

| Group | Notes | DSP P / R / F1 | model (shipped, 21k) P / R / F1 | model (larger, 37k) P / R / F1 |
|---|---|---|---|---|
| all | 17120 | 0.830 / 0.277 / 0.415 | 0.803 / 0.801 / 0.802 | 0.811 / 0.818 / 0.814 |
| clean | 8560 | 0.836 / 0.311 / 0.453 | 0.811 / 0.826 / 0.818 | 0.821 / 0.843 / 0.832 |
| room | 8560 | 0.821 / 0.243 / 0.375 | 0.794 / 0.777 / 0.785 | 0.801 / 0.792 / 0.796 |
| report delay p50 / p95 (ms), all | | 95 / 116 | 69 / 86 | 68 / 85 |

**real piano (MAESTRO test excerpts), blind mode** (held-out test split)

| Group | Notes | DSP P / R / F1 | model (shipped, 21k) P / R / F1 | model (larger, 37k) P / R / F1 |
|---|---|---|---|---|
| all | 17120 | 0.866 / 0.202 / 0.327 | 0.914 / 0.580 / 0.709 | 0.924 / 0.619 / 0.741 |
| clean | 8560 | 0.876 / 0.231 / 0.366 | 0.921 / 0.610 / 0.734 | 0.929 / 0.651 / 0.766 |
| room | 8560 | 0.854 / 0.172 / 0.287 | 0.907 / 0.549 / 0.684 | 0.917 / 0.587 / 0.716 |
| report delay p50 / p95 (ms), all | | 101 / 117 | 119 / 134 | 118 / 132 |

**Independent noise.** Speech from eSpeak NG, a synthesizer the generator never used: 10 clips alone (80 s; every detection is a false note) and 45 piano clips (15 clips x 3 pianos) with speech mixed in, the piano 0 and 6 dB above it.

**independent noise (eSpeak speech, alone and over piano), score mode** (held-out test split)

| Group | Notes | DSP P / R / F1 | model (shipped, 21k) P / R / F1 | model (larger, 37k) P / R / F1 |
|---|---|---|---|---|
| all | 105 | 0.182 / 0.752 / 0.293 | 0.662 / 0.971 / 0.788 | 0.687 / 0.981 / 0.808 |
| mixed | 105 | 0.322 / 0.752 / 0.451 | 0.703 / 0.971 / 0.816 | 0.730 / 0.981 / 0.837 |
| speech: false notes/min | | 141.8 | 6.8 | 6.8 |
| report delay p50 / p95 (ms), all | | 81 / 106 | 76 / 92 | 76 / 91 |

**independent noise (eSpeak speech, alone and over piano), blind mode** (held-out test split)

| Group | Notes | DSP P / R / F1 | model (shipped, 21k) P / R / F1 | model (larger, 37k) P / R / F1 |
|---|---|---|---|---|
| all | 105 | 0.087 / 0.619 / 0.153 | 0.524 / 0.829 / 0.642 | 0.544 / 0.876 / 0.672 |
| mixed | 105 | 0.208 / 0.619 / 0.311 | 0.584 / 0.829 / 0.685 | 0.605 / 0.876 / 0.716 |
| speech: false notes/min | | 322.5 | 12.8 | 12.8 |
| report delay p50 / p95 (ms), all | | 99 / 111 | 128 / 143 | 128 / 136 |

**Compute.** `onnxruntime-web` 1.27.0 (single-thread wasm) in a module Web Worker, desktop Chrome in the Claude desktop browser pane: **0.65-0.84 ms per 16 ms frame on average, 1.3-1.8 ms worst**, measured on the standalone test page and inside the built app (`tools/mic-model/browser_check.py`). The worker output matches Python exactly on the two clips compared (15/15 and 3/3 notes, equal times to the millisecond). **Not measured:** any phone or low-end device. The first load downloads the 13.5 MB wasm after the mic starts; the DSP detector listens until the model is ready. A worker that falls 40 frames behind real time, errors, or cannot load switches back to DSP.

### What the numbers say, and what they don't

- Score-informed (the app's main mode) the model beats DSP on every set: synthetic F1 0.990 vs 0.935, real concert audio 0.80 vs 0.42, piano plus speech 0.82 vs 0.45. False notes on typing, chatter, hum and knocks fall from 57.5 to 0.0 per minute and on speech from 142 to 7 per minute; no phantom pass in 360 (DSP: 1).
- Blind mode (nothing expected: calibration, free play) is better than DSP in precision and recall but reports notes later (124 ms vs 101 ms at p50) because unexpected notes are held for 3 frames.
- Known failure: an **octave ghost** one octave below a real low note (a `kw` room C-E-G chord adds a C3) in blind mode; the guard removes it when notes are expected. An octave doubling is the weakest case for both detectors (score-informed recall 0.93 for the model, 0.96 for DSP).
- The larger 37k model is a little better on chords and real audio and slower; it stays in the tables to show what the small one costs (about 0.01 F1 on synthetic, 0.01-0.03 on real).
- The synthetic noise clips and the training noise share ideas (typing, formant speech, hum), so the **independent speech set is the honest noise number**: 7 false notes per minute, not 0.
- Still unproven: a real student's piano and room, phone microphones and their processing, laptop speakers, a second instrument playing along, and phone compute. MAESTRO is concert-hall Disklavier audio, not a microphone in a living room.

## Implications

- Good enough for Piano Basics (single notes and triads in C3–C6). Not proof for acoustic pianos in real rooms: fixtures are synthetic degradations of sampled pianos plus concert recordings, not microphone recordings of a student's piano.
- The trained model removes most voice and typing false notes and the chord misses the DSP rules could not fix, on every held-out set tried. That is evidence from synthetic, concert and TTS audio only; it justifies shipping it behind a switch with DSP fallback, not calling mic input solved.
- Wrong extra notes cost little in wait mode (blue splash, not penalized) and none count as misses in core; missed chord notes do block progress, so recall on chords matters most.
- Bass below C3 is unreliable for the DSP detector (the model's low register was not scored separately); lessons there should prefer MIDI until measured.

## Follow-ups

- Done (2026-10-22): small onset+frame model, our own, score-informed. Open: a real fixture set to retrain and re-score on; retrain on more MAESTRO or synthetic-only to drop the NC licence (D32); octave-ghost handling in blind mode; per-frame cost on phones; a native (non-web) runtime; a bigger model if phones allow.
- Echo cancellation against the app's own backing so play-along can keep its band in mic mode.

- Record a real fixture set (own recordings, acoustic + digital piano, phone + laptop) and re-score; measure end-to-end latency on a named device with a loopback/clap test (bean piano-m4r9).
- Safari and iOS (bean piano-czsj).
- Octave/fifth doublings: a score-informed check (expected notes known) could confirm both notes.
- Score-informed check: core knows the expected chord; test "are these pitches present?" instead of blind transcription to lift chord recall.
- Native capture (Android/iOS/desktop) with the same detector, or port it to Rust `core` once a native audio thread exists.
