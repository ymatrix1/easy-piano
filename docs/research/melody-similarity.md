# Melody similarity checker for generated tunes

Checked: 2026-10-20. Bean: piano-9h4q. Status: checker built (`core/src/similarity.rs`, `content similar`).

Sources: project home pages and licence files of the corpora below as known on the checked date (Lakh MIDI: colinraffel.com/projects/lmd; Nottingham: abc.sourceforge.net/NMD and github.com/jukedeck/nottingham-dataset; Essen: esac-data.org and kern.humdrum.org; The Session: github.com/adactio/TheSession-data; Mutopia: mutopiaproject.org; POP909: github.com/music-x-lab/POP909-Dataset; Meertens Tune Collections: liederenbank.nl/mtc). Licence rows marked "verify" were not confirmed against a licence file this session. Calibration: our own `content/songs` (40 songs).

## Question

Generated practice tunes (agent skill, Magenta.js, rules) must not closely copy a known melody, especially a copyrighted one, because our content is open source and clean-room ([content rule](../../.agents/rules/content-and-licensing.md)). How do we measure "close", against which corpus, and with what threshold?

## Method

| Step | Choice | Why |
|---|---|---|
| Melody | RH part of a song; top note per onset (skyline) for MIDI/ABC/MusicXML | Lead line is what listeners recognise |
| Token | interval to previous note (±12 clamp) + rhythm class `round(log2(IOI/prev IOI))` in -2..2 | Transposition-invariant; rhythm kept coarse |
| Measure 1 | interval 6-gram overlap: share of query 6-grams found in the candidate | Fast, catches long verbatim runs |
| Measure 2 | Smith-Waterman local alignment on intervals (match +4, rhythm agrees +1, mismatch -3, gap -4) normalised by the shorter melody | Finds a copied passage inside a longer tune, tolerates ornaments |
| Floor | both normalised over at least 16 tokens (`MIN_SPAN`) | A 4-note motif or 10-note scale cannot score 1.0 |
| Score | max(ngram, alignment), 0..1 | Either signal alone is enough to flag |

Rhythm only adds a bonus: a copy with changed rhythm still matches on pitch contour, which is what plagiarism cases mostly turn on.

## Calibration (our PD songs and drills vs each other)

`cargo run -- similar ../../content/songs --top 1` in `tools/content-cli`, each song against the other 39:

| Pair | Score | Note |
|---|---|---|
| cdefg-drill ~ e1-eighth-drill | 0.56 | same 5-note up/down scale |
| e3-waltz-drill ~ e2-f-waltz | 0.54 | sibling drills, same pattern |
| e1-boogie ~ e3-waltz-drill | 0.51 | |
| au-clair-de-la-lune ~ hot-cross-buns | 0.46 | highest pair of two real PD songs |
| ode-to-joy ~ cdefg-drill | 0.42 | shared stepwise run |

Positive controls: Ode to Joy transposed up a tone scores 1.00 against our `ode-to-joy`; an ABC file with its first 4 bars in the reference corpus scores 0.85. Unit test copies (transposed, all rhythms changed) score > 0.9; an invented leapy tune scores < 0.3.

**Default threshold 0.6** (`DEFAULT_THRESHOLD`): above every unrelated pair in our catalogue (max 0.56), well below real copies (≥ 0.85). Scores 0.45–0.6 deserve a human glance; generic scale runs live there.

## Corpora

| Corpus | Size, format | Content | Licence | Use |
|---|---|---|---|---|
| Our `content/songs` | 40 JSON | PD tunes + own drills | CC-BY-SA / CC0 | Default corpus, in git |
| Lakh MIDI (LMD) | ~176k MIDI | Mostly copyrighted pop/rock transcriptions | Dataset CC-BY 4.0; underlying songs copyrighted | Best "copyrighted reference": local only, never commit |
| POP909 | 909 MIDI | Chinese pop piano arrangements | Research release; songs copyrighted (verify terms) | Local only |
| Nottingham Music Database | ~1,000 ABC | British/US folk dance tunes | Tunes traditional; ABC files have no clear licence (verify) | Local only |
| Essen Folksong Collection | ~8,000 EsAC/kern | European folk songs | Research use; no open licence stated (verify) | Local only |
| The Session data dump | ~40k ABC settings | Irish trad tunes | Repository licence to verify (ODbL claimed) | Local only until verified |
| Meertens Tune Collections | ~18k kern/MIDI | Dutch folk songs | CC BY-NC-SA (verify) | Local only (NC) |
| Mutopia | ~2,000 LilyPond/MIDI | Classical PD | PD / CC per piece | Could be committed per piece, but not needed |

Rule: **no external corpus goes in git.** The reference corpus is whatever the user drops into `references/melody-corpus/` (git-ignored via `references/`). Recognisable copyrighted melodies (pop hooks, film themes, children's TV songs) are the real risk; Lakh MIDI is the practical way to cover them locally.

Supported corpus formats: our song JSON, MIDI (`.mid`, `.midi`, all channels but 10), ABC (`.abc`, multi-tune, key signature, chords), uncompressed MusicXML (`.musicxml`, `.xml`, first part). Not yet: compressed `.mxl`, kern, LilyPond.

## Usage

```
cd tools/content-cli
cargo run -- similar ../../content/songs/new-tune.json            # content/songs + references/melody-corpus
cargo run -- similar <dir> --corpus <dir> --corpus <dir2> --threshold 0.6 --top 3
```

Prints per song `ok`/`SIMILAR`, then top matches: score, ngram, alignment, matched note spans (query ~ candidate). Exits 1 when any song is at or above the threshold. A song is never compared with its own file.

## Implications

- Generation pipelines (piano-ze9t spike) must run `content similar` on every candidate and reject ≥ 0.6 before a human listens.
- Our own drills share scale fragments at ~0.5; that is expected and below threshold.
- Alignment is O(n·m) per pair: fine for hundreds of songs, slow for full Lakh (176k files). Large corpora need an n-gram index prefilter.

## Follow-ups

- n-gram inverted index prefilter for Lakh-scale corpora.
- `.mxl` (zip) and kern readers if a corpus needs them.
- Melody-track selection for MIDI (skyline picks accompaniment when it sits above the tune).
- Wire into `content lint` as a warning once generated songs land (separate bean; lint is owned by another change now).
