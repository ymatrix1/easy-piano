# Simply Piano teardown

Checked: 2026-10-15. Source: jadx-decompiled Android APK in `references/simply_piano_jadx_deobf/` (local only, never committed, see [D6](../DECISIONS.md)). Paths below are relative to that folder. Purpose: learn structure and pedagogy; **do not copy content**.

## Question

How is Simply Piano built and how is its curriculum modeled, so we can design an open equivalent?

## Tech stack

| Area | Finding | Evidence |
|---|---|---|
| Game engine | LibGDX (Java), not Unity | `resources/lib/arm64-v8a/libgdx.so`, `com/badlogic` |
| Menus | Android Views + Kotlin | `com/joytunes/simplypiano/ui` |
| Audio out | Superpowered + SoundFont synth (`spl_6octave_22k.sf2`), Oboe | `libSuperpoweredWrapper.so`, `com/joytunes/common/audio/SoundFontSynth.java` |
| Mic recognition | TFLite CNN ("CnnRecogEngine"), full + light model, NMF engine, GPU/NNAPI | `sources/p375ok/`, `assets/GameConfig.json` |
| Echo handling | Backing-track correlation/subtraction, calibration | `musicengine/SuperpoweredReferenceMusicCorrelator.java`, `CalibrationRunner.java` |
| Latency table | Per-device A/V latency JSON, default 0.13 s | `assets/2022_11_device_latencies.json` |
| MIDI | `android.media.midi` + USB; BLE only via OS | `com/joytunes/common/midi/` |
| Content | JSON in assets + CDN on demand, MD5 manifest | `assets/*.json`, `assets/BigFilesMD5s.json` |
| Strings | Apple `.strings` UTF-16, 13 locales, shared with iOS | `assets/Localizable.*.strings` |

## Curriculum model

Course → Journey → Level → Stage.

- `AllCourses.json`: id, title, description, image, `requiredCoursesId`, `journeyFilename`, `isTouch`.
- `DefaultCoursePaths.cdc.json`: touch section → basic section (Piano Basics 1–4) → main section split into two tracks, **Soloist** (sheet music, technique) and **Chords** (pop/jazz accompaniment), laid out as a 3-column grid.
- `*.journey.json` (125 files): array of nodes `{id, displayName, icon, next[], levels[]}`. Node types include song nodes (`isBig`), star gates (`starsNeeded` + `starsSongs`), `boss` / `miniBoss`. Levels may be A/B/locale variant maps.
- `AllLevels.json`: ~6,576 levels. Keys: `stages`, `uiType` (`both_clefs`, `treble_clef`, `bass_clef`, `video`, `touch`), `scaleFactor`, `levelType` (`pool`, `flash_card`), `hideKeyboard`, `preventSkip`, `numRepeats`.
- `AllSongs.json`, `AllLibrarySongs.json`: songs with melodies + backing track, practice sub-levels, tier gating.
- `*.workout.json` (158): daily workouts from pool and flash-card levels.

Course titles: Touch Intro, Piano Basics 1–4, Essentials I–III, Intermediate I–IV, Pre-Advanced I–II, Classical I, Taste of Bach I–II, Pop Chords I–III, Chord Styling I–III, Blues Chords I, Jazz Chords I–II, Lead Sheet I–III, Arpeggios I, Slash Chords.

## Stage types (counts in `AllLevels.json`)

| Type | Count | Behaviour |
|---|---|---|
| `note_sequence` | 44,235 | Wait mode: staff shows notes, app waits for each. Options `preListen`, `tooltipText`, narration |
| `moving` | 20,436 | Timed play-along, notes scroll to a vertical rhythm line, backing track `bgm`, look-ahead `onScreenDisplayDuration` (~2.5 s) |
| `video` | 377 | `videoFile` from CDN: concept, technique, song walkthrough |
| `one_note` | 254 | Single notes / chord drills |

No dedicated theory quiz type; theory comes via video + tooltips.

## Note notation

Custom text inside JSON, parser in `sources/mk/`:

- Token: `C4E4G4:1/2%135(HL)` = chord C4 E4 G4, half note, fingers 1-3-5, annotation `HL`.
- Pitch `[A-G][#bnsf]?[0-9]`; duration as fraction of whole note; `-:1` rest.
- Directives `*Name: json*`: `Text` (chord labels/lyrics), `CriticalSectionStart/End` (+ `threshold`), `Swing8ths`, `TimeSignature`, `bpm`, `PhraseStart/End`.
- Melodies split into `right` and `left` hands.

Parsing rules (confirmed 2026-10-16, for the local stats tool only):

- Tokenize with `\*[^\*]+\*|[^\s\*]+`; tokens are notes (`PITCHES:DUR...`) or `*Event:arg*`.
- Cursor `t` in whole-note fractions; a note token advances `t` by its duration; chord pitches share `t` and `dur`; `-:d` is a rest.
- `%n` finger(s), `^` other hand, `(StemU|StemD)` stem direction, `[..]` micro-timing.
- Events (`CriticalSectionStart/End`, `Text`, `Swing8ths`, `tdm-reservation`, `bgmFileName`, `LevelStart`, `StageStart`) take zero time.
- Beats = `dur × denominator(timeSignature)` (`1/4` in 4/4 = 1 beat); seconds = `beats × 60 / bpm`.

