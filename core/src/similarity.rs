//! Melody similarity: guards generated practice tunes against copying a known melody.
//! See docs/research/melody-similarity.md.
//!
//! A melody becomes a sequence of tokens, one per note after the first: the pitch interval
//! to the previous note and a coarse rhythm ratio (this inter-onset interval over the
//! previous one). Intervals compare modulo 12, so transposition and octave displacement of
//! single notes both still match. The score comes from the best local alignment
//! (Smith-Waterman) of query and candidate:
//! - purity: share of the aligned span whose intervals match (rhythm is ignored, so a
//!   rhythm-varied copy still has purity 1);
//! - information: how distinctive the matched intervals are (leaps count more than repeats,
//!   a scale step in the same direction as the last one counts least);
//! - length: matched intervals.
//!
//! score = purity² × min(1, information / `HOOK_INFO`) × min(1, length / `HOOK_LEN`).
//! A copied 8-note hook with some leaps scores about 0.7–1.0 wherever it sits in either tune;
//! a shared scale run stays low. Calibration: core/tests/similarity_calibration.rs.
//! Interval 6-gram overlap is reported alongside as a second, alignment-free signal.

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
    /// Semitones from the previous note.
    pub interval: i8,
    /// round(log2(ioi / previous ioi)) clamped to -2..=2; 0 for the first token.
    pub rhythm: i8,
}

impl Token {
    /// Interval class used for matching: octave displacement folds away.
    pub fn class(self) -> i8 {
        self.interval.rem_euclid(12)
    }
}

/// Interval n-gram length for the overlap measure.
pub const NGRAM: usize = 6;
/// Information a matched span needs for a full score (see `info`).
pub const HOOK_INFO: f64 = 4.0;
/// Matched intervals a span needs for a full score (a 7-note phrase).
pub const HOOK_LEN: usize = 6;

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
        .map(|n| MelodyNote {
            pitch: n.pitch,
            onset: n.start_beat,
        })
        .collect();
    skyline(notes)
}

pub fn tokens(melody: &[MelodyNote]) -> Vec<Token> {
    let mut out = Vec::with_capacity(melody.len().saturating_sub(1));
    for i in 1..melody.len() {
        let interval = (melody[i].pitch as i16 - melody[i - 1].pitch as i16) as i8;
        let ioi = melody[i].onset - melody[i - 1].onset;
        let rhythm = if i >= 2 {
            let prev = melody[i - 1].onset - melody[i - 2].onset;
            if ioi > 0.0 && prev > 0.0 {
                (ioi / prev).log2().round().clamp(-2.0, 2.0) as i8
            } else {
                0
            }
        } else {
            0
        };
        out.push(Token { interval, rhythm });
    }
    out
}

/// How distinctive token `i` is given the one before it: repeat 0.3, step (1–2 semitones)
/// continuing the previous step's direction 0.05, other step 0.5, third/fourth 0.8, wider 1.0.
/// Intervals are read in their smallest octave-folded form.
fn weight(t: &[Token], i: usize) -> f64 {
    let folded = |x: Token| {
        let c = x.class();
        if c > 6 {
            c - 12
        } else {
            c
        }
    };
    let v = folded(t[i]);
    match v.unsigned_abs() {
        0 => 0.3,
        1 | 2 => {
            let prev = if i > 0 { folded(t[i - 1]) } else { 0 };
            if prev != 0 && prev.signum() == v.signum() && prev.unsigned_abs() <= 2 {
                0.05
            } else {
                0.5
            }
        }
        3 | 4 => 0.8,
        _ => 1.0,
    }
}

/// Total distinctiveness of `t[i]` for each index in `idx`.
pub fn info(t: &[Token], idx: &[usize]) -> f64 {
    idx.iter().map(|&i| weight(t, i)).sum()
}

fn ngrams(t: &[Token], n: usize) -> Vec<Vec<i8>> {
    if t.len() < n {
        return Vec::new();
    }
    t.windows(n)
        .map(|w| w.iter().map(|x| x.class()).collect())
        .collect()
}

/// Share of `query`'s octave-folded interval n-grams found anywhere in `cand`
/// (0 if the query is shorter than n).
pub fn ngram_overlap(query: &[Token], cand: &[Token], n: usize) -> f64 {
    let q = ngrams(query, n);
    if q.is_empty() {
        return 0.0;
    }
    let c: HashSet<Vec<i8>> = ngrams(cand, n).into_iter().collect();
    q.iter().filter(|g| c.contains(*g)).count() as f64 / q.len() as f64
}

