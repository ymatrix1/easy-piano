# Melody similarity checker for generated tunes

Checked: 2026-10-20. Bean: piano-9h4q. Status: checker built (`core/src/similarity.rs`, `content similar`).

Sources: our own `content/songs` (40 songs) for calibration; corpus home pages named below from general knowledge. **No licence file of any external corpus was fetched in this work**; every external licence cell below is "not verified" until someone reads the corpus's own licence file and links it here.

## Question

Generated practice tunes (agent skill, Magenta.js, rules) must not closely copy a known melody, especially a copyrighted one, because our content is open source and clean-room ([content rule](../../.agents/rules/content-and-licensing.md)). How do we measure "close", against which corpus, and with what threshold?

## Method

| Step | Choice | Why |
|---|---|---|
| Melody | RH part of a song, top note per onset. MIDI: the (track, channel) that owns most of the combined skyline; drums dropped | Lead line is what listeners recognise |
| Token | interval to previous note + rhythm class `round(log2(IOI/prev IOI))` in -2..2 | Transposition-invariant |
| Interval match | equal modulo 12 | Octave-displaced notes still match |
| Alignment | Smith-Waterman on intervals: match +4 (+1 if rhythm class agrees), mismatch -6, gap -4 | Finds a copied passage anywhere in either tune; rhythm only breaks ties |
| Purity | matched intervals / aligned span | Penalises loose alignments |
| Information | per matched interval: repeat 0.3, step continuing the previous step's direction 0.05, other step 0.5, 3–4 semitones 0.8, wider 1.0 | Scale runs and repeated notes are generic; leaps make a hook recognisable |
| Score | purity² × min(1, info / 4.0) × min(1, matched / 6) | Exact 7-note phrase with some shape → near 1; short or generic matches stay low |
| Side signal | share of query interval 6-grams (mod 12) found in candidate | Printed, not scored |

The score is local: it does not depend on how long either tune is, so a hook copied into a long tune scores the same as on its own.

## Calibration