Compact, diff-friendly, easy to hand-author. We adopt the same idea with our own grammar ([content format](../specs/content-format.md)).

## Grading

- Critical sections decide pass/fail in timed stages. Pass ratio default **0.7**, lowered **0.1 per 2 failed attempts** (`p587wk/C15361c.java`).
- Timing window: base 0.3 s; ≈0.34 s with MIDI, ≈0.15 s with mic (`p587wk/C15362c0.java:449`).
- Repeated failure → "Practice Mode" (slow tempo, turtle sound).
- Stars per song (0–3/0–5), star gates unlock nodes, weekly streak with freezes (disabled by flag), practice-time tracking. No XP.

## Videos

377 video stages, fetched from CDN, named `Video_<Course>_<Topic>_localized.mp4`: how to sit, finger numbers, hand position, chord shapes, song walkthroughs. These are the items we replace with animation scenes. Video understanding plan: [video-to-animation](../specs/animations.md#pipeline-from-reference-video).

## Onboarding

60+ config files: age, goals, experience snippet tests, piano type, learning style, plan preview. First-song picker for Piano Basics 1.

## Implications

1. Copy the **shape**: Course/Journey/Level/Stage, wait vs timed stages, critical sections, adaptive threshold, star gates. Proven and simple.
2. MIDI first; mic needs an ML model + echo handling, a large separate project.
3. Scrolling staff (not falling notes) is their primary view; we offer both.
4. Replace videos with scenes; add a real `quiz` stage they lack.
5. Per-device latency calibration is needed; ship a calibration screen.

## Staff note cover

Checked 2026-10-21, local jadx sources (`references/simply_piano_jadx_deobf_33_7`, git-ignored). Mechanics only.

| What | Reference behaviour | Where |
|---|---|---|
| Passed notes | Not faded themselves. Sheet `draw()` grabs the rendered background (band, staff, clefs) with `glReadPixels` once, builds an alpha mask and draws that copy **over** the notes group | `p380oj/C10032s0.java:197-232` |
| Cover alpha, play-along | 255 from x=0 to clef-images right edge minus 50 px, then linear 1→0 to the header width | same, loop at `:211-222` |
| Cover alpha, static/wait stage | Linear 1→0 from x=0 to play line minus half a notehead | same, `f32361g` branch `:204-208` |
| Dim cover | Second copy at max alpha 127, starts transparent, `fadeIn(0.2f)` when a highlight overlay opens | `:226-231`, `p350nj/C9674v0.java:193` |
| Page slide (wait) | Notes group `moveTo(x - shift, y, 1.0f)`, linear, when the current note passes ~70% of the width | `p350nj/C9674v0.java:417,462` |
| Play line x | staffAreaLeft 129 + clefImageXDiffFromStaffAreaLeft 30 + rhythmLineXDiffFromClefImageLeft 480 = 639 px on a 1080 px tall layout (scale 1.0 at ≥1080 px height, 0.67 at ≥720, 0.5 below) ≈ 0.27-0.33 of the width | `resources/assets/LevelUIConfig.json`, `p380oj/C10043y.java:83`, `p380oj/EnumC10012i0.java` |
| Static notes start | 60 px left of the play line (`staticUINotesContainerXDiffFromRhythmLine: -60`) | `LevelUIConfig.json` |
| Stage intro | Each sheet element starts one screen-height below, `delay(k/(2n))` then `moveTo(y, min(1-(n-1)/(2n), 0.5))` with swingOut(2) `((s+1)q+s)q²+1`, q=t-1; no alpha change | `p380oj/C10032s0.java:173-181,289-308`, `p651ya/C13982m.java:16-19`, `AbstractC13983n.java:53` |
| Note colour | Hit: `Actions.color(c, 0.2f)`, linear. Partial chord: tween to hit colour 0.2 s then back to ink 0.2 s. Hit colours 0x00CCCC / 0xFFCF00, ink 0x0F0F0F | `p691zi/C14751v.java:20-30`, `p350nj/C9674v0.java:382-397`, `p350nj/C9666r0.java:160-172`, `p380oj/C10032s0.java:52-55` |
| Right edge | No fade-in found; notes are clipped at the edge | - |
| Labels | Instruction labels `fadeIn/fadeOut(0.2f)` | `p350nj/C9674v0.java:213,234` |

Implications: our painter repaints the background over the notes with the same alpha profile (see `docs/specs/practice-screen.md`); no assets or code copied.

## Follow-ups

- Bean: extract journey/level **statistics** (stage mix per course, bpm ranges, note ranges) into a numeric summary. No content copy.
- Bean: watch reference videos via `agy` and write per-video scene briefs.
