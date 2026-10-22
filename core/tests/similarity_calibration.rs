//! Calibrates the melody similarity threshold on the real songs in content/songs.
//! Positives: copies of each PD song (transposed, rhythm-varied, octave-displaced, a 12-note
//! passage inside an invented tune, an 8-note hook inside an invented tune). Negatives: every
//! pair of distinct PD songs, generic stepwise lines (scales, five-finger runs) and invented
//! tunes against every song. Prints precision/recall per threshold
//! (`cargo test --test similarity_calibration -- --nocapture`) and pins the default.

use easy_piano_core::similarity::{compare, info, melody_from_song, tokens, MelodyNote};
use easy_piano_core::song::Song;
use std::fs;
use std::path::Path;

const THRESHOLD: f64 = 0.5;

fn songs() -> Vec<Song> {
    let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("../content/songs");
    let mut out: Vec<Song> = fs::read_dir(&dir)
        .expect("content/songs")
        .flatten()
        .map(|e| Song::from_json(&fs::read_to_string(e.path()).unwrap()).unwrap())
        .collect();
    out.sort_by(|a, b| a.id.cmp(&b.id));
    out
}

fn is_drill(id: &str) -> bool {
    id.ends_with("-drill")
        || id.starts_with("e1-")
        || id.starts_with("e2-")
        || id.starts_with("e3-")
        || id == "c-finder"
}

/// Method-book pieces (`mikrokosmos-NNN`): short modal studies that reuse their own
/// material on purpose (No. 17 is No. 13 in contrary motion). Like drills, they stay
/// out of the calibration set; they are still in the `content similar` corpus.
fn is_method_piece(id: &str) -> bool {
    id.rsplit_once('-')
        .is_some_and(|(book, n)| book == "mikrokosmos" && n.len() == 3)
}

fn line(pitches: &[u8], beats: f64) -> Vec<MelodyNote> {
    pitches
        .iter()
        .enumerate()
        .map(|(i, &pitch)| MelodyNote {
            pitch,
            onset: i as f64 * beats,
        })
        .collect()
}

fn filler(len: usize, seed: u32) -> Vec<u8> {
    let mut x = seed;
    (0..len)
        .map(|_| {
            x = x.wrapping_mul(1_103_515_245).wrapping_add(12_345);
            55 + ((x >> 16) % 24) as u8
        })
        .collect()
}

/// `len` consecutive notes of `m` with the most distinctive intervals.
fn best_window(m: &[MelodyNote], len: usize) -> &[MelodyNote] {
    let t = tokens(m);
    let start = (0..=m.len() - len)
        .max_by(|&a, &b| {
            let ia = info(&t, &(a..a + len - 1).collect::<Vec<_>>());
            let ib = info(&t, &(b..b + len - 1).collect::<Vec<_>>());
            ia.total_cmp(&ib).then(b.cmp(&a))
        })
        .unwrap();
    &m[start..start + len]
}

fn inside(passage: &[MelodyNote], seed: u32) -> Vec<MelodyNote> {
    let mut p: Vec<u8> = filler(14, seed);
    p.extend(passage.iter().map(|n| n.pitch + 2));
    p.extend(filler(14, seed + 1));
    line(&p, 0.5)
}

