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

`source`: `original` (our arrangement from our own knowledge of the tune), `generated` (see below), or the edition it is based on, e.g. `mutopia` with `source_url` pointing at the Mutopia piece page (public domain or CC-BY-SA editions only; the simplified arrangement stays ours, `CC-BY-SA-4.0`).

`bpm` counts the time signature's beat unit (its denominator note): `6/8` at 120 plays 120 eighths a minute, `2/2` at 60 plays 60 halves (session engine, [difficulty](difficulty.md)).

### Generated songs (optional fields)

Songs made by a generator ([D17](../DECISIONS.md), [skill-specs](skill-specs.md)) use `"source": "generated"`, `"license": "CC0-1.0"` and a `generator` object:

```json
"generator": {
  "method": "llm", "tool": "compose-song", "model": "claude-opus-5-5",
  "seed": 42, "source_song": null, "prompt_ref": ".agents/skills/compose-song/SKILL.md"
},
"spec_node": "essentials-1/eighths"
```

| Field | Rule |
|---|---|
| `generator.method` | required; `rules`, `pd-variation`, `llm`, `magenta`, `hand` or `melody-model` (our own model, [melody-model](melody-model.md)) |
| `generator.source_song` | required for `pd-variation`: id of the PD song varied |
| `tool`, `model`, `seed`, `prompt_ref` | optional, free text / integer |
| `spec_node` | optional on any song, `course/node`; lint then runs the rubric against that node |

`generator` is only allowed with `source: generated`; `source_url` is not required for it.

### Regional restriction (optional)

A song whose composition is still protected somewhere lists those regions ([D33](../DECISIONS.md), proposed):

```json
"restricted_in": [{"region": "US", "until": "2036-01-01"}]
```

`region` is an ISO 3166-1 alpha-2 code, `until` the first day (`YYYY-MM-DD`) the song may be offered there. The app does not filter by region yet (bean piano-7os5).

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

## Directives: dynamics and hairpins

Status: rendering (piano-boat PR 1), lint and MIDI velocity grading (piano-rdr4) implemented. Grading is informational and does not change stars yet. Core: core/src/dynamics.rs. Zero length, placed in a hand string like a note: `{dyn:"mf"} C4:4 {cresc} D4:4 E4:4 {end} F4:4`.

- `{dyn:"<text>"}`: dynamic at that beat. Supported text: `p pp ppp mp mf f ff fff fp sf sfz`. Other text is ignored by the app and must be rejected by lint.
- `{cresc}` / `{dim}`: open a crescendo or diminuendo hairpin at that beat.
- `{end}`: close the open hairpin. A hairpin also closes at the next `{dyn}`, the next hairpin, or the end of the song.

The same directive in both hands at the same beat is drawn once.

**Grading (informational).** For MIDI input, each matched note-on carries its velocity. A dynamic passes when at least half of the onsets from its beat to the next dynamic classify as it (MuseScore velocities: ppp 16, pp 33, p 49, mp 64, mf 80, f 96, ff 112, fff 126; nearest centre wins). `fp`, `sf` and `sfz` are not graded. A crescendo passes when the mean velocity of its second half exceeds the first by 8 or more (a diminuendo, the reverse). Mic and touch input have no velocity and are not graded.
  Parsed by `app/lib/ui/staff/song_marks_parser.dart`.

## Directives: damper pedal

Status: rendering (piano-unmb) implemented. Pedal marks are drawn only; grading does not use them. Zero length, same placement rules as above. Core: none; app parser: `app/lib/ui/staff/song_marks_parser.dart`.

- `{ped}`: press the damper pedal at that beat. A `{ped}` while the pedal is already down is a pedal change (drawn as a notch on the line).
- `{ped-up}`: release the pedal at that beat.

A pedal left down runs to the end of the song with no release mark. A pedal pressed and released on the same beat draws nothing. Lint does not yet check these directives.

## Directives: arpeggios and glissandi

Status: rendering (piano-i235, PR 3). Parsed by `app/lib/ui/staff/song_marks_parser.dart`, drawn by `arpeggio_layout.dart`. Core lint does not check these yet (unknown directives are ignored there), so a typo is silently not drawn.

- `{arp}`, `{arp:up}`, `{arp:down}`: arpeggio on the chord at that beat, in the hand the directive sits in. `up` / `down` add an arrowhead; any other argument is ignored.
- `{gliss}`: glissando from the notes at that beat to the next note of the same hand. Rests do not end it. With no later note in that hand, nothing is drawn.

Example: `{arp:up} C4E4G4:2 {gliss} D5:2` (chord syntax as in the grammar above).


## Directives: ornaments and acciaccaturas

Status: rendering only (piano-rlp3, PR 4). Parsed by `app/lib/ui/staff/song_marks_parser.dart`, drawn from `ornament_layout.dart`. Core (`core/src/dynamics.rs`) ignores these names (`Ok(None)`), and lint does not check them yet, so a typo is silently not drawn. Zero length, placed in a hand string like a note.

