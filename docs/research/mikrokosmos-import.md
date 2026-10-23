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
uv run python -m melody_model.mikrokosmos ../../data/mikrokosmos ../../content --pieces 1-153
```

Rules beyond `convert.py`: the key is the written signature (most pieces have none, so `C` or `Am`; `convert.py` would analyse modal pieces into keys like `Dm` that are not written); tempo is the score's metronome mark in the time signature's beat unit; a bar where one hand has two voices is refused (`convert.py` keeps only the top voice).

One course per Bartók volume (`mikrokosmos-1` … `-5`; pieces 1-36, 37-66, 67-96, 97-121, 122-139, 140-153). The dataset has 147 solo pieces (the six four-hand pieces are not in it); two voices per hand work since [D34](../DECISIONS.md).

| Volume | Pieces imported | Dataset pieces |
|---|---|---|
| I | 32 (1-11, 13-24, 26-31, 34-36) | 36 |
| II | 20 | 26 (43, 44, 55, 65 not in dataset) |
| III | 10 | 29 (68 not in dataset) |
| IV | 3 | 25 |
| V | 1 (No. 134) | 17 (127 not in dataset) |
| VI | 0 | 14 |
| **Total** | **66** | **147** |

Skipped (81), by reason:

| Reason | Count | Pieces |
|---|---|---|
| Meter change inside the piece | 20 | e.g. 12, 41, 71, 75, 77, 81, 87, 93, 109, 112, 117, 120, 126, 128, 129, 136, 137, 138, 141, 147 |
| Bar length wrong after OCR | 15 | 72, 78, 84, 91, 92, 96, 105, 106, 114, 118, 123, 124, 125, 135, 146 |
| Three or more voices in one hand | 11 | 60, 85, 89, 90, 94, 133, 140, 144, 149, 152, 153 |
| Meter the converter and app do not take (3/2, 6/4, 5/4, 5/8, 7/8, 8/8) | 10 | 32, 33, 48, 82, 100, 111, 113, 115, 150, 151 |
| Triplets, quintuplets or a 9/2 note | 7 | 25, 88, 102, 103, 130, 132, 148 |
| Tie into a different pitch (OCR) | 7 | 64, 86, 99, 107, 110, 116, 139 |
| Key change or five or more accidentals | 6 | 51, 57, 104, 121, 122, 131 |
| Double sharp or flat, or a note out of range | 5 | 108, 119, 142, 143, 145 |

Checks on the imported pieces:

- Notes per piece in the MusicXML (ties merged) equal the notes in the song JSON for all 66 pieces except No. 14, which differs by 3: a zero-length three-note chord in LH bar 1, an OMR artefact the converter drops. Voices are counted too (`RH2`, `LH2`).
- `content lint`: no errors.
- Round trips (`tests/test_convert.py`, `tests/test_tokenizer.py`): MusicXML round trip passes for every piece. The MIDI round trip skips pieces with a second voice or invisible rest (MIDI has neither) and pieces where MIDI merges ties or rests across bars into a length the format cannot hold; it matches pitches and rhythm on the rest once runs of rests are summed. The melody-model tokenizer refuses songs with `RH2`/`LH2` or `s:` (the model has no such tokens) instead of dropping notes; `difficulty.py` ignores spacers.

## What the source has and the lessons drop

Counted in the MusicXML of the 66 imported pieces, and compared with the printed page for Nos. 56 and 31 (notes and rhythm match):

| Mark | In the XML | In the lesson |
|---|---|---|
| Slurs | 1630 marks, 57 pieces | dropped |
| Staccato | 187, 14 pieces | dropped |
| Accents | 37, 4 pieces | dropped |
| Tenuto | 15, 3 pieces | dropped |
| Hairpins (crescendo, diminuendo) | 119, 20 pieces | dropped |
| Fermata | 8, 5 pieces (37, 47, 62, 73, 101) | dropped, note not lengthened |
| Pedal | 52, 3 pieces (47, 83, 97) | dropped |
| Grace notes | 4, 2 pieces (62, 134) | dropped, notes missing |
| Ties | 682, 38 pieces | kept |
| Repeats | 22 marks, 3 pieces (31, 40, 134) | written out in full |
| Dynamic letters (`p`, `f`) | none | none (the printed page has them: `f` on Nos. 31 and 56) |
| Fingering | none | none (the printed page has it) |
| Tempo words (Allegro, Risoluto) | none | none; only the metronome mark |

Notes in the XML were counted against the song JSON for all 66 pieces; only two pieces were compared with the printed page, so an OCR pitch error elsewhere is possible. Repeats were expanded after this check (No. 31: 16 to 24 bars, matching the printed `|: :|`; No. 40: 31 to 37; No. 134: 21 to 47).

No. 134 is three separate studies in double notes printed under one number, with repeats in each. It is one very dense lesson; splitting it into three is open (bean piano-gjig).

## Similarity

Bartók reuses his own material on purpose: No. 17 is No. 13's melody in contrary motion, No. 27 is No. 9 with a new left hand, No. 28 is a canon on No. 7. These pairs score 1.0 in `core::similarity`. Mikrokosmos pieces against the folk tunes in `content/songs` give 36 false positives in 992 pairs at 0.5 (3.6%, above the 3% the calibration allows): five-finger modal lines share stock figures with folk tunes. Like the drills, method pieces are left out of the calibration set (`core/tests/similarity_calibration.rs`). They stay in the `content similar` corpus, so a generated tune that copies them is flagged.

## App shape

- New section `methods` in `courses.json` and courses `mikrokosmos-1` (requires `piano-basics`) to `mikrokosmos-5` (each requires the previous book): one `song` node and one level per piece, in Bartók's order. Level: right hand alone (wait mode, with pre-listen), left hand alone (wait mode), both hands in play-along at 0.8× tempo, pass 0.7.
- Methods courses sit off the difficulty ramp: lint does not compare their levels with the main path, and calibration input (`content level --course`) leaves them out.
- Titles in en, pt-BR, es, fr and de as `node.mk<book>.NN`.
- Songs carry `restricted_in: [{"region": "US", "until": "2036-01-01"}]`. The app does not read the field yet.

## Implications

- The song format and the converter now cover 66 of 147 pieces. Meter changes, odd meters, triplets, a third voice and OCR errors in the dataset block the other 81, most of Volumes III-VI.
- The repository and the web build are public worldwide, so the US restriction is only metadata until the app filters by region and the content is kept out of the US build or served per region.
- Without fingering, the learner gets no finger hints in these pieces.

## Follow-ups

- App: hide `restricted_in` songs in restricted regions (bean piano-7os5).
- Two voices per hand: done (D34, bean piano-16vk).
- Expressive marks and grace notes (bean piano-gjig).
- The remaining 81 pieces: bean piano-weqs (meter changes, odd meters, tuplets, a third voice, hand fixes for OCR errors).
- Ask the dataset author for an explicit licence (CC-BY-4.0 or CC0) on the MusicXML (bean piano-xmga).
- Confirm which edition `IMSLP465640` is.
