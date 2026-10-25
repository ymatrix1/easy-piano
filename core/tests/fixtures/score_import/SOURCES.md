# Score import fixtures

Real files used by `core/tests/score_import_real.rs` (spec `docs/specs/score-import-and-page-view.md` 5.3). Each file is unchanged from its source.

| File | Format | Source | License | Used for |
|---|---|---|---|---|
| `wtk1-prelude1.ly` | LilyPond 2.14.2 | Mutopia Project, BWV 846 Prelude 1, [mutopiaproject.org/ftp/BachJS/BWV846/wtk1-prelude1/](https://www.mutopiaproject.org/ftp/BachJS/BWV846/wtk1-prelude1/) | Public Domain (`copyright` in the header) | LilyPond parser vs the MIDI that LilyPond exported from the same file |
| `wtk1-prelude1.mid` | Standard MIDI, 3 tracks | Same Mutopia folder (LilyPond export) | Public Domain (as above) | Oracle for the LilyPond test |
| `lc6583477.mxl` | Compressed MusicXML 4.0, MuseScore 4.5.2 | OpenScore Lieder, "Just for Today" by Jane Bingham Abbott, [github.com/OpenScore/Lieder](https://github.com/OpenScore/Lieder) | CC0 (`rights` in the file) | MusicXML: piano part selection, measure count, hands |
| `piano-boogie-left-hand-pattern.mid` | Standard MIDI, 2 tracks, 480 ticks/beat | Wikimedia Commons, "Piano Boogie left hand pattern0001.mid" by Floorcleaner22, [commons.wikimedia.org](https://commons.wikimedia.org/wiki/File:Piano_Boogie_left_hand_pattern0001.mid) | CC0 (Commons license) | MIDI parser vs `mido` (independent reader) |

## Oracles

- LilyPond: the MIDI file that LilyPond wrote from the same source. Note count, pitches and onsets must match.
- MusicXML: counted with an independent script (ElementTree) for part P2: 483 sounding notes, 295 on staff 1, 188 on staff 2. A note with a tie stop is not counted (the parser merges it). Measure count 41 per part, time 3/4. The sung part P1 (102 notes) is left out.
- MIDI: `mido` reads the file: 65 notes, each with pitch, start and length in quarter notes (expected list in the test).

## Not used

- "Wedding Dress Piano.mid" (Commons, claimed public domain): the song is a copyrighted pop song, so the MIDI's licence is not verified. Not committed.
- Files in `references/` (MuseScore and other reference apps) are local only and not committed.