- `{trill}`, `{mordent}`, `{turn}`: ornament above the chord that starts at that beat, in the hand the directive sits in. A mordent or turn is centred on the chord. A trill starts at the chord's left edge and runs as a wavy line to one spatium before the next onset of that hand. With no note at that beat, nothing is drawn.
- `{acc:"D5"}`: acciaccatura (grace note, pitch D5) before the chord that starts at that beat. Write it directly before the main note, at the same beat. The name is a note name as in the grammar above (`[A-G]`, optional `#` / `b` / `n`, octave): `{acc:"F#4"}`, `{acc:"Bb3"}`, `{acc:"Cn4"}`. A `#`, `b` or `n` is drawn as an accidental; without one, none is drawn. Grace notes take no time, so they are not in the bar sum.

Example: `{trill} C5:2 {acc:"D5"} E5:4 {mordent} G5:4` (the trill and the mordent sit on the chords at beats 0 and 3; the grace D5 leans on the E5 at beat 2).

Malformed names are ignored (`{acc:D5}` without quotes, `{acc:"H5"}`, out-of-range pitches, `{trill:"x"}`). Not in this version: appoggiatura, playback of grace notes, and any directive that changes the timeline.

Duplicate directives in `RH` and `RH2` (or `LH` and `LH2`) at one beat are drawn once.

## Two voices per hand (`RH2`, `LH2`)

Status: implemented ([D34](../DECISIONS.md), proposed; bean piano-16vk). Needed by most of Mikrokosmos Books 2-6: 69 of 147 pieces have a hand that holds one line while it plays another.

A bar may hold a second voice for either hand. It is written like any hand string:

```json
{"RH": "E4:4@3 F4:4@4 G4:4@5 A4:4@5", "RH2": "C4:1@1", "LH": "C3:1@5"}
```

| Key | Meaning | Engraving |
|---|---|---|
| `RH`, `LH` | voice 1 (as today) | stems up in `RH`, stems down in `LH` when the hand has a second voice in that bar; otherwise as today |
| `RH2`, `LH2` | voice 2 of the same hand | stems down in `RH2`, stems up in `LH2` |

Rules:

- Only two voices per hand. A bar without `RH2` / `LH2` is single-voice, so every existing song stays valid.
- Each voice sums to the time signature on its own (same lint as a hand).
- Voice 2 needs voice 1 in the same bar: `RH2` without `RH` is an error.
- New token `s:<dur>`: an invisible rest (spacer). It counts for the bar length, draws nothing and is allowed in any hand or voice. Typical use: `"RH2": "s:2 C4:2"`.
- Unison: the same pitch with the same onset in both voices of one hand is one target (graded once) and is drawn as one notehead with two stems.
- Overlap: the same pitch sounding in both voices at once with different onsets is a lint error (one key cannot be struck while held).
- Fingering (`@`) and `{tie}` work per voice. A tie never joins voice 1 and voice 2.
- `ACC` and the backing parts have no second voice; they are never graded.

Behaviour:

| Area | Rule |
|---|---|
| Timeline (`Song::timeline`) | `TimedNote` gets `voice: u8` (1 or 2); `part` and `left_hand` follow the hand, so `RH2` notes are `Part::Right`. |
| Matching / grading | Unchanged: targets are (pitch set, onset, hand); notes of both voices with the same onset form one chord. Durations are not graded. |
| Hand modes | A stage with `hand: "RH"` grades `RH` and `RH2`; the app plays the other hand's two voices. |
| Wait mode | Waits for every pitch at the onset across both voices; held voice-2 notes keep sounding (app or learner) while voice 1 moves. |
| Staff | Both voices on the hand's staff; voice-2 rests move down (`RH2`) or up (`LH2`) so they do not collide; spacers draw nothing. |
| Difficulty (`core/src/difficulty.rs`) | New feature `two_voice_bars_per_bar` (bars where a hand has a second voice / bars); the model is not refitted in this change. |
| Rubric / skill specs | A song with a second voice needs the taught flag `two_voices`; no main-path node teaches it yet, so the rubric rejects generated songs with voices. |
| Converter (`tools/melody-model`) | Reads up to two voices per part (MusicXML voice order: first = voice 1); three or more is still `Unsupported`. `song_to_score` writes them back as voices. |
| Similarity | Melody extraction keeps using the top line of `RH` + `RH2` (skyline). |

Out of this spec: more than two voices, cross-staff notes, meter and key changes in a song, tuplets.

## Backing parts (`ACC`, `DRUMS`, `BASS`, `PAD`, `CHOIR`)

A bar may hold an `ACC` part next to `RH` / `LH`: our own accompaniment (chords, bass) in the same notation. It is played by the app in play-along and never graded; bar lengths are linted like any hand.

