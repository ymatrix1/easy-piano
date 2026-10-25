# Score formats and sources

Checked: 2026-10-15. Sources: local clones `references/sightread`, `references/musescore-downloader` (read, not run); format knowledge (no web check yet).

## Question

Which score format should be canonical, which to import, and where do we get legal scores?

## Format comparison

| Format | Hand-author | PR diff | Fingering | Two hands | Rust parser | Dart parser | PD sources |
|---|---|---|---|---|---|---|---|
| MusicXML | poor (verbose) | noisy | yes | yes | `roxmltree` DIY, small crates | DIY | MuseScore export, OpenScore (CC0), IMSLP some |
| ABC | excellent | excellent | weak | weak for piano | immature | little | folk (abcnotation) |
| LilyPond | good (experts) | excellent | yes | excellent | none (Scheme) | none | Mutopia |
| MIDI | no (binary) | no | no | tracks by convention | `midly` (great) | `dart_midi` | everywhere, unclear licenses |
| MEI | poor | medium | yes | yes | none mature | none | academic |
| MNX | medium (JSON) | good | yes | yes | none (draft) | none | almost none |
| Custom text in JSON | excellent | excellent | first-class | first-class | ours | via Rust FFI | via importers |

## Recommendation

| Role | Format |
|---|---|
| Canonical (stored, reviewed) | Custom text notation in JSON ([D3](../DECISIONS.md), [spec](../specs/content-format.md)) |
| Primary import | MusicXML / .mxl → Rust importer |
| Secondary import | MIDI (`midly`); hands guessed by track/pitch split; no fingering |
| Offline conversion | LilyPond (Mutopia) → MusicXML/MIDI via `lilypond` / `python-ly` |
| Export | MIDI (playback, MIDI out); MusicXML later |
| Engraving (if custom staff not enough) | Verovio (LGPL) from MusicXML/MEI |

## sightread (reference app)

- TS/React, Canvas 2D, Web MIDI, `@tonejs/midi`, **GPL-3.0**. Reading only; porting code would make us GPL ([OQ2](../OPEN-QUESTIONS.md)).
- Model: flat time-sorted `SongNote{midiNote, track, time, duration}` + measures; hands are a per-song track→hand setting; no fingering, spelling, lyrics.
- Wait mode blocks on next note index; perfect/good windows; late/early matching; held-duration score. Good ideas to re-implement in Rust core.
- Bundled MIDI files have no license info: do not copy.
- Synth: FluidR3_GM samples (MIT) via WebAudio.

## musescore-downloader

- Browser extension rebuilding MuseScore's private API token to fetch PDF/MIDI/MP3. Taken down from Chrome store after MuseScore complaint (paywall/login circumvention).
- **Not used.** Circumventing access control risks ToS and anti-circumvention law.

## Legal sources

| Source | Format | License | Fit |
|---|---|---|---|
| OpenScore (MuseScore/IMSLP) | MusicXML/MSCZ | CC0 | best |
| Mutopia | LilyPond, MIDI, PDF | PD / CC-BY / CC-BY-SA per file | good |
| MuseScore user scores | MusicXML via site export | per score; default all rights reserved | only CC0/PD/CC-BY(-SA) + PD composition |
| IMSLP | mostly PDF scans | varies per edition | needs transcription |
| Own arrangements of PD tunes | our notation | CC-BY-SA | primary for beginner content |

Beginner levels need simplified arrangements anyway, so most curriculum content will be written by us; imports serve the song library.

## Follow-ups

- Bean: MusicXML importer in `tools/content-cli`. Update: the parser was built in `core/src/score_import` (`piano-gy3o`, [D37](../DECISIONS.md)); the CLI import, if still wanted, reuses it.
- Bean: curated list of 50 OpenScore/Mutopia pieces with licenses verified.