/// Best local alignment and its score; spans are token ranges `[start, end)`.
#[derive(Debug, Clone, PartialEq)]
pub struct Alignment {
    pub score: f64,
    pub purity: f64,
    pub info: f64,
    pub query_span: (usize, usize),
    pub cand_span: (usize, usize),
}

const MATCH: i32 = 4;
const RHYTHM_BONUS: i32 = 1;
const MISMATCH: i32 = -6;
const GAP: i32 = -4;

fn pair(a: Token, b: Token) -> i32 {
    if a.class() == b.class() {
        MATCH
            + if a.rhythm == b.rhythm {
                RHYTHM_BONUS
            } else {
                0
            }
    } else {
        MISMATCH
    }
}

pub fn local_alignment(q: &[Token], c: &[Token]) -> Alignment {
    let (n, m) = (q.len(), c.len());
    let empty = Alignment {
        score: 0.0,
        purity: 0.0,
        info: 0.0,
        query_span: (0, 0),
        cand_span: (0, 0),
    };
    if n == 0 || m == 0 {
        return empty;
    }
    let w = m + 1;
    let mut h = vec![0i32; (n + 1) * w];
    let (mut best, mut bi, mut bj) = (0, 0, 0);
    for i in 1..=n {
        for j in 1..=m {
            let v = (h[(i - 1) * w + j - 1] + pair(q[i - 1], c[j - 1]))
                .max(h[(i - 1) * w + j] + GAP)
                .max(h[i * w + j - 1] + GAP)
                .max(0);
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
    let mut matched = Vec::new();
    while i > 0 && j > 0 && h[i * w + j] > 0 {
        let v = h[i * w + j];
        if v == h[(i - 1) * w + j - 1] + pair(q[i - 1], c[j - 1]) {
            if q[i - 1].class() == c[j - 1].class() {
                matched.push(i - 1);
            }
            i -= 1;
            j -= 1;
        } else if v == h[(i - 1) * w + j] + GAP {
            i -= 1;
        } else {
            j -= 1;
        }
    }
    let span = (bi - i).max(bj - j);
    let purity = matched.len() as f64 / span as f64;
    let inf = info(q, &matched);
    let score = purity.powi(2)
        * (inf / HOOK_INFO).min(1.0)
        * (matched.len() as f64 / HOOK_LEN as f64).min(1.0);
    Alignment {
        score,
        purity,
        info: inf,
        query_span: (i, bi),
        cand_span: (j, bj),
    }
}

/// One corpus entry's comparison with the query.
#[derive(Debug, Clone, PartialEq)]
pub struct Match {
    pub name: String,
    /// Alignment score, 0..=1.
    pub score: f64,
    pub ngram: f64,
    pub alignment: Alignment,
}

pub fn compare(name: &str, query: &[Token], cand: &[Token]) -> Match {
    let alignment = local_alignment(query, cand);
    Match {
        name: name.to_string(),
        score: alignment.score,
        ngram: ngram_overlap(query, cand, NGRAM),
        alignment,
    }
}

/// Compares the query with every corpus melody; best `top` first.
pub fn top_matches(query: &[Token], corpus: &[(&str, &[Token])], top: usize) -> Vec<Match> {
    let mut all: Vec<Match> = corpus
        .iter()
        .map(|(name, t)| compare(name, query, t))
        .collect();
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

    fn even(p: &[u8]) -> Vec<(u8, f64)> {
        p.iter().map(|&p| (p, 1.0)).collect()
    }

    // Ode to Joy (PD), first two phrases, quarter notes with dotted endings.
    fn ode() -> Vec<(u8, f64)> {
        [
            64, 64, 65, 67, 67, 65, 64, 62, 60, 60, 62, 64, 64, 62, 62, 64, 64, 65, 67, 67, 65, 64,
            62, 60, 60, 62, 64, 62, 60, 60,
        ]
        .iter()
        .enumerate()
        .map(|(i, &p)| {
            (
                p,
                if i == 12 || i == 26 {
                    1.5
                } else if i == 13 || i == 27 {
                    0.5
                } else {
                    1.0
                },
            )
        })
        .collect()
    }

    /// A leapy invented line, deterministic.
    fn filler(len: usize, seed: u32) -> Vec<(u8, f64)> {
        let mut x = seed;
        (0..len)
            .map(|_| {
                x = x.wrapping_mul(1_103_515_245).wrapping_add(12_345);
                (55 + ((x >> 16) % 24) as u8, 0.5)
            })
            .collect()
    }

    // Twinkle-style 8-note hook with leaps (PD).
    const HOOK: [u8; 8] = [60, 60, 67, 67, 69, 69, 67, 65];

    fn score(q: &[(u8, f64)], c: &[(u8, f64)]) -> Match {
        compare("c", &tokens(&mel(q)), &tokens(&mel(c)))
    }

    #[test]
    fn tokens_are_transposition_invariant() {
        let a = tokens(&mel(&ode()));
        let up: Vec<_> = ode().iter().map(|&(p, d)| (p + 5, d)).collect();
        assert_eq!(a, tokens(&mel(&up)));
        assert_eq!(
            a[0],
            Token {
                interval: 0,
                rhythm: 0
            }
        );
        assert_eq!(a[1].interval, 1);
    }

    #[test]
    fn transposed_rhythm_varied_copy_scores_high() {
        let copy: Vec<_> = ode()
            .iter()
            .enumerate()
            .map(|(i, &(p, _))| (p + 5, if i % 3 == 0 { 0.75 } else { 0.5 }))
            .collect();
        let m = score(&copy, &ode());
        assert!(m.score > 0.95, "{m:?}");
        assert!(m.ngram > 0.9, "{m:?}");
        assert_eq!(m.alignment.query_span, (0, ode().len() - 1));
    }

    #[test]
    fn octave_displaced_copy_scores_high() {
        let copy: Vec<_> = ode()
            .iter()
            .enumerate()
            .map(|(i, &(p, d))| (if i % 4 == 2 { p + 12 } else { p }, d))
            .collect();
        let m = score(&copy, &ode());
        assert!(m.score > 0.95, "{m:?}");
        assert!(m.ngram > 0.9, "{m:?}");
    }

    #[test]
    fn contained_copy_in_longer_tune_is_found() {
        // 12 notes of Ode to Joy inside a 40-note invented tune, and vice versa.
        let mut q = filler(14, 7);
        q.extend(ode()[..12].iter().map(|&(p, d)| (p + 2, d)));
        q.extend(filler(14, 9));
        let m = score(&q, &ode());
        assert!(m.score > 0.6, "{m:?}");
        assert_eq!(m.alignment.query_span, (14, 25));
        assert_eq!(m.alignment.cand_span, (0, 11));
        let back = score(&ode(), &q);
        assert!(back.score > 0.6, "{back:?}");
    }

    #[test]
    fn short_exact_hook_is_caught() {
        let mut q = filler(16, 3);
        q.extend(even(&HOOK).iter().map(|&(p, d)| (p + 3, d)));
        q.extend(filler(16, 4));
        let m = score(&q, &even(&HOOK));
        assert!(m.score >= 0.7, "{m:?}");
        // 6 of its notes still clear the default threshold of 0.5.
        let m6 = score(&q, &even(&HOOK[..6]));
        assert!(m6.score >= 0.5, "{m6:?}");
    }

    #[test]
    fn unrelated_tune_scores_low() {
        let other: Vec<_> = [
            60, 67, 64, 72, 69, 65, 74, 71, 67, 76, 72, 79, 62, 69, 66, 59, 64, 71, 68, 61,
        ]
        .iter()
        .map(|&p| (p, 0.5))
        .collect();
        let m = score(&other, &ode());
        assert!(m.score < 0.4, "{m:?}");
        assert_eq!(m.ngram, 0.0);
    }

    #[test]
    fn shared_scale_run_scores_low() {
        let up_down = even(&[60, 62, 64, 65, 67, 69, 71, 72, 71, 69, 67, 65, 64, 62, 60]);
        let mut other = filler(10, 5);
        other.extend(even(&[
            62, 64, 65, 67, 69, 71, 72, 74, 72, 71, 69, 67, 65, 64, 62,
        ]));
        let m = score(&up_down, &other);
        assert!(m.score < 0.5, "{m:?}");
    }

    #[test]
    fn skyline_keeps_top_note_per_onset() {
        let s = skyline(vec![
            MelodyNote {
                pitch: 60,
                onset: 0.0,
            },
            MelodyNote {
                pitch: 64,
                onset: 0.0,
            },
            MelodyNote {
                pitch: 62,
                onset: 1.0,
            },
        ]);
        assert_eq!(s.iter().map(|n| n.pitch).collect::<Vec<_>>(), vec![64, 62]);
    }

    #[test]
    fn top_matches_sorted_and_truncated() {
        let orig = tokens(&mel(&ode()));
        let other = tokens(&mel(&[(60, 1.0), (72, 1.0), (61, 1.0), (70, 1.0)]));
        let corpus = [("other", other.as_slice()), ("ode", orig.as_slice())];
        let top = top_matches(&orig, &corpus, 1);
        assert_eq!(top.len(), 1);
        assert_eq!(top[0].name, "ode");
        assert!((top[0].score - 1.0).abs() < 1e-9);
    }
}
