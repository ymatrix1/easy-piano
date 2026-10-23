# Mikrokosmos Book 1 import

- **Checked:** 2026-10-22
- **Sources:** [Mikrokosmos-difficulty dataset](https://github.com/PRamoneda/Mikrokosmos-difficulty) (README, `metadata/mikrokosmos_metadata.csv`, `musicxml/1-66.xml`, last commit 2022-08-04); [IMSLP: Mikrokosmos, Sz.107](https://imslp.org/wiki/Mikrokosmos,_Sz.107_(Bart%C3%B3k,_B%C3%A9la)); [Brazilian Law 9.610/1998, art. 41](https://www.planalto.gov.br/ccivil_03/leis/l9610.htm); [methods spike](piano-method-library-spike.md)
- **Question:** Can the dataset's MusicXML become a playable Methods course, and what does that take in format, tooling and rights?

## Rights findings

| Item | Finding |
|---|---|
| Composition | Bartók died 1945: public domain in Brazil and the EU since 2016 (70 years p.m.a.). First published 1940 (Boosey & Hawkes); IMSLP says protected in the USA until 2036-01-01. |
| Dataset MusicXML | No `LICENSE` file, empty `<rights>`; `<source>` says "Mikrokosmos expired copy-right edition. Transcribed by Pedro Ramoneda to MusicXML". OMR plus manual correction of an IMSLP PDF (`IMSLP465640`). |
| Source edition | Not verified which IMSLP edition `IMSLP465640` is (1940 Boosey & Hawkes or the 1987 "New Definitive Edition"). The IMSLP page lists both as public domain outside the USA. |
| Fingering | The MusicXML has no fingering marks, so the songs carry none. |

The user decided on 2026-10-22 to use the dataset XML and publish ("pode usar o xml do repo e codificar, vamos publicar"). The licence position and the US term are recorded in [D33](../DECISIONS.md) (proposed).

## Conversion

`tools/melody-model/melody_model/mikrokosmos.py` (on top of `convert.py`):

```
cd tools/melody-model
uv run python -m melody_model.mikrokosmos ../../data/mikrokosmos ../../content --pieces 1-36
```

Rules beyond `convert.py`: the key is the written signature (most pieces have none, so `C` or `Am`; `convert.py` would analyse modal pieces into keys like `Dm` that are not written); tempo is the score's metronome mark in the time signature's beat unit; a bar where one hand has two voices is refused (`convert.py` keeps only the top voice).

| Pieces 1-36 | Result |
|---|---|
| Imported (32) | 1-11, 13-24, 26-31, 34-36 |
| No. 12 Reflection | two voices in one hand (bar 12); also a 2/2-3/2 meter change |
| No. 25 Imitation and Inversion (2) | triplets (2/3-quarter durations) |
| No. 32 In Dorian Mode | 3/2 time, not in the converter's list |
| No. 33 Slow Dance | 6/4 time, not in the converter's list |

Checks on the 32 pieces:

- Notes per piece in the MusicXML (ties merged) equal the notes in the song JSON for 31 pieces. No. 14 differs by 3: a zero-length three-note chord in LH bar 1, an OMR artefact, which the converter drops.
- `content lint`: no errors. Difficulty model levels: 27 pieces at 3, 4 at 4, 1 at 5.
- MIDI round trip (`tests/test_convert.py`): pitches and rhythm match once runs of rests are summed (MIDI stores no rests; `r:4 r:4` returns as `r:2`). Two pieces end with a hand resting through the last bar, which MIDI cannot carry; that test skips them.

## Similarity

Bartók reuses his own material on purpose: No. 17 is No. 13's melody in contrary motion, No. 27 is No. 9 with a new left hand, No. 28 is a canon on No. 7. These pairs score 1.0 in `core::similarity`. Mikrokosmos pieces against the folk tunes in `content/songs` give 36 false positives in 992 pairs at 0.5 (3.6%, above the 3% the calibration allows): five-finger modal lines share stock figures with folk tunes. Like the drills, method pieces are left out of the calibration set (`core/tests/similarity_calibration.rs`). They stay in the `content similar` corpus, so a generated tune that copies them is flagged.

## App shape

- New section `methods` in `courses.json` and course `mikrokosmos-1` (requires `piano-basics`): one `song` node and one level per piece, in Bartók's order. Level: right hand alone (wait mode, with pre-listen), left hand alone (wait mode), both hands in play-along at 0.8× tempo, pass 0.7.
- Methods courses sit off the difficulty ramp: lint does not compare their levels with the main path, and calibration input (`content level --course`) leaves them out.
- Titles in en, pt-BR, es, fr and de as `node.mk1.NN`.
- Songs carry `restricted_in: [{"region": "US", "until": "2036-01-01"}]`. The app does not read the field yet.

## Implications

- The song format and the converter cover most of Book 1 as written. Meter changes, triplets and two voices per hand block the rest of Book 1 and much of Books 2-6.
- The repository and the web build are public worldwide, so the US restriction is only metadata until the app filters by region and the content is kept out of the US build or served per region.
- Without fingering, the learner gets no finger hints in these pieces.

## Follow-ups

- App: hide `restricted_in` songs in restricted regions (bean piano-7os5).
- Two voices per hand: spec and D34, implementation bean piano-16vk.
- Import the rest of Books 1-6 (bean piano-s1iz, supersedes piano-zn4c).
- Ask the dataset author for an explicit licence (CC-BY-4.0 or CC0) on the MusicXML (bean piano-xmga).
- Confirm which edition `IMSLP465640` is.
