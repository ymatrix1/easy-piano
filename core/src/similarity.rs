//! Melody similarity: guards generated practice tunes against copying a known melody.
//! See docs/research/melody-similarity.md.
//!
//! A melody becomes a transposition-invariant sequence of tokens, one per note after the
//! first: the pitch interval to the previous note and a coarse rhythm ratio (this
//! inter-onset interval over the previous one). Two measures compare a query to a corpus
//! melody, both on intervals only so a rhythm-varied copy still matches:
//! - n-gram overlap: share of the query's interval n-grams that occur in the candidate;
//! - local alignment (Smith-Waterman): best matching passage, normalised by the shorter
//!   melody (at least `MIN_SPAN` tokens), with a small bonus when the rhythm ratio also agrees.
//! The reported score is the larger of the two, in 0..=1.

use crate::song::{Part, Song};
use std::collections::HashSet;

/// One melody note, times in beats.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct MelodyNote {
    pub pitch: u8,
    pub onset: f64,
}

/// Interval and rhythm-ratio class between a note and the one before it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct Token {
    /// Semitones, clamped to ±12 so octave displacement of a leap stays close.
    pub interval: i8,
    /// round(log2(ioi / previous ioi)) clamped to -2..=2; 0 for the first token.
    pub rhythm: i8,
}

/// Default interval n-gram length.
pub const NGRAM: usize = 6;

/// Keeps the highest note at each onset (skyline), sorted by time.
pub fn skyline(mut notes: Vec<MelodyNote>) -> Vec<MelodyNote> {
    notes.sort_by(|a, b| a.onset.total_cmp(&b.onset).then(b.pitch.cmp(&a.pitch)));
    notes.dedup_by(|b, a| (a.onset - b.onset).abs() < 1e-6);
    notes
}

/// Right-hand melody (top voice) of a song.
pub fn melody_from_song(song: &Song) -> Vec<MelodyNote> {
    let notes = song
        .timeline()
        .into_iter()
        .filter(|n| n.part == Part::Right)
        .map(|n| MelodyNote { pitch: n.pitch, onset: n.start_beat })
        .collect();
    skyline(notes)
}

pub fn tokens(melody: &[MelodyNote]) -> Vec<Token> {
    let mut out = Vec::with_capacity(melody.len().saturating_sub(1));
    for i in 1..melody.len() {
        let interval = (melody[i].pitch as i16 - melody[i - 1].pitch as i16).clamp(-12, 12) as i8;
        let ioi = melody[i].onset - melody[i - 1].onset;
        let rhythm = if i >= 2 {
            let prev = melody[i - 1].onset - melody[i - 2].onset;
            if ioi > 0.0 && prev > 0.0 { (ioi / prev).log2().round().clamp(-2.0, 2.0) as i8 } else { 0 }
        } else {
            0
        };
        out.push(Token { interval, rhythm });
    }
    out
}

fn ngrams(t: &[Token], n: usize) -> Vec<Vec<i8>> {
    if t.len() < n {
        return Vec::new();
    }
    t.windows(n).map(|w| w.iter().map(|x| x.interval).collect()).collect()
}

/// Share of `query`'s interval n-grams found anywhere in `cand`, over at least as many
/// n-grams as a `MIN_SPAN`-token query has (0 if the query is shorter than n).
pub fn ngram_overlap(query: &[Token], cand: &[Token], n: usize) -> f64 {
    let q = ngrams(query, n);
    if q.is_empty() {
        return 0.0;
    }
    let c: HashSet<Vec<i8>> = ngrams(cand, n).into_iter().collect();
    let floor = MIN_SPAN.saturating_sub(n) + 1;
    q.iter().filter(|g| c.contains(*g)).count() as f64 / q.len().max(floor) as f64
}

/// Best local alignment: normalised score and matched token spans `[start, end)` in each.
#[derive(Debug, Clone, PartialEq)]
pub struct Alignment {
    pub score: f64,
    pub query_span: (usize, usize),
    pub cand_span: (usize, usize),
}

const MATCH: i32 = 4;
const RHYTHM_BONUS: i32 = 1;
const MISMATCH: i32 = -3;
const GAP: i32 = -4;
/// Alignments are normalised by at least this many tokens, so a short drill (or a short
/// shared scale run) cannot score 1.0 by matching a few notes.
pub const MIN_SPAN: usize = 16;

pub fn local_alignment(q: &[Token], c: &[Token]) -> Alignment {
    let (n, m) = (q.len(), c.len());
    let empty = Alignment { score: 0.0, query_span: (0, 0), cand_span: (0, 0) };
    if n == 0 || m == 0 {
        return empty;
    }
    let w = m + 1;
    let mut h = vec![0i32; (n + 1) * w];
    let (mut best, mut bi, mut bj) = (0, 0, 0);
    for i in 1..=n {
        for j in 1..=m {
            let s = if q[i - 1].interval == c[j - 1].interval {
                MATCH + if q[i - 1].rhythm == c[j - 1].rhythm { RHYTHM_BONUS } else { 0 }
            } else {
                MISMATCH
            };
            let v = (h[(i - 1) * w + j - 1] + s).max(h[(i - 1) * w + j] + GAP).max(h[i * w + j - 1] + GAP).max(0);
            h[i * w + j] = v;
            if v > best {
                (best, bi, bj) = (v, i, j);
            }
        }
    }
    if best == 0 {
        return empty;
    }
    let (mut i, mut j) = (bi, bj);
    while i > 0 && j > 0 && h[i * w + j] > 0 {
        let v = h[i * w + j];
        let s = if q[i - 1].interval == c[j - 1].interval {
            MATCH + if q[i - 1].rhythm == c[j - 1].rhythm { RHYTHM_BONUS } else { 0 }
        } else {
            MISMATCH
        };
        if v == h[(i - 1) * w + j - 1] + s {
            i -= 1;
            j -= 1;
        } else if v == h[(i - 1) * w + j] + GAP {
            i -= 1;
        } else {
            j -= 1;
        }
    }
    let max = ((MATCH + RHYTHM_BONUS) * n.min(m).max(MIN_SPAN) as i32) as f64;
    Alignment { score: best as f64 / max, query_span: (i, bi), cand_span: (j, bj) }
}

