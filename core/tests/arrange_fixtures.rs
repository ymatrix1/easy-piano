//! Measures the arranger on real Basic Pitch output captured from the song
//! import spike (synthetic PD audio; see tests/fixtures/*.txt headers).
//! Run with `cargo test -- --nocapture` to see the numbers.

use easy_piano_core::arrange::{arrange, clean, melody, note_f1, CleanConfig, Level, RawNote};

const BPM: f64 = 100.0;

fn rows(text: &str) -> Vec<Vec<f64>> {
    text.lines()
        .filter(|l| !l.starts_with('#') && !l.trim().is_empty())
        .map(|l| l.split_whitespace().map(|x| x.parse().unwrap()).collect())
        .collect()
}

fn raw(text: &str) -> Vec<RawNote> {
    rows(text)
        .into_iter()
        .map(|r| RawNote {
            pitch: r[0] as u8,
            start: r[1],
            dur: r[2],
            amp: r[3] as f32,
        })
        .collect()
}

fn truth() -> Vec<(u8, f64)> {
    rows(include_str!("fixtures/truth_melody.txt"))
        .into_iter()
        .map(|r| (r[0] as u8, r[1]))
        .collect()
}

const SETS: [(&str, &str); 3] = [
    ("piano", include_str!("fixtures/bp_piano.txt")),
    ("mix", include_str!("fixtures/bp_mix.txt")),
    ("other", include_str!("fixtures/bp_other.txt")),
];

#[test]
fn cleanup_and_skyline_recover_the_melody() {
    let truth = truth();
    for (name, text) in SETS {
        let notes = raw(text);
        let before = note_f1(&notes, &truth, 0.05);
        let cleaned = clean(&notes, &CleanConfig::default());
        let after_clean = note_f1(&cleaned, &truth, 0.05);
        let tune = melody(&cleaned, 0.06);
        let after_melody = note_f1(&tune, &truth, 0.05);
        println!(
            "{name:5}  raw n={:3} P={:.2} R={:.2} F1={:.2} | clean n={:3} P={:.2} R={:.2} F1={:.2} | melody n={:3} P={:.2} R={:.2} F1={:.2}",
            notes.len(), before.0, before.1, before.2,
            cleaned.len(), after_clean.0, after_clean.1, after_clean.2,
            tune.len(), after_melody.0, after_melody.1, after_melody.2,
        );
        assert!(
            after_melody.1 >= 0.95,
            "{name}: melody recall {:.2}",
            after_melody.1
        );
        assert!(
            after_melody.2 >= 0.9,
            "{name}: melody F1 {:.2}",
            after_melody.2
        );
        assert!(after_melody.2 > before.2, "{name}: no improvement");
    }
}

#[test]
fn beginner_version_fits_five_finger_c_position() {
    for (name, text) in SETS {
        let a = arrange(&raw(text), BPM, Level::Beginner);
        assert!(!a.is_empty(), "{name}");
        assert!(
            a.iter()
                .all(|n| (60..=67).contains(&n.pitch) && !n.left_hand),
            "{name}"
        );
        assert!(
            a.iter().all(|n| [0, 2, 4, 5, 7].contains(&(n.pitch % 12))),
            "{name}: outside C position"
        );
        assert!(
            a.iter().all(|n| n.beat.fract() == 0.0),
            "{name}: off-beat onset"
        );
        println!(
            "{name:5} beginner: {} notes, first 8 pitches {:?}",
            a.len(),
            a.iter().take(8).map(|n| n.pitch).collect::<Vec<_>>()
        );
    }
}

#[test]
fn intermediate_adds_one_left_hand_root_per_bar() {
    for (name, text) in SETS {
        let a = arrange(&raw(text), BPM, Level::Intermediate);
        let lh: Vec<_> = a.iter().filter(|n| n.left_hand).collect();
        let bars = (a.iter().map(|n| n.beat).fold(0.0, f64::max) / 4.0).floor() as usize + 1;
        assert_eq!(lh.len(), bars, "{name}");
        assert!(
            lh.iter()
                .all(|n| (48..=59).contains(&n.pitch) && n.beat % 4.0 == 0.0),
            "{name}"
        );
        println!(
            "{name:5} intermediate: {} RH, LH roots {:?}",
            a.len() - lh.len(),
            lh.iter().map(|n| n.pitch).collect::<Vec<_>>()
        );
    }
}

#[test]
fn advanced_keeps_bass_in_left_hand_for_the_mix() {
    let a = arrange(&raw(SETS[1].1), BPM, Level::Advanced);
    assert!(a.iter().any(|n| n.left_hand));
    assert!(a.iter().all(|n| n.left_hand == (n.pitch < 60)));
    assert!(a.iter().all(|n| (n.beat * 4.0).fract() == 0.0));
}
