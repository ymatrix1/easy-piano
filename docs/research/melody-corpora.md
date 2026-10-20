# Melody corpora for the practice-tune model

Checked: 2026-10-20

Sources: licence files and READMEs fetched from each project (each licence claim links its source in the table); PDMX `PDMX.csv` metadata (Zenodo 15571083, counted locally 2026-10-20); `docs/research/score-formats-and-sources.md`; `.agents/rules/content-and-licensing.md`. Decisions: [D18](../DECISIONS.md) (NMD), [D19](../DECISIONS.md) (corpora), [D20](../DECISIONS.md) (model design).

Question: which symbolic melody corpora can we train a small model on, given that the trained weights ship in an open-source app and must be clean (no pop, no non-commercial or "no ML" terms)?

## Criteria

A corpus is **use** only when all hold:

1. Compositions are public domain in **both** regimes we ship to: life+70 (EU, UK, Brazil and most others: composer died ≤ 1955 as of 2026) **and** the US (published before 1931; the US uses publication date, not death year, for older works). Traditional tunes pass. A modern **arrangement** of a PD composition is its own work: it needs its own PD/CC0/CC-BY(-SA) status from the arranger.
2. The encoding (the file/data itself) is CC0, PD, CC-BY or CC-BY-SA, with no non-commercial, research-only or "no AI/ML" clause.
3. Licence lets us process it locally and ship a model trained on it. We never redistribute raw files (git-ignored `data/`).

## Candidates

