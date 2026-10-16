# Product requirements

Status: draft (planning phase). Working name: **Easy Piano** (final name is [OQ1](OPEN-QUESTIONS.md)).

## Summary

An open-source, gamified piano course that runs on Android, iOS, web and desktop from one codebase. It listens to the student's piano (MIDI or microphone), shows what to play, waits or scrolls in time, grades the result and rewards progress. The curriculum follows the shape that made Simply Piano work (short lessons, play from day one, songs as rewards), rebuilt with original content and **no videos**: every explanation is a data-driven animation rendered by the app.

## User

| Persona | Need |
|---|---|
| Adult beginner with a cheap keyboard | Play a recognizable song in week one; no theory wall |
| Returning player | Re-learn sight reading and chords at own pace |
| Kid (with parent) | Short, bright, game-like sessions |
| Teacher / contributor | Author lessons and songs as plain files, review them in a PR |

## Pains (what existing apps get wrong)

1. Closed, subscription-gated; good lessons locked behind paywall.
2. Video lessons: heavy downloads, not localizable, not editable, can't adapt to left-handed view or tempo.
3. Content not remixable: teachers can't fix or extend a lesson.

## Goals

- G1. Recreate the Simply Piano learning path (Piano Basics → Essentials → Intermediate, plus Chords track) with original material. See [curriculum spec](specs/curriculum.md).
- G2. One codebase, four targets: Android, iOS, web, desktop.
- G3. Input: MIDI (USB/BLE) first; microphone (acoustic piano) second; on-screen touch keyboard as fallback.
- G4. Latency budget: MIDI key → visual feedback ≤ 30 ms on reference devices.
- G5. Zero video. Every teaching moment is an animation scene (keyboard, hands, staff, text) defined in content files. See [animation spec](specs/animations.md).
- G6. Content is plain text in git (JSON + compact note notation), validated in CI.
- G7. Works offline after first download; no account needed for core lessons.

## Non-goals (v1)

- Copying Simply Piano assets, songs, audio, images or level files. We study structure; we write our own content. See [D6](DECISIONS.md).
- Licensed pop songs. Public domain and original/CC-licensed arrangements only.
- Social features, leaderboards, payments.
- Instruments other than piano.

## Core concept

Course → Journey (map of nodes) → Level → Stage. A stage is one of: `wait` (play notes at own pace), `play_along` (timed, scrolling), `one_note` (single notes/chords drill), `animation` (teaching scene, replaces video), `quiz` (theory check). Grading uses critical sections with a pass ratio; stars reward accuracy. Details in [exercise engine spec](specs/exercise-engine.md).

## Features by pain

| Pain | Feature |
|---|---|
| 1 | GPL/MPL app + CC-BY-SA content; all lessons free |
| 2 | Animation scenes: tiny, localized via string tables, tempo-aware, mirror-able |
| 3 | Content repo + schema + `content lint` CLI + in-app preview |

## Success metrics

- Week-1 retention proxy: a new user finishes Piano Basics 1 node 1–5 in first session (measured locally, opt-in telemetry only).
- MIDI latency ≤ 30 ms p95; mic note detection F1 ≥ 0.9 on monophonic test set, ≥ 0.75 on 3-note chords.
- 60 fps on mid-range Android (2022) in play-along stage.

## Constraints and risks

| Risk | Mitigation |
|---|---|
| Polyphonic mic detection is hard | Ship MIDI first; score-informed detection (we know expected notes); research bean |
| Web Audio/MIDI gaps (Safari no Web MIDI) | Mic/touch fallback; document browser matrix |
| Content volume (SP has ~6.5k levels) | Start with Piano Basics 1–2 (~60 levels); tooling to author fast; AI-assisted drafting reviewed by humans |
| Legal | Clean-room content rule [D6](DECISIONS.md); reference APK never committed |

## Licensing

Code: [OQ2](OPEN-QUESTIONS.md) (proposed MPL-2.0 or GPL-3.0). Content: CC-BY-SA-4.0. Fonts: Bravura (OFL). Samples: CC0 / public-domain piano soundfont (e.g. Salamander, CC-BY).
