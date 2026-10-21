# Mic input: detector accuracy and latency

Checked: 2026-10-20. Bean: piano-mlyf. Decision: [D18](../DECISIONS.md). Code: `app/lib/input/mic/`, `app/web/mic_worklet.js`, `app/tool/mic_eval.dart`, `tools/mic_fixtures.py`.

Sources: app piano samples (`app/assets/piano`: Salamander Grand Piano V3, CC-BY 3.0, since PR #49; first run used the earlier midi-js-soundfonts set, MIT); Klapuri, "Multiple fundamental frequency estimation by summing harmonic amplitudes" (ISMIR 2006) for the salience/removal idea; Bello et al., "A tutorial on onset detection in music signals" (2005) for spectral flux; [song-import.md](song-import.md) for Basic Pitch.

## Question

Can a small, dependency-free detector find beginner-level piano notes and chords from a laptop/phone mic well enough to grade lessons with core's mic window (early 150 ms, late 430 ms)? How late are notes reported?

## Options considered

| Option | Chords | Size / cost | License | Verdict |
|---|---|---|---|---|
| YIN / MPM | No (mono only) | Tiny | Algorithm, own code | Fails Piano Basics chords |
| Basic Pitch (Spotify) | Yes | ~20 MB ONNX runtime + model on web, ~0.5–1 s windows | Apache-2.0 | Later, for "My songs" (D11), too heavy/slow for live grading |
| Harmonic-salience matcher + onset gating (chosen) | Up to 4 notes | ~400 lines Dart, no deps | Own code | Ship now, measure, revisit |

## Method

**Detector** (`NoteDetector`): spectral flux on 21 ms frames finds onsets; a 2 ms energy envelope refines the onset sample. 12 ms after the onset, an ~85 ms Hann frame (4096 samples at 48 kHz, zero-padded 2×) is compared to the frame just before the onset; only bins that grew ≥1.3× count, so ringing notes are ignored. Spectral peaks are scored per MIDI pitch 36–96 by a weighted sum of 8 partials (±45 cent windows, mild inharmonicity); the best pitch is taken, its partials removed, repeated while the next scores ≥30 % of the first. Octave/twelfth/semitone relatives of a found note are not added (octaves can't be told from partials). Releases come from the fundamental falling to 12 % of its onset level.

**Fixtures** (`python tools/mic_fixtures.py`, output git-ignored, ~15 MB): 46 clips × 3 conditions = 138 WAVs, 24 kHz mono, 309 truth notes.

| Kind | Clips | Content |
|---|---|---|
| single | 31 | every 2nd semitone C2–C7 |
| chord | 12 | 7 triads, 5 dyads (thirds, fifths, octave, mixed hands), keys within 20 ms |
| melody | 2 | Ode to Joy, Twinkle Twinkle (PD), legato with repeated notes |
| two-hands | 1 | Ode to Joy melody over held bass |

Conditions: **clean** band-pass 120 Hz–7 kHz, 50 dB SNR; **room** + synthetic room tail (70 ms decay, direct-to-reverb +3 dB), 35 dB SNR; **noisy** same with 20 dB SNR. Notes come from the app's own piano samples (Salamander Grand, natural decay), pitch-shifted ≤1.5 semitones, random velocity 0.5–1.

**Scoring** (`cd app && dart run tool/mic_eval.dart`): a detected note-on is a hit if pitch matches and onset is within ±50 ms of a truth note (each matched once). Onset error = detected onset − truth. Report delay = time the detector had the note − truth onset (pure algorithm, no audio I/O).

## Results

Scored 2026-10-21 with the Salamander piano and flux settings γ=100, ratio 1.5, δ=3 (`NoteDetector` defaults):

```
| Group | Notes | P | R | F1 | Onset error mean / p95 (ms) | Report delay p50 / p95 (ms) |
|---|---|---|---|---|---|---|
| all | 309 | 0.869 | 0.861 | 0.865 | 13.2 / 23 | 111 / 120 |
| clean | 103 | 0.860 | 0.893 | 0.876 | 12.8 / 22 | 110 / 119 |
| room | 103 | 0.921 | 0.903 | 0.912 | 13.5 / 23 | 111 / 120 |
| noisy | 103 | 0.827 | 0.786 | 0.806 | 13.3 / 22 | 111 / 119 |
| single | 93 | 0.781 | 0.882 | 0.828 | 12.9 / 15 | 110 / 112 |
| chord | 93 | 0.859 | 0.785 | 0.820 | 9.8 / 15 | 109 / 112 |
| melody | 87 | 0.965 | 0.943 | 0.953 | 15.7 / 23 | 112 / 121 |
| two-hands | 36 | 0.935 | 0.806 | 0.866 | 15.7 / 27 | 111 / 125 |
```

Against PRD targets (mono F1 ≥ 0.9, 3-note chords ≥ 0.75): single notes 0.828 and melodies 0.953 (mono below/above), chords 0.820 (above).

**Tuning history.** The first run (2026-10-20, midi-js samples, γ=1000, ratio 1.8, δ=4) scored F1 0.891. Re-scored on the Salamander piano with those settings it fell to 0.777, noisy recall 0.330: the stronger log compression let background noise raise the flux median so real attacks stayed under the threshold. Same failure a student saw with a real mic ("didn't hear enough notes"). Grid over γ ∈ {10, 30, 100, 300, 1000}, ratio ∈ {1.3–1.8}, δ ∈ {0.5–4} picked the current values (`dart run tool/mic_eval.dart --gamma= --ratio= --delta=`).

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

**End-to-end latency** (mic hardware + browser buffer + detector) was not measured on a real device in this task: no physical piano or measurement rig was available. The calibration step (below) measures and subtracts it per device; a real-device number is a follow-up.

**Web demo (pipeline, not acoustics)**: Chromium in the Claude desktop browser pane, release web build. `getUserMedia` was stubbed to a `MediaStream` playing the app's own C4 sample, so the run exercises worklet → detector → core, not a microphone. Calibration finished ("247 ms"; the fake loop's phase is arbitrary) and "Find middle C" (wait mode, 4 notes) completed 4/4 by mic.

## Implications

- Good enough for Piano Basics (single notes and triads in C3–C6). Not proof for acoustic pianos in real rooms: fixtures are synthetic degradations of one sampled piano.
- Wrong extra notes cost little in wait mode (blue splash, not penalized) and none count as misses in core; missed chord notes do block progress, so recall on chords matters most.
- Bass below C3 is unreliable; lessons there should prefer MIDI until improved.

## Follow-ups

- Record a real fixture set (own recordings, acoustic + digital piano, phone + laptop) and re-score; measure end-to-end latency on a named device with a loopback/clap test.
- Score-informed check: core knows the expected chord; test "are these pitches present?" instead of blind transcription to lift chord recall.
- Native capture (Android/iOS/desktop) with the same detector, or port it to Rust `core` once a native audio thread exists.
