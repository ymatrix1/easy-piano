# Content format

Status: implemented for songs, levels, journeys, courses, scenes (shape) and strings ([D3](../DECISIONS.md)). Parser: `core/src/notation.rs`, songs: `core/src/song.rs`, linter: `tools/content-cli` (`cargo run -- lint ../../content`). Editor schema: `content/schema/song.schema.json`; the linter is the source of truth.

## Files

```
content/
  courses.json                 # course list, prerequisites, tracks
  courses/<course>/journey.json
  courses/<course>/levels/<level>.json
  songs/<song>.json
  scenes/<scene>.json          # animation stages
  strings/<locale>.json        # all user-visible text by key
  schema/*.schema.json
```

## Level

```json
{
  "id": "pb1.rh-c-position.02",
  "title": "str:pb1.rh_c_position.02.title",
  "ui": "treble",
  "stages": [
    {"type": "animation", "scene": "pb1.finger-numbers"},
    {"type": "wait", "pre_listen": true,
     "score": "pb1-cde"},
    {"type": "play_along", "score": "pb1-cde", "tempo": 0.7, "pass": 0.7}
  ]
}
```

## Song / score

```json
{
  "id": "ode-to-joy-easy",
  "title": "Ode to Joy", "composer": "L. van Beethoven",
  "arranger": "Easy Piano contributors",
  "source": "original", "source_url": null,
  "license": "CC-BY-SA-4.0", "composition_license": "public-domain",
  "bpm": 100, "time": "4/4", "key": "C",
  "bars": [
    {"RH": "E4:4@3 E4:4@3 F4:4@4 G4:4@5", "LH": "C3:1@5"},
    {"RH": "G4:4@5 F4:4@4 E4:4@3 D4:4@2", "LH": "G2:1@1"}
  ],
  "critical": [[0, 8]]
}
```

## Note token grammar (draft)

```
token    := (pitch+ | "r") ":" dur ("@" finger+)? ("(" ann ")")?
pitch    := [A-G] ("#"|"b"|"n")? octave        ; C4 = middle C
dur      := denom ("." )*  | n "/" d           ; 4 = quarter, 2. = dotted half, 3/8 explicit
finger   := [1-5]                               ; one per pitch in chord order
directive:= "{" name (":" json)? "}"            ; {chord:"C"} {lyric:"..."} {tie} {cresc}
```

Examples: `C4E4G4:2@135` C major chord half note, fingers 1-3-5; `r:4` quarter rest; `F#4:8.` dotted eighth.

Each bar's hand string must sum to the time signature (lint error otherwise). Differs from Simply Piano grammar on purpose (denominator durations, `@` fingering, `{}` directives).

## Backing parts (`ACC`, `DRUMS`, `BASS`, `PAD`, `CHOIR`)

A bar may hold an `ACC` part next to `RH` / `LH`: our own accompaniment (chords, bass) in the same notation. It is played by the app in play-along and never graded; bar lengths are linted like any hand.

A bar may also hold a backing band ([D14](../DECISIONS.md)), same notation, also app-played and never graded:

| Part | Sound | Pitches |
|---|---|---|
| `DRUMS` | Synthesized kit (no sample files) | General MIDI percussion numbers written as note names: kick 36 `C2`, snare 38 `D2`, closed hi-hat 42 `F#2`, open hi-hat 46 `A#2`, crash 49 `C#3`. Lint rejects any other pitch. Length matters only for bar sums. |
| `BASS` | Synthesized bass voice | Normal pitches (21–108), e.g. `C2:4 G2:4`. |
| `PAD` | Synthesized strings pad (3 detuned saws, slow attack/release) | Normal pitches; long chords, e.g. `G3C4E4:1`. Keep it off the melody's notes. |
| `CHOIR` | Synthesized wordless "ooh" voices (2 detuned saws, vibrato, /u/ formant filters) | Normal pitches; sustained lines above the melody, e.g. `C5E5:1`; use `r:1` where it rests. |

Example bar: `"DRUMS": "C2F#2:8 F#2:8 D2F#2:8 F#2:8 C2F#2:8 C2F#2:8 D2F#2:8 F#2:8"`, `"BASS": "C2:4 G2:4 E2:4 G2:4"`. The bridge's `companion()` returns each note with its `part_name` so the app picks the instrument. Each part plays through its own gain bus (default mix: piano 4.0, `ACC` 3.0, `DRUMS` 0.17, `BASS` 0.07, `PAD` 0.06, `CHOIR` 0.32; the piano samples peak near -21 dBFS. Measured on Ode to Joy play-along, mean RMS vs `ACC`: bass -4.7 dB, drums -11.1, choir -14.3, pad -15.4); `PianoSynth.setPartLevel(part, level)` changes it, ready for a per-part mute/volume UI.

## Journey and levels (implemented)

- `courses.json`: `sections[]` (`id`, `title`) and `courses[]` (`id`, `title`, `description`, `section`, `requires`, `journey`, optional `status`: `ready` (default) or `planned`). Planned courses have no journey and show locked in the app. Hierarchy: section → module (course) → submodule (journey node) → task (level); see [visual-style.md](visual-style.md).
- Journey nodes: `id`, `kind` (`lesson`, `song`, `star_gate`, `boss`, `mini_boss`), `title`, `icon`, `levels`, `next`, optional `songs` slots keyed by taste (`default`, `classical`, `folk_world`, …; D12).
- `star_gate` nodes also need `stars_needed` (1 to 3 × level count): one level per song, and the gate is passed when the stars summed over its levels reach it, so the learner picks which songs to play (e.g. 3 songs, `stars_needed: 5` ≈ any two played well). Other kinds must not set it. Gates never lock anything: until placement exists (OQ9) every node stays open.
- Level stages: `type` (`wait`, `play_along`, `one_note`, `animation`, `quiz`); `score` required for wait/play_along/one_note; `scene` for animation; optional `tempo` (0.3–1.5), `pass` (0–1), `hand` (`RH`, `LH`, `both`), `pre_listen`, `repeats` (1–10, wait stages repeat in a row).
- Levels: `ui` (`treble` / `bass` single staff for beginners, `both` grand staff), optional `keyboard` (default `true`; on-screen keyboard shown by default).
- Beats: duration × time-signature denominator (quarter = 1 beat in x/4).

## What `content lint` checks

Song metadata and allowed licenses; `source_url` unless `original`; bpm range; every bar per hand sums to the time signature; pitches in piano range; finger count matches chord size; critical sections in range; ids match file names; level, scene, score, next-node and song-slot references exist; `star_gate` has a valid `stars_needed`; course sections and statuses are known; planned courses skip journey checks; every `str:` key exists in `strings/en.json`.

## Rules

- All text via `str:` keys.
- Songs need license fields ([content rule](../../.agents/rules/content-and-licensing.md)).
- IDs stable forever (progress keyed by them).