#[test]
fn threshold_separates_copies_from_unrelated_tunes() {
    let all = songs();
    let pd: Vec<(&str, Vec<MelodyNote>)> = all
        .iter()
        .filter(|s| !is_drill(&s.id) && !is_method_piece(&s.id))
        .map(|s| (s.id.as_str(), melody_from_song(s)))
        .filter(|(_, m)| m.len() >= 16)
        .collect();
    assert!(pd.len() >= 15, "expected the PD song set");

    // (label, score)
    let mut pos: Vec<(String, f64)> = Vec::new();
    let mut neg: Vec<(String, f64)> = Vec::new();
    let score = |q: &[MelodyNote], c: &[MelodyNote]| compare("c", &tokens(q), &tokens(c)).score;
    for (k, (id, m)) in pd.iter().enumerate() {
        let k = k as u32 * 10;
        let shifted = |f: &dyn Fn(usize, &MelodyNote) -> MelodyNote| {
            m.iter()
                .enumerate()
                .map(|(i, n)| f(i, n))
                .collect::<Vec<_>>()
        };
        let transposed = shifted(&|_, n| MelodyNote {
            pitch: n.pitch + 5,
            onset: n.onset,
        });
        let rhythm = shifted(&|i, n| MelodyNote {
            pitch: n.pitch,
            onset: i as f64 * 0.5 + if i % 2 == 1 { 0.25 } else { 0.0 },
        });
        let octave = shifted(&|i, n| MelodyNote {
            pitch: if i % 5 == 2 { n.pitch + 12 } else { n.pitch },
            onset: n.onset,
        });
        for (kind, q) in [
            ("transposed", transposed),
            ("rhythm", rhythm),
            ("octave", octave),
            ("contained-12", inside(best_window(m, 12), k + 1)),
            ("hook-8", inside(best_window(m, 8), k + 3)),
        ] {
            pos.push((format!("{kind} {id}"), score(&q, m)));
        }
        for (other, om) in &pd[..] {
            if other < id {
                neg.push((format!("{id} ~ {other}"), score(m, om)));
            }
        }
    }
    let generic: Vec<(&str, Vec<u8>)> = vec![
        (
            "C scale up-down",
            vec![60, 62, 64, 65, 67, 69, 71, 72, 71, 69, 67, 65, 64, 62, 60],
        ),
        (
            "five-finger run",
            vec![
                60, 62, 64, 65, 67, 65, 64, 62, 60, 62, 64, 65, 67, 65, 64, 62, 60,
            ],
        ),
        (
            "G scale two octaves",
            vec![55, 57, 59, 60, 62, 64, 66, 67, 69, 71, 72, 74, 76, 78, 79],
        ),
        (
            "thirds broken",
            vec![60, 64, 62, 65, 64, 67, 65, 69, 67, 71, 69, 72],
        ),
        (
            "repeated-note drill",
            vec![
                60, 60, 62, 62, 64, 64, 65, 65, 67, 67, 65, 65, 64, 64, 62, 62, 60,
            ],
        ),
        ("invented A", filler(24, 101)),
        ("invented B", filler(24, 202)),
        ("invented C", filler(24, 303)),
    ];
    for (name, p) in &generic {
        for (id, m) in &pd {
            neg.push((format!("{name} ~ {id}"), score(&line(p, 1.0), m)));
        }
    }

    println!("{} positives, {} negatives", pos.len(), neg.len());
    println!("| threshold | recall | precision | FN | FP |");
    println!("|---|---|---|---|---|");
    for t in [0.4, 0.5, 0.55, 0.6, 0.65, 0.7, 0.8] {
        let tp = pos.iter().filter(|(_, s)| *s >= t).count();
        let fp = neg.iter().filter(|(_, s)| *s >= t).count();
        let precision = if tp + fp == 0 {
            1.0
        } else {
            tp as f64 / (tp + fp) as f64
        };
        println!(
            "| {t:.2} | {:.3} | {precision:.3} | {} | {fp} |",
            tp as f64 / pos.len() as f64,
            pos.len() - tp
        );
    }
    let mut misses: Vec<_> = pos.iter().filter(|(_, s)| *s < THRESHOLD).collect();
    misses.sort_by(|a, b| a.1.total_cmp(&b.1));
    let mut worst_neg: Vec<_> = neg.iter().collect();
    worst_neg.sort_by(|a, b| b.1.total_cmp(&a.1));
    println!("missed positives at {THRESHOLD}: {misses:?}");
    println!("top negatives: {:?}", &worst_neg[..14]);

    let recall = pos.iter().filter(|(_, s)| *s >= THRESHOLD).count() as f64 / pos.len() as f64;
    let fp = neg.iter().filter(|(_, s)| *s >= THRESHOLD).count();
    assert!(recall >= 0.95, "recall {recall} at {THRESHOLD}");
    assert!(
        fp as f64 <= 0.03 * neg.len() as f64,
        "{fp} false positives at {THRESHOLD}"
    );
}