/// One corpus entry's comparison with the query.
#[derive(Debug, Clone, PartialEq)]
pub struct Match {
    pub name: String,
    /// max(ngram, alignment), 0..=1.
    pub score: f64,
    pub ngram: f64,
    pub alignment: Alignment,
}

pub fn compare(name: &str, query: &[Token], cand: &[Token]) -> Match {
    let ngram = ngram_overlap(query, cand, NGRAM);
    let alignment = local_alignment(query, cand);
    Match { name: name.to_string(), score: ngram.max(alignment.score), ngram, alignment }
}

/// Compares the query with every corpus melody; best `top` first.
pub fn top_matches(query: &[Token], corpus: &[(String, Vec<Token>)], top: usize) -> Vec<Match> {
    let mut all: Vec<Match> = corpus.iter().map(|(name, t)| compare(name, query, t)).collect();
    all.sort_by(|a, b| b.score.total_cmp(&a.score));
    all.truncate(top);
    all
}

#[cfg(test)]
mod tests {
    use super::*;

    /// (pitch, beats) pairs laid end to end.
    fn mel(notes: &[(u8, f64)]) -> Vec<MelodyNote> {
        let mut t = 0.0;
        notes
            .iter()
            .map(|&(pitch, d)| {
                let n = MelodyNote { pitch, onset: t };
                t += d;
                n
            })
            .collect()
    }

    // Ode to Joy (PD), first two phrases, quarter notes with dotted endings.
    fn ode() -> Vec<(u8, f64)> {
        [64, 64, 65, 67, 67, 65, 64, 62, 60, 60, 62, 64, 64, 62, 62, 64, 64, 65, 67, 67, 65, 64, 62, 60, 60, 62, 64, 62, 60, 60]
            .iter()
            .enumerate()
            .map(|(i, &p)| (p, if i == 12 || i == 26 { 1.5 } else if i == 13 || i == 27 { 0.5 } else { 1.0 }))
            .collect()
    }

    #[test]
    fn tokens_are_transposition_invariant() {
        let a = tokens(&mel(&ode()));
        let up: Vec<_> = ode().iter().map(|&(p, d)| (p + 5, d)).collect();
        assert_eq!(a, tokens(&mel(&up)));
        assert_eq!(a[0], Token { interval: 0, rhythm: 0 });
        assert_eq!(a[1].interval, 1);
    }

    #[test]
    fn transposed_rhythm_varied_copy_scores_high() {
        let orig = tokens(&mel(&ode()));
        // Up a fourth, everything in eighths with some dotted pairs swapped in.
        let copy: Vec<_> = ode().iter().enumerate().map(|(i, &(p, _))| (p + 5, if i % 3 == 0 { 0.75 } else { 0.5 })).collect();
        let m = compare("ode", &tokens(&mel(&copy)), &orig);
        assert!(m.score > 0.9, "{m:?}");
        assert!(m.ngram > 0.9, "{m:?}");
        assert_eq!(m.alignment.query_span, (0, orig.len()));
    }

    #[test]
    fn copied_phrase_inside_new_tune_is_found_with_its_span() {
        let orig = tokens(&mel(&ode()));
        let mut q: Vec<(u8, f64)> = [72, 60, 69, 59, 71].iter().map(|&p| (p, 1.0)).collect();
        q.extend(ode()[..12].iter().map(|&(p, d)| (p + 2, d)));
        let m = compare("ode", &tokens(&mel(&q)), &orig);
        assert!(m.alignment.score > 0.6, "{m:?}");
        assert!(m.alignment.query_span.0 >= 4 && m.alignment.cand_span.0 <= 1, "{m:?}");
    }

    #[test]
    fn unrelated_tune_scores_low() {
        let orig = tokens(&mel(&ode()));
        // A leapy, invented line with no long stepwise runs.
        let other: Vec<_> = [60, 67, 64, 72, 69, 65, 74, 71, 67, 76, 72, 79, 62, 69, 66, 59, 64, 71, 68, 61]
            .iter()
            .map(|&p| (p, 0.5))
            .collect();
        let m = compare("ode", &tokens(&mel(&other)), &orig);
        assert!(m.score < 0.3, "{m:?}");
        assert_eq!(m.ngram, 0.0);
    }

    #[test]
    fn skyline_keeps_top_note_per_onset() {
        let s = skyline(vec![
            MelodyNote { pitch: 60, onset: 0.0 },
            MelodyNote { pitch: 64, onset: 0.0 },
            MelodyNote { pitch: 62, onset: 1.0 },
        ]);
        assert_eq!(s.iter().map(|n| n.pitch).collect::<Vec<_>>(), vec![64, 62]);
    }

    #[test]
    fn top_matches_sorted_and_truncated() {
        let orig = tokens(&mel(&ode()));
        let other = tokens(&mel(&[(60, 1.0), (72, 1.0), (61, 1.0), (70, 1.0)]));
        let corpus = vec![("other".to_string(), other), ("ode".to_string(), orig.clone())];
        let top = top_matches(&orig, &corpus, 1);
        assert_eq!(top.len(), 1);
        assert_eq!(top[0].name, "ode");
        assert!((top[0].score - 1.0).abs() < 1e-9);
    }
}