A bar may also hold a backing band ([D14](../DECISIONS.md), sounds per [D22](../DECISIONS.md)), same notation, also app-played and never graded:

| Part | Sound | Pitches |
|---|---|---|
| `DRUMS` | Sampled kit (Virtuosity Drums, CC0) | General MIDI percussion numbers written as note names: kick 36 `C2`, snare 38 `D2`, closed hi-hat 42 `F#2`, open hi-hat 46 `A#2`, crash 49 `C#3`. Lint rejects any other pitch. Length matters only for bar sums. |
| `BASS` | Sampled electric bass (FluidR3, C1–C4) | Normal pitches (21–108), e.g. `C2:4 G2:4`. |
| `PAD` | Sampled string ensemble (FluidR3, C3–C6, looped, slow attack/release) | Normal pitches; long chords, e.g. `G3C4E4:1`. Keep it off the melody's notes. |
| `CHOIR` | Sampled wordless "ooh" voices (FluidR3, C3–C6, looped) | Normal pitches; sustained lines above the melody, e.g. `C5E5:1`; use `r:1` where it rests. |

Example bar: `"DRUMS": "C2F#2:8 F#2:8 D2F#2:8 F#2:8 C2F#2:8 C2F#2:8 D2F#2:8 F#2:8"`, `"BASS": "C2:4 G2:4 E2:4 G2:4"`. The bridge's `companion()` returns each note with its `part_name` so the app picks the instrument. Each part plays through its own gain bus into a reverb send, a gentle bus compressor and a limiter (default mix: piano 1.0, `ACC` 1.0, `DRUMS` 0.19, `BASS` 1.1, `PAD` 0.37, `CHOIR` 0.67; the learner's live keys 1.0, bypassing the dynamics). Measured on Ode to Joy play-along, RMS vs `ACC`: bass -5.2 dB, drums -8.9, choir -14.0, pad -15.0; mix peak -3.5 dBFS ([instrument-samples.md](../research/instrument-samples.md)). App-played notes get metric/phrase velocity and a few ms of seeded humanize (`app/lib/audio/backing.dart`); graded parts never do. `PianoSynth.setPartLevel(part, level)` scales it (1 = default), ready for a per-part mute/volume UI.

## Journey and levels (implemented)

- `courses.json`: `sections[]` (`id`, `title`; `methods` holds optional method-book courses such as `mikrokosmos-1`, which stay off the difficulty ramp; to be replaced by `content/methods.json`, see [methods](methods.md)) and `courses[]` (`id`, `title`, `description`, `section`, `requires`, `journey`, optional `status`: `ready` (default) or `planned`). Planned courses have no journey and show locked in the app. Hierarchy: section → module (course) → submodule (journey node) → task (level); see [visual-style.md](visual-style.md).
- Journey nodes: `id`, `kind` (`lesson`, `song`, `star_gate`, `boss`, `mini_boss`), `title`, `icon`, `levels`, `next`, optional `songs` slots keyed by taste (`default`, `classical`, `folk_world`, …; D12).
- `star_gate` nodes also need `stars_needed` (1 to 3 × level count): one level per song, and the gate is passed when the stars summed over its levels reach it, so the learner picks which songs to play (e.g. 3 songs, `stars_needed: 5` ≈ any two played well). Other kinds must not set it. Gates never lock anything: until placement exists (OQ9) every node stays open.
- Level stages: `type` (`wait`, `play_along`, `one_note`, `animation`, `quiz`); `score` required for wait/play_along/one_note; `scene` for animation; optional `tempo` (0.3–1.5), `pass` (0–1), `hand` (`RH`, `LH`, `both`), `pre_listen`, `repeats` (1–10, wait stages repeat in a row).
- Levels: `ui` (`treble` / `bass` single staff for beginners, `both` grand staff), optional `keyboard` (default `true`; on-screen keyboard shown by default).
- Beats: duration × time-signature denominator (quarter = 1 beat in x/4).

## What `content lint` checks

Song metadata and allowed licenses; `restricted_in` region codes and dates; `source_url` unless `original` or `generated`; `generated` songs need `generator` and CC0-1.0; songs with `spec_node` pass the [rubric](skill-specs.md) for that node; `skill-specs/<course>.json` parse and name real journey nodes; bpm range; every bar per hand sums to the time signature; pitches in piano range; finger count matches chord size; critical sections in range; ids match file names; level, scene, score, next-node and song-slot references exist; `star_gate` has a valid `stars_needed`; course sections and statuses are known; planned courses skip journey checks; every `str:` key exists in `strings/en.json`; other `strings/<tag>.json` files warn on missing or stale keys (English fallback, see [i18n](i18n.md)).

## Rules

- All text via `str:` keys.
- Songs need license fields ([content rule](../../.agents/rules/content-and-licensing.md)).
- IDs stable forever (progress keyed by them).