`cargo test --test similarity_calibration -- --nocapture` in `core/` (fixture test, runs in CI with `cargo test`). Built from the 16 PD songs in `content/songs` with ≥ 16 melody notes (drills and method-book pieces excluded, see [mikrokosmos-import](mikrokosmos-import.md#similarity)):

- **Positives (80)**, 5 per song: transposed up a fourth; all rhythms replaced; every 5th note an octave up; the song's most distinctive 12-note passage inside 28 invented notes; its most distinctive 8-note hook inside 28 invented notes.
- **Negatives (248)**: every pair of distinct PD songs (120); 5 generic stepwise lines (scales, five-finger run, broken thirds, repeated-note drill) and 3 invented tunes against every song (128).

| threshold | recall | precision | FN | FP |
|---|---|---|---|---|
| 0.40 | 1.000 | 0.825 | 0 | 17 |
| **0.50** | **1.000** | **0.920** | **0** | **7** |
| 0.55 | 1.000 | 0.920 | 0 | 7 |
| 0.60 | 0.975 | 0.940 | 2 | 5 |
| 0.65 | 0.963 | 0.963 | 3 | 3 |
| 0.70 | 0.963 | 0.975 | 3 | 2 |
| 0.80 | 0.938 | 0.987 | 5 | 1 |

**Default threshold 0.5** (`DEFAULT_THRESHOLD`, pinned by the test: recall ≥ 0.95, FP ≤ 3%). At 0.6 two 8-note hooks (Minuet in G, Go Tell Aunt Rhody) slip under. The 7 "false" positives at 0.5 are mostly real shared fragments, not noise: the repeated-note drill vs Twinkle (0.83), Oh Susanna vs Greensleeves (0.79, an identical 8-note interval run), Mary Had a Little Lamb vs Jingle Bells (0.67, the repeated-E figure), Camptown Races / When the Saints vs Auld Lang Syne (~0.6), and one invented tune vs Amazing Grace (0.56). Treat a flag as "a human listens", not "reject".

On the whole catalogue (`content similar ../../content/songs`), 26 of 40 songs flag at 0.5, 21 at 0.6, 5 at 0.7: drills reuse each other's patterns on purpose, and folk tunes share stock figures. For generated tunes the check should run against PD songs and the reference corpus, and drills should be compared only with each other when looking for accidental duplicates.

Unit tests (`core/src/similarity.rs`): transposed + rhythm-varied Ode to Joy > 0.95; octave-displaced copy > 0.95; 12-note Ode passage inside a 40-note tune > 0.6 both ways, with exact spans; 8-note hook inside invented notes ≥ 0.7, its first 6 notes ≥ 0.5; unrelated leapy tune < 0.4; shared scale run < 0.5. CLI test (`tools/content-cli/src/similar.rs`): Ode to Joy in D vs an ABC reference with its first 4 bars in C exits 1.

## Corpora

| Corpus | Size, format | Content | Licence | Use |
|---|---|---|---|---|
| Our `content/songs` | 40 JSON | PD tunes + own drills | CC-BY-SA / CC0 (per file) | Default corpus, in git |
| Lakh MIDI (colinraffel.com/projects/lmd) | ~176k MIDI | Mostly transcriptions of copyrighted pop/rock | not verified (dataset reported as CC-BY 4.0; underlying songs copyrighted either way) | Best copyrighted reference; local only |
| POP909 (github.com/music-x-lab/POP909-Dataset) | 909 MIDI | Pop song piano arrangements | not verified; songs copyrighted | Local only |
| Nottingham Music Database (abc.sourceforge.net/NMD) | ~1,000 ABC | British/US folk dance tunes | not verified; tunes traditional | Local only |
| Essen Folksong Collection (esac-data.org) | ~8,000 EsAC/kern | European folk songs | not verified | Local only; kern reader needed |
| The Session data (github.com/adactio/TheSession-data) | ~40k ABC settings | Irish trad tunes | not verified | Local only |
| Meertens Tune Collections (liederenbank.nl/mtc) | ~18k kern/MIDI | Dutch folk songs | not verified | Local only |
| Mutopia (mutopiaproject.org) | ~2,000 LilyPond/MIDI | Classical | PD / CC per piece (per-file field, not verified here) | Local; not needed in git |

Rule: **no external corpus goes in git.** The reference corpus is whatever the user drops into `references/melody-corpus/` (git-ignored via `references/`). Recognisable copyrighted melodies (pop hooks, film themes, children's TV songs) are the real risk; a Lakh MIDI subset is the practical way to cover them locally.

Corpus formats read: song JSON, MIDI (`.mid`, `.midi`), ABC (`.abc`; multi-tune, key signatures, bar-scoped accidentals, chords), uncompressed MusicXML (`.musicxml`, `.xml`, first part). Not yet: `.mxl`, kern, LilyPond.

## Usage

```
cd tools/content-cli
cargo run -- similar ../../content/songs/new-tune.json        # content/songs + references/melody-corpus if present
cargo run -- similar <song.json|dir>... --corpus <dir> --corpus <dir2> --threshold 0.5 --top 3
```

Per song: `ok`/`SIMILAR`, then top matches with score, purity, info, 6-gram overlap and matched note spans (query ~ candidate). A song is never compared with its own file. Exit codes: 0 clear, 1 a song at or above threshold, 2 usage or input error (unknown flag, bad value, missing path, non-JSON input file, no songs found, missing or empty corpus, unreadable song).

## Implications

- Generation pipelines (piano-ze9t) run `content similar` on every candidate against PD songs + reference corpus; ≥ 0.5 goes to a human, ≥ 0.7 is rejected outright.
- Purely stepwise phrases (e.g. the first 8 notes of Ode to Joy alone, score ≈ 0.4) are not flagged by design; longer stepwise copies are.
- Alignment is O(n·m) per pair, corpus tokens are built once: fine for thousands of tunes, slow for full Lakh.

## Follow-ups

- n-gram inverted index prefilter for Lakh-scale corpora.
- Verify and link each external corpus licence file.
- `.mxl` (zip) and kern readers.
- Wire into `content lint` as a warning once generated songs land (lint is changing in parallel).
