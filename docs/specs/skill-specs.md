# Skill specs and the rubric

Status: implemented (Phase A of epic piano-bovj, [D17](../DECISIONS.md)). Code: `core/src/rubric.rs`, `tools/content-cli` (`specs`, lint). Data: `content/skill-specs/<course>.json`.

Generated practice songs must teach one node's new skill and use nothing the learner has not seen. Two inputs define that:

| Input | Source | Meaning |
|---|---|---|
| Taught set | derived from songs | everything played up to and including the node |
| Node spec | `content/skill-specs/<course>.json` | what the node adds and what its songs must show |

## Taught set (derived)

`content specs` walks courses in `content/courses.json` order and nodes in journey order. For each node it collects the `score` of every stage of the node's levels and merges those songs into a running set. Songs with `source: "generated"` never widen it.

| Field | From graded hands (`RH`, `LH`) only |
|---|---|
| `pitches` | pitch set per hand |
| `durations` | duration labels as written: `1`, `2`, `2.`, `4`, `4.`, `8` … |
| `times` | time signatures |
| `accidentals` | black-key pitch classes (`F#`/`Gb` count as one) |
| `max_interval` | largest melodic leap in one hand, semitones (RH top note, LH bottom note) |
| `polyphony` | most notes struck at once, per hand |
| `rests`, `hands_together` | seen at least once |

## Node spec (written)

```json
{
  "course": "essentials-1",
  "nodes": [
    {
      "node": "eighths",
      "new_skill": "Eighth notes: two even notes per beat.",
      "required": [{ "rhythm": "8", "hand": "RH", "min_bar_share": 0.5 }],
      "bars": [8, 8],
      "bpm": [76, 96],
      "hands": "RH",
      "time": "4/4"
    }
  ]
}
```

| Field | Rule |
|---|---|
| `node` | journey node id (lint checks it exists) |
| `new_skill` | one sentence, the generator's brief |
| `bars`, `bpm` | inclusive ranges |
| `hands` | `RH`, `LH` or `both`: which graded hands must (and may) have notes |
| `time` | time signature of generated songs |
| `required` | patterns; every key in a pattern must hold, every pattern must hold |

Pattern keys:

| Key | Holds when |
|---|---|
| `rhythm` | that duration label appears; with `min_bar_share` (0..1), in at least that share of bars |
| `interval_min` | a melodic leap of at least that interval number: 2 = second (1 semitone), 3 = third (3), 4 = fourth (5), 5 = fifth (7), 6 = sixth (8), 7 = seventh (10), 8 = octave (12) |
| `accidental` | that black key appears (`F#`, `Bb`) |
| `pitch` | that pitch appears (`A4`) |
| `hand` | limits `rhythm`, `interval_min`, `pitch`, `chord`, `accidental` to `RH` or `LH` |
| `rest`, `chord`, `hands_together` | `true`: at least one rest / chord / shared onset |

Specs cover every node of piano-basics and essentials-1..3. A test in `content-cli` fails if a journey node has no spec.

## Rubric (`easy_piano_core::rubric`)

```rust
let taught = TaughtSet::from_song(&song);   // or merged over a walk
let errors: Vec<String> = rubric::check(&song, &taught, &node_spec);  // empty = pass
```

`check` reports: wrong meter, bpm or bar count; missing or extra graded hand; pitches per hand, durations, accidentals, meter not in the taught set; leap above `max_interval`; more simultaneous notes than taught; chord span over an octave; chord fingering out of order (RH fingers rise with pitch, LH fall); rests or hands-together not taught; each unmet `required` pattern. Backing parts (`ACC`, `DRUMS`, `BASS`, `PAD`, `CHOIR`) are ignored.

## Lint

A song with `spec_node: "course/node"` must pass `check` against that node's taught set and spec; failures are lint errors (`rubric course/node: …`). Spec files must parse, match their file name and name real nodes.

## `content specs`

```
cd tools/content-cli
cargo run -- specs ../../content               # JSON to stdout
cargo run -- specs ../../content --out f.json  # JSON to a file
```

One entry per node: `course`, `node`, `kind`, `songs`, `taught`, `spec` summary, `self_check` (each of the node's own songs → rubric errors). `self_check` is informational: hand-written songs predate the specs, and star gates mix meters and hands, so some fail by design. Exit code 1 only when a spec file is invalid.

## Limits

- Pitch names in output are spelled with sharps (`A#2` for B♭2); accidental lists give both spellings when a flat key was seen.
- Finger checks cover chords only; melodic finger crossings are not checked.
- The taught set is derived from songs, so a node whose songs omit a skill does not teach it to the rubric.
