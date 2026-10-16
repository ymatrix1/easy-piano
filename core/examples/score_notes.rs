//! Scores a transcription file against a truth melody with the arranger's
//! cleanup and melody steps. Used by the model benchmark (docs/research/song-import.md).
//!
//! Usage: cargo run --example score_notes -- <notes.txt> <truth_melody.txt>
//! notes.txt rows: `pitch start_s duration_s amplitude`; truth rows: `pitch start_s end_s`.
//! Lines starting with `#` are ignored.

use easy_piano_core::arrange::{clean, melody, note_f1, CleanConfig, RawNote};

fn rows(path: &str) -> Vec<Vec<f64>> {
    std::fs::read_to_string(path)
        .unwrap_or_else(|e| panic!("{path}: {e}"))
        .lines()
        .filter(|l| !l.starts_with('#') && !l.trim().is_empty())
        .map(|l| l.split_whitespace().map(|x| x.parse().unwrap()).collect())
        .collect()
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let [_, notes_path, truth_path] = args.as_slice() else {
        eprintln!("usage: score_notes <notes.txt> <truth_melody.txt>");
        std::process::exit(2);
    };
    let notes: Vec<RawNote> = rows(notes_path)
        .into_iter()
        .map(|r| RawNote { pitch: r[0] as u8, start: r[1], dur: r[2], amp: r[3] as f32 })
        .collect();
    let truth: Vec<(u8, f64)> = rows(truth_path).into_iter().map(|r| (r[0] as u8, r[1])).collect();
    let cleaned = clean(&notes, &CleanConfig::default());
    let tune = melody(&cleaned, 0.06);
    let fmt = |(p, r, f): (f64, f64, f64)| format!("P={p:.2} R={r:.2} F1={f:.2}");
    println!(
        "raw n={} {} | clean n={} {} | melody n={} {}",
        notes.len(),
        fmt(note_f1(&notes, &truth, 0.05)),
        cleaned.len(),
        fmt(note_f1(&cleaned, &truth, 0.05)),
        tune.len(),
        fmt(note_f1(&tune, &truth, 0.05)),
    );
}
