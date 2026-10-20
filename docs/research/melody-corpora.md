# Melody corpora for the practice-tune model

Checked: 2026-10-20

Sources: licence files and READMEs fetched from each project (links in the table); `docs/research/score-formats-and-sources.md`; `.agents/rules/content-and-licensing.md`. Nothing downloaded beyond licence/README text.

Question: which symbolic melody corpora can we train a small model on, given that the trained weights ship in an open-source app and must be clean (no pop, no non-commercial or "no ML" terms)?

## Criteria

A corpus is **use** only when all hold:

1. Compositions are public domain (traditional, or composer died > 70 years ago).
2. The encoding (the file/data itself) is CC0, PD, CC-BY or CC-BY-SA, with no non-commercial, research-only or "no AI/ML" clause.
3. Licence lets us process it locally and ship a model trained on it. We never redistribute raw files (git-ignored `data/`).

## Candidates

| Corpus | Size | Format | Composition | Encoding licence | Training / weights | Verdict |
|---|---|---|---|---|---|---|
| [OpenScore Lieder](https://github.com/OpenScore/Lieder) | ~1,300 songs | MuseScore / MusicXML | PD (19th c.) | CC0 | No restriction | **use** (voice line = melody; art song, wide ranges) |
| [PDMX](https://zenodo.org/records/15571083) `no_license_conflict` subset | ~223k scores | MusicXML (JSON) | mixed; per-file PD Mark or CC0 per MuseScore metadata | dataset CC-BY; files PD/CC0 | Allowed (paper: "commercially viable") | **ask** – largest source, but user-tagged: some "PD" uploads are modern pop arrangements. Needs our own filter (composer death year, title blocklist, similarity check vs pop corpus) |
| [Mutopia](https://www.mutopiaproject.org/legal.html) | ~2,100 pieces, ~110 folk | LilyPond | PD | per piece: PD, CC-BY, CC-BY-SA | Allowed; keep per-file attribution in provenance | **use** (fetch per piece, honour robots/ToS) |
| [Nottingham Music Database](https://abc.sourceforge.net/NMD/) ([cleaned, jukedeck](https://github.com/jukedeck/nottingham-dataset)) | ~1,000 tunes | ABC | traditional (jigs, reels, waltzes, carols) | original NMD: no licence stated; jukedeck clean-up: GPLv3; Ashover set: "IPR with Mick Peat" | Unclear: GPLv3 on data is odd; does model trained on it inherit GPL? Original has no grant | **ask** – musically ideal (simple folk, chords). Option: use original NMD minus Ashover, treating ABC transcriptions of trad tunes as uncopyrightable facts; or skip |
| Essen Folksong Collection ([CCARH](https://github.com/ccarh/essen-folksong-collection)) | ~6,250 songs | Humdrum **kern | traditional (mostly German, Chinese) | CCARH licence: "distributed by license only", no derivative editions for commercial distribution | Restrictive; shipped weights could be a derivative | **exclude** |
| [Meertens Tune Collections](https://www.liederenbank.nl/mtc/) | ~18k Dutch melodies | kern / MIDI | traditional | CC BY-NC-SA 3.0 | Non-commercial | **exclude** (NC conflicts with open-source app weights) |
| [The Session data](https://github.com/adactio/TheSession-data) | ~50k tune settings | ABC / JSON | traditional Irish | ODbL **plus a clause forbidding use with or training of Large Language Models** | Forbidden in spirit (our model is a transformer LM over tokens) | **exclude** |
| music21 bundled corpus (Bach chorales etc.) | ~370 chorales + misc | MusicXML / kern | PD | mixed; several sets originate from CCARH MuseData/Humdrum | Inherits CCARH terms for those sets | **exclude** unless a CC0 re-encoding is found (OpenScore has none yet) |
| IMSLP | huge | mostly PDF scans; some MusicXML | per work | per file; many scans of copyrighted editions | Needs OMR; licence per file | **exclude for now** (cost, mixed licences) |
| Lakh MIDI, POP909, Wikifonia, MuseScore non-PD | – | MIDI / MusicXML | copyrighted pop | – | – | **exclude** (decided: no pop). Lakh only allowed as local negative corpus for similarity check (PR #34), never for training |
| Our own songs (`content/songs/`) | 40 | song JSON | PD tunes, our arrangements | ours (project licence) | Allowed | **use** (small, but exact target format and level labels) |

## Expected clean data

| Set | Tunes (est.) | Notes |
|---|---|---|
| OpenScore Lieder | ~1,300 | phrases cut to 4–16 bars → ~10k fragments |
| Mutopia | ~500 usable melodic pieces | many are polyphonic; take top voice / folk set |
| Own songs | 40 | upweight |
| + PDMX filtered (if approved) | 20k–80k after filters | dominates; quality varies by rating |
| + Nottingham (if approved) | ~1,000 | closest to beginner-tune style |

Without PDMX the clean set is small (~2k tunes, ~15k fragments after phrase cuts, ×12 transpositions). Enough for a ~5M-param model with heavy augmentation; PDMX makes 10–15M realistic.

## Implications

- Weights provenance record lists every corpus, version/date, licence and file count; CC-BY/CC-BY-SA sources need attribution in the app credits. CC-BY-SA data: whether weights are an "adaptation" is unsettled; propose treating weights as CC-BY-SA-compatible (decision to be proposed with the weights licence).
- PDMX needs our own pop filter before use: composer death year ≤ 1955 or "Traditional", reject titles matching a pop blocklist, and run the similarity checker (`tools/content-cli similar`) against a local pop corpus; drop hits ≥ 0.6.
- Raw corpora live in git-ignored `data/`; only download scripts and manifests (source URL, licence, hash) are committed.

## Approved training set (user, 2026-10-20)

| Corpus | Scope |
|---|---|
| OpenScore Lieder | all |
| Mutopia | pieces licensed PD, CC-BY or CC-BY-SA; attribution kept |
| Own songs (`content/songs/`) | all |
| PDMX | `no_license_conflict` subset, after pop filter (composer death year / Traditional, title blocklist, similarity < 0.6) |
| Nottingham Music Database | original NMD ABC files, **excluding the Ashover collection** |

Everything else in the table above stays excluded.

## Model design (approved by user, 2026-10-20)

How the corpus will be used; recorded here so later step PRs build on it.

| # | Choice | Data consequence |
|---|---|---|
| 1 | Compound note tokens (REMI/compound): one step = (pitch, duration, finger[, hand]); spec prefix, `BAR`, `END`. Exact round-trip with song JSON | Converters must yield fingering (from `core/src/arrange.rs` when source has none) |
| 2 | Two-level generation: bar-level form plan (A A' B A, per-bar cadence stable/open, contour up/down/flat), then notes conditioned on plan + spec | Plan labels derived automatically per tune: bar similarity clustering, last-note scale degree, contour |
| 3 | Fill-in-the-middle objective on the same decoder: `<prefix> <suffix> <middle>` | Dataset builder emits FIM samples (random bar spans) alongside left-to-right ones |
| 4 | Constrained search at inference: sample/beam many, score spec coverage, cadence (tonic end), repetition, melody score, similarity (`content-cli similar`, threshold 0.6); rubric is hard gate | Train-set similarity index built from the same corpus |
| 5 | Later: preference tuning (DPO) on blind ratings from `tools/listening-test/` | Keep generation ids + ratings linkable |

Backbone stays a small decoder-only transformer (5–15M params) for a simple ONNX int8 / onnxruntime-web path.

## Follow-ups

- Done: user approved the set above (2026-10-20).
- Bean: converters (MusicXML, LilyPond via `lilypond`/`musicxml2ly` round trip, ABC) + tokenizer.
- Decision (proposed): model weights licence and training-data provenance record.
