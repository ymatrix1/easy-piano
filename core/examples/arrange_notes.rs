//! Runs the arranger on a transcription file and prints the arrangement.
//! Used to try personal song imports end to end (D11).
//!
//! Usage: cargo run --example arrange_notes -- <notes.txt> <bpm> <beginner|intermediate|advanced>
//! Input rows: `pitch start_s duration_s amplitude` (`#` lines ignored).
//! Output rows: `pitch beat beats hand` with hand `R` or `L`.

use easy_piano_core::arrange::{arrange, Level, RawNote};

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let [_, path, bpm, level] = args.as_slice() else {
        eprintln!("usage: arrange_notes <notes.txt> <bpm> <beginner|intermediate|advanced>");
        std::process::exit(2);
    };
    let level = match level.as_str() {
        "beginner" => Level::Beginner,
        "intermediate" => Level::Intermediate,
        "advanced" => Level::Advanced,
        other => panic!("unknown level {other}"),
    };
    let notes: Vec<RawNote> = std::fs::read_to_string(path)
        .unwrap_or_else(|e| panic!("{path}: {e}"))
        .lines()
        .filter(|l| !l.starts_with('#') && !l.trim().is_empty())
        .map(|l| {
            let r: Vec<f64> = l.split_whitespace().map(|x| x.parse().unwrap()).collect();
            RawNote { pitch: r[0] as u8, start: r[1], dur: r[2], amp: r[3] as f32 }
        })
        .collect();
    let bpm: f64 = bpm.parse().expect("bpm");
    for n in arrange(&notes, bpm, level) {
        println!("{} {} {} {}", n.pitch, n.beat, n.beats, if n.left_hand { "L" } else { "R" });
    }
}
