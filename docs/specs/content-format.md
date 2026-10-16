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

## Accompaniment part

A bar may hold an `ACC` part next to `RH` / `LH`: our own accompaniment (chords, bass) in the same notation. It is played by the app in play-along and never graded; bar lengths are linted like any hand.

## Journey and levels (implemented)

- Journey nodes: `id`, `kind` (`lesson`, `song`, `star_gate`, `boss`, `mini_boss`), `title`, `icon`, `levels`, `next`, optional `songs` slots keyed by taste (`default`, `classical`, `folk_world`, …; D12).
- Level stages: `type` (`wait`, `play_along`, `one_note`, `animation`, `quiz`); `score` required for wait/play_along/one_note; `scene` for animation; optional `tempo` (0.3–1.5), `pass` (0–1), `hand` (`RH`, `LH`, `both`), `pre_listen`, `repeats` (1–10, wait stages repeat in a row).
- Levels: `ui` (`treble` / `bass` single staff for beginners, `both` grand staff), optional `keyboard` (default `true`; on-screen keyboard shown by default).
- Beats: duration × time-signature denominator (quarter = 1 beat in x/4).

## What `content lint` checks

Song metadata and allowed licenses; `source_url` unless `original`; bpm range; every bar per hand sums to the time signature; pitches in piano range; finger count matches chord size; critical sections in range; ids match file names; level, scene, score, next-node and song-slot references exist; every `str:` key exists in `strings/en.json`.

## Rules

- All text via `str:` keys.
- Songs need license fields ([content rule](../../.agents/rules/content-and-licensing.md)).
- IDs stable forever (progress keyed by them).