| Corpus | Size | Format | Composition | Encoding licence | Training / weights | Verdict |
|---|---|---|---|---|---|---|
| [OpenScore Lieder](https://github.com/OpenScore/Lieder) | ~1,300 songs | MuseScore `.mscx` (MusicXML via MuseScore CLI) | mostly 19th c.; **per-composer death-year check** against the corpus's own `data/composers.yaml` (drop composers died > 1955 or US-published ≥ 1931) | CC0 ([README: "released under Creative Commons Zero (CC0)"](https://github.com/OpenScore/Lieder#license-and-acknowledgement)) | No restriction | **use** (voice line = melody; art song, wide ranges) |
| [PDMX](https://zenodo.org/records/15571083) `no_license_conflict` subset | 222,856 scores (counted) | MusicXML (`.mxl`) | mixed; uploader-tagged | dataset [CC-BY-4.0 (Zenodo record licence)](https://zenodo.org/records/15571083); files: subset holds **only** PD Mark (189,714) and CC0 (33,142), **no CC-BY/CC-BY-SA files** (counted from `PDMX.csv`) | Allowed: the [paper](https://arxiv.org/abs/2409.10831) calls it "fully commercially viable" | **use after pop screen + 50-tune sample approval** (see below) |
| [Mutopia](https://www.mutopiaproject.org/legal.html) | ~2,100 pieces, ~110 folk (est., site counts) | LilyPond (+ MIDI) | PD (per piece header) | per piece: PD, CC-BY, CC-BY-SA ([legal page](https://www.mutopiaproject.org/legal.html); `license` field in each `.ly` header) | Allowed; keep per-file attribution in provenance | **use** (fetch per piece, honour robots/ToS) |
| [Nottingham Music Database](https://abc.sourceforge.net/NMD/) ([cleaned, jukedeck](https://github.com/jukedeck/nottingham-dataset)) | ~1,000 tunes | ABC | traditional (jigs, reels, waltzes, carols) | original NMD: [no licence stated on the NMD page](https://abc.sourceforge.net/NMD/); jukedeck clean-up: [GPLv3 (README)](https://github.com/jukedeck/nottingham-dataset#readme); Ashover set: "IPR … reside with Mick Peat" ([NMD page](https://abc.sourceforge.net/NMD/)) | Unclear: GPLv3 on data is odd; does model trained on it inherit GPL? Original has no grant | **use, original files minus Ashover** ([D18](../DECISIONS.md), risk accepted by user) |
| Essen Folksong Collection ([CCARH](https://github.com/ccarh/essen-folksong-collection)) | ~6,250 songs | Humdrum **kern | traditional (mostly German, Chinese) | CCARH: "protected by copyright and … distributed by license only" ([README.txt](https://github.com/ccarh/essen-folksong-collection/blob/main/README.txt)); no derivative editions for commercial distribution ([license.txt](https://github.com/ccarh/essen-folksong-collection/blob/main/license.txt), clause 3) | Restrictive; shipped weights could be a derivative | **exclude** |
| [Meertens Tune Collections](https://www.liederenbank.nl/mtc/) | ~18k Dutch melodies | kern / MIDI | traditional | CC BY-NC-SA 3.0 ([MTC documentation](https://www.liederenbank.nl/mtc/)) | Non-commercial | **exclude** (NC conflicts with open-source app weights) |
| [The Session data](https://github.com/adactio/TheSession-data) | ~50k tune settings | ABC / JSON | traditional Irish | ODbL **plus a "Prohibition on LLM Use" clause** ([LICENSE.md](https://github.com/adactio/TheSession-data/blob/main/LICENSE.md)) | Forbidden in spirit (our model is a transformer LM over tokens) | **exclude** |
| music21 bundled corpus (Bach chorales etc.) | ~370 chorales + misc | MusicXML / kern | PD | per set; origin and licence **not verified** per set ([corpus folder](https://github.com/cuthbertLab/music21/tree/master/music21/corpus)); Bach chorale encodings are commonly traced to CCARH/Humdrum (unverified) | Unknown | **exclude** until each set's licence is verified |
| IMSLP | huge | mostly PDF scans; some MusicXML | per work | per file; many scans of copyrighted editions | Needs OMR; licence per file | **exclude for now** (cost, mixed licences) |
| Lakh MIDI, POP909, Wikifonia, MuseScore non-PD | – (not checked) | MIDI / MusicXML | copyrighted pop | – | – | **exclude** (decided: no pop). Lakh only allowed as local negative corpus for similarity check (PR #34), never for training |
| Our own songs (`content/songs/`) | 40 | song JSON | PD tunes, our arrangements | ours (project licence) | Allowed | **use** (small, but exact target format and level labels) |

## Additional candidates (checked 2026-10-20, not yet approved)

| Corpus | Size | Format | Composition | Encoding licence | Verdict (proposed) |
|---|---|---|---|---|---|
| [Open Hymnal Project](http://openhymnal.org/) | ~300 hymns (est.); one ABC bulk file (2 MB) | ABC | mostly PD hymn tunes | Project's own data files placed in the public domain; per-hymn exceptions carry their own terms in the ABC source ([copying page](http://openhymnal.org/copying.html)): "Each work in the Open Hymnal which is not in the public domain gives specific license terms … in the abc source file". Exceptions are typically **words-only, no alteration, all other rights reserved** | **use**, music only, after dropping any tune whose ABC header names a non-PD licence for the **music or setting** (words are discarded anyway). Simple, step-wise, 4-bar phrases: closest to beginner style |
| [OpenScore String Quartets](https://github.com/OpenScore/StringQuartets) | ~100 quartets (est., [OpenScore page](https://fourscoreandmore.org/openscore/)) | MuseScore (`.mscx`) | 18th–20th c.; per-composer check as for Lieder | CC0 ([README: "released under Creative Commons Zero (CC0)"](https://github.com/OpenScore/StringQuartets)) | **use later**: clean, but needs MuseScore CLI and gives instrumental first-violin lines, not singable melodies. Low priority |
| [Project Gutenberg music](https://www.gutenberg.org/ebooks/bookshelf/) | small (est. hundreds of items; MusicXML/MIDI only for some) | MusicXML / MIDI / LilyPond (varies) | US public domain | [PG licence](https://www.gutenberg.org/policy/license.html): after stripping the PG licence and name, "you are left with a text unrestricted by U.S. intellectual property law". PD status is **US only**; life+70 must be checked per item | **ask / low value**: clean in the US, small, mixed formats, per-item life+70 check needed |
| [CPDL](https://www.cpdl.org/wiki/index.php/ChoralWiki:CPDL) | 23k+ choral scores | per edition (PDF, MusicXML, MIDI, …) | mostly PD | per edition: PD **or** the [CPDL licence](https://www.cpdl.org/wiki/index.php/ChoralWiki:CPDL), a copyleft that requires derived works to be "licensed as a whole under the terms of this License" with notices | **exclude**: copyleft-on-derivatives would reach the weights question (OQ10) with a non-standard licence; per-edition sorting at that scale is costly |
| O'Neill's collections (1903 *Music of Ireland*, 1907 *Dance Music*, 1922 *Waifs and Strays*) via [John Chambers' ABC](https://trillian.mit.edu/~jc/music/book/ONeills/) | ~3,000 tunes (est.) | ABC | traditional / PD books | ABC typed by ~20 volunteers 1996–99; **no licence statement** on the page. The [HF mirror](https://huggingface.co/datasets/ecairol/oneills-irish-tunes-1850) claims "no separate license claim … faithful mechanical rendering" (a mirror's opinion, not a grant) | **ask**: same legal position as NMD (D18): transcription of PD books, no grant. If accepted, keep it a separate corpus like NMD |
| Ryan's Mammoth Collection (1883) | ~1,050 tunes (est.) | PD book; ABC transcriptions exist (individual sites, Facebook groups) | traditional / PD | **no clean source found**: no transcription with a stated licence; [ITMA](https://www.itma.ie/notated-collections/ryans-mammoth-collection-d/) offers scans, no ABC terms | **exclude** until a transcription with a clear licence is found (or we OCR the PD scans ourselves) |

Proposal: add **Open Hymnal** now (clean, small, beginner-like). **O'Neill's** only if you accept the NMD-style risk again (separate corpus, droppable). Keep String Quartets for later, skip Gutenberg, CPDL and Ryan's. Synthetic tunes from our rule generator (mg-foundations spike) remain the cleanest bulk source for pre-training.

## Expected clean data (estimates)

All numbers in this section are estimates made before the dataset build; measured counts come with the dataset PR.

| Set | Tunes (est.) | Notes |
|---|---|---|
| OpenScore Lieder | ~1,300 | phrases cut to 4–16 bars → ~10k fragments (est.) |
| Mutopia | ~500 usable melodic pieces | many are polyphonic; take top voice / folk set |
| Own songs | 40 | upweight |
| + PDMX filtered (if approved) | 20k–80k after filters | dominates; quality varies by rating |
| + Nottingham (if approved) | ~1,000 | closest to beginner-tune style |

Without PDMX the clean set is small (est. ~2k tunes, ~15k fragments after phrase cuts, ×12 transpositions). Enough for a ~5M-param model with heavy augmentation; PDMX makes 10–15M realistic.

## PDMX pop screen

Uploader tags are not proof. Rules applied by `tools/melody-model` (dataset step), in order:

| Rule | Why |
|---|---|
| `subset:no_license_conflict` and `subset:deduplicated` | public and internal licence agree |
| Genre tags only from classical, folk, religious, world | pop/rock/soundtrack/game uploads mostly carry those tags |
| **Composer missing** (161,919 of 222,856 in the subset, counted): **exclude**, unless `is_original` (uploader's own composition, dedicated CC0/PD by its author) | no composer = no way to check the composition's PD status |
| Composer present: must resolve to a person who died ≤ 1955 (life+70) with the work published before 1931 (US), via a committed composer → death-year table; otherwise exclude | jurisdiction rule above |
| Name/title blocklist (film, game, anime, pop names and titles) | catches mis-tagged uploads the table misses |
| Arrangements: keep only the melody part (first part); exclude scores whose title/subtitle says "arr.", "arranged by", "version", "cover", "easy piano" unless the uploader is the arranger (`is_original`) | a PD composition does not clear a modern arrangement; the melody line is the composition, the accompaniment belongs to the arranger |
| Similarity check (`content-cli similar`, threshold 0.6) against a local pop corpus in `references/melody-corpus/` | catches copies the metadata hides |
| **50-tune random sample** of the filtered set shown to the user; training waits for approval | human check of the screen |

Local pop corpus coverage today: **none** (`references/melody-corpus/` does not exist, checked 2026-10-20), so the similarity check currently compares only against our 40 songs. Follow-up: user places a local negative set (e.g. a Lakh MIDI subset) there; it is never used for training.

## Implications

- Provenance record lists every corpus, version/date, licence, file count and decision (D18, D19); CC-BY/CC-BY-SA sources need attribution in the app credits.
- Weights licence is unsettled: [OQ10](../OPEN-QUESTIONS.md) (does training on CC-BY-SA data make weights an adaptation?).
- NMD stays a separable corpus (`corpus: "nottingham"`) so it can be dropped and the model retrained (D18).
- Raw corpora live in git-ignored `data/`; only download scripts and manifests (source URL, licence, hash) are committed.

## Approved training set (user, 2026-10-20)

| Corpus | Scope |
|---|---|
| OpenScore Lieder | composers passing the death-year / US-publication check |
| Mutopia | pieces licensed PD, CC-BY or CC-BY-SA; attribution kept |
| Own songs (`content/songs/`) | all |
| PDMX | `no_license_conflict` subset after the pop screen above, **and** after the user approves a 50-tune sample |
| Nottingham Music Database | original NMD ABC files, **excluding the Ashover collection** and tunes credited to a named composer ([D18](../DECISIONS.md)) |

Everything else in the table above stays excluded.

## Model design (approved by user, 2026-10-20; [D20](../DECISIONS.md))

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

- Done: user approved the corpus set (D19) and NMD with risk (D18), 2026-10-20.
- Done: converters + tokenizer (PR #41, bean piano-lkg2).
- Gate before training: user approves a random 50-tune sample of the filtered PDMX set (bean piano-qpyc).
- Composer → death-year table for PDMX and OpenScore Lieder (dataset step).
- Local pop corpus for the similarity check (user).
- Weights licence: OQ10.
