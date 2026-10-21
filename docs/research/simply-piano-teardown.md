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

## Play-along error feedback and training mode

Checked 2026-10-21. Sources: decompiled 7.33 engine (`simply_piano_jadx_deobf_33_7/sources`, cited below) and the `app-ss` build (same code in `p587wk/C15362c0.java:87-119`; `assets/GameConfig.json`). Question: what the reference shows on wrong, missed and off-time notes in play-along, and how its slow-down ("turtle") mode triggers and ends. Mechanics and numbers only.

| Mechanic | Reference | Where |
|---|---|---|
| Matcher events | Missed note, hit (carries played − expected time), unmatched key | `p623xi/C13633j.java:85-88`, `p619xd/RunnableC13587e.java:70-80` |
| Miss window | Note expires at its time + 0.43 s | `p623xi/C13633j.java:43,105-111` |
| Hit colour | Teal `#00CCCC` on every glyph of the note | `p380oj/AbstractC10024o0.java:48,224-233` |
| Miss colour | Red `#DC1E1E` | `p380oj/AbstractC10024o0.java:51`, `p350nj/C9656m0.java:128` |
| Wrong key | Nothing visible, no sound, no penalty in normal play | `p350nj/C9656m0.java:118-122` |
| Early / late | Offset goes to scoring only; no visual difference | `p350nj/C9656m0.java:134-140` |
| Error sounds | None per note; only section results (turtle win / fail) | `p350nj/EnumC9658n0.java:9-10` |
| Streak / combo | None found | — |
| Unit of training | Critical section; its start marker may carry a pass ratio (default 0.7) | `p350nj/C9635c.java:27`, `dj/C3836l.java:453-469` |
| Section pass | When song time passes the section end: hits / notes ≥ threshold | `p350nj/C9634b0.java:326-330` |
| Early fail | Misses > (1 − threshold) × notes, before the section ends | `p350nj/C9634b0.java:331` |
| Threshold | base − 0.1 × ⌊fails / 2⌋ (no floor seen) | `p350nj/C9635c.java:26-33` |
| On fail | Seek back to the section start, restart its tracker | `p350nj/C9634b0.java:~165-190` |
| Practice trigger | Every 2nd consecutive fail of the same section (`failsBeforePracticeMode` = 2, remote config) | `p350nj/C9634b0.java:212-218`, `GameConfig.json` |
| Practice tempo | 0.75 × clock, one step only; miss window 0.75 × 0.43 s | `p350nj/C9640e0.java:32-52` |
| Practice intro | Badge 0.2 → 2× in 0.8 s, → 1.8× in 0.2 s, hold 1 s (+1.5 s the first time), then shrinks into the top-right corner in 1.0 s; label waits 1.2 s, fades in 0.4 s, holds 0.5 s, fades out 0.2 s; start sound; progress bar hidden | `p350nj/C9634b0.java:68-123` |
| Practice passed | Fail count +1 (threshold keeps dropping), back to full tempo on the same section, win sound | `p350nj/C9634b0.java:369-376` |
| Practice failed | Fail sound, practise again (no loop cap) | `p350nj/C9634b0.java:205-209` |
| Full-tempo pass | Next section, fail count reset | `p350nj/C9634b0.java:378-379` |

Implications: the reference's only per-note feedback is colour. Our keyboard flash and early / late tag are additions ([D31](../DECISIONS.md)). Training mode follows the reference rules ([exercise engine](../specs/exercise-engine.md#training-mode)).

Follow-ups: the reference's wait-for-note practice variant (`p350nj/C9638d0.java`, yellow `#FFCF00`) is not built; our content format has no per-section pass ratio.

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

## Follow-ups

- Bean: extract journey/level **statistics** (stage mix per course, bpm ranges, note ranges) into a numeric summary. No content copy.
- Bean: watch reference videos via `agy` and write per-video scene briefs.
