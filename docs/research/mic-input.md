# Mic input: detector accuracy and latency

Checked: 2026-10-20, re-scored 2026-10-21, score-informed redesign 2026-10-22. Bean: piano-mlyf. Decision: [D29](../DECISIONS.md). Code: `app/lib/input/mic/`, `app/web/mic_worklet.js`, `app/tool/mic_eval.dart`, `tools/mic_fixtures.py`.

Sources: app piano samples (`app/assets/piano`): Salamander Grand Piano V3 by Alexander Holm, CC-BY 3.0, used for the current scores; the first run (2026-10-20) used the app's earlier midi-js-soundfonts set (FluidR3_GM renders, MIT). Fixtures are generated locally and never committed. Methods: Klapuri, "Multiple fundamental frequency estimation by summing harmonic amplitudes" (ISMIR 2006) for the salience/removal idea; Bello et al., "A tutorial on onset detection in music signals" (2005) for spectral flux; [song-import.md](song-import.md) for Basic Pitch.

## Question

Can a small, dependency-free detector find beginner-level piano notes and chords from a laptop/phone mic well enough to grade lessons with core's mic window (early 150 ms, late 430 ms)? How late are notes reported?

## Options considered

| Option | Chords | Size / cost | License | Verdict |
|---|---|---|---|---|
| YIN / MPM | No (mono only) | Tiny | Algorithm, own code | Fails Piano Basics chords |
| Basic Pitch (Spotify) | Yes | ~20 MB ONNX runtime + model on web, ~0.5–1 s windows | Apache-2.0 | Later, for "My songs" (D11), too heavy/slow for live grading |
| Harmonic-salience matcher + onset gating (chosen) | Up to 4 notes | ~400 lines Dart, no deps | Own code | Ship now, measure, revisit |

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

**Fixtures** (`python tools/mic_fixtures.py`, output git-ignored, ~17 MB): 52 clips × 3 conditions = 156 WAVs, 24 kHz mono, 357 truth notes. Every third clip in list order (all kinds, all conditions) is the **held-out test set**; only the rest (**tune**) may be used to pick thresholds.

| Kind | Clips | Content |
|---|---|---|
| single | 31 | every 2nd semitone C2–C7 |
| chord | 12 | 7 triads, 5 dyads (thirds, fifths, octave, mixed hands), keys within 20 ms |
| doubled | 6 | octave and fifth doublings (C4+C5, C3–G3–C4, C4–G4–C5, …) |
| melody | 2 | Ode to Joy, Twinkle Twinkle (PD), legato with repeated notes |
| two-hands | 1 | Ode to Joy melody over held bass |

Conditions: **clean** band-pass 120 Hz–7 kHz, 50 dB SNR; **room** + synthetic room tail (70 ms decay, direct-to-reverb +3 dB), 35 dB SNR; **noisy** same with 20 dB SNR. Notes come from the app's own piano samples (Salamander Grand, natural decay), pitch-shifted ≤1.5 semitones, random velocity 0.5–1.

**Scoring** (`cd app && dart run tool/mic_eval.dart`): a detected note-on is a hit if pitch matches and onset is within ±50 ms of a truth note (each matched once). Onset error = detected onset − truth. Report delay = time the detector had the note − truth onset. **Computed** from the algorithm on files, not measured on a device: it excludes mic hardware, browser buffering and display.

## Results

### Score-informed (the app's mode), held-out set

`dart run tool/mic_eval.dart --mode=score`. The lesson expects the notes due from 0.3 s ago to 0.6 s ahead, as the wait-mode cursor does.

| Group | Notes | P | R | F1 | Onset error mean / p95 (ms) | Computed report delay p50 / p95 (ms) |
|---|---|---|---|---|---|---|
| all | 120 | 0.926 | 0.942 | 0.934 | 13.3 / 23 | 85 / 112 |
| clean | 40 | 0.974 | 0.950 | 0.962 | 12.9 / 25 | 81 / 110 |
| room | 40 | 0.923 | 0.900 | 0.911 | 14.0 / 32 | 86 / 112 |
| noisy | 40 | 0.886 | 0.975 | 0.929 | 12.9 / 23 | 87 / 112 |
| single | 30 | 0.833 | 1.000 | 0.909 | 12.3 / 15 | 69 / 112 |
| chord | 33 | 1.000 | 0.879 | 0.935 | 9.3 / 18 | 103 / 116 |
| doubled | 15 | 0.933 | 0.933 | 0.933 | 10.0 / 18 | 95 / 108 |
| melody | 42 | 0.952 | 0.952 | 0.952 | 18.0 / 43 | 73 / 103 |

### Wrong notes, held-out set

`--mode=wrong`: the lesson expects a whole tone above what is played, so every played note goes through the strict path. **Phantom** = an expected (unplayed) note reported, which would pass a step the student did not play.

| Group | Notes | P | R | F1 | Onset error mean / p95 (ms) | Computed report delay p50 / p95 (ms) |
|---|---|---|---|---|---|---|
| all | 120 | 0.895 | 0.783 | 0.836 | 13.0 / 23 | 110 / 121 | phantom 0/120 |
| clean | 40 | 0.944 | 0.850 | 0.895 | 12.4 / 23 | 110 / 121 | phantom 0/40 |
| room | 40 | 0.914 | 0.800 | 0.853 | 13.9 / 25 | 110 / 123 | phantom 0/40 |
| noisy | 40 | 0.824 | 0.700 | 0.757 | 12.9 / 19 | 110 / 116 | phantom 0/40 |
| single | 30 | 0.711 | 0.900 | 0.794 | 12.2 / 15 | 110 / 112 | phantom 0/30 |
| chord | 33 | 1.000 | 0.606 | 0.755 | 8.9 / 18 | 109 / 116 | phantom 0/33 |
| doubled | 15 | 1.000 | 0.533 | 0.696 | 8.5 / 15 | 105 / 112 | phantom 0/15 |
| melody | 42 | 1.000 | 0.929 | 0.963 | 16.6 / 25 | 112 / 123 | phantom 0/42 |

Phantom passes: 0/120 held-out, 5/237 on the tune split (wrong mode, all conditions).

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

## Implications

- Good enough for Piano Basics (single notes and triads in C3–C6). Not proof for acoustic pianos in real rooms: fixtures are synthetic degradations of one sampled piano.
- Wrong extra notes cost little in wait mode (blue splash, not penalized) and none count as misses in core; missed chord notes do block progress, so recall on chords matters most.
- Bass below C3 is unreliable; lessons there should prefer MIDI until improved.

## Follow-ups

- Small onset+frame model (Basic Pitch class, Apache-2.0, or our own trained on synthetic Salamander data) as a second engine, score-informed the same way.
- Echo cancellation against the app's own backing so play-along can keep its band in mic mode.

- Record a real fixture set (own recordings, acoustic + digital piano, phone + laptop) and re-score; measure end-to-end latency on a named device with a loopback/clap test (bean piano-m4r9).
- Safari and iOS (bean piano-czsj).
- Octave/fifth doublings: a score-informed check (expected notes known) could confirm both notes.
- Score-informed check: core knows the expected chord; test "are these pitches present?" instead of blind transcription to lift chord recall.
- Native capture (Android/iOS/desktop) with the same detector, or port it to Rust `core` once a native audio thread exists.
