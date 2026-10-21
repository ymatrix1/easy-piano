//! Rule-based accompaniment for generated practice music (docs/specs/practice-mode.md).
//!
//! Each bar of the melody gets one diatonic chord of C major (I, ii, IV, V,
//! vi), chosen by how much of the bar's melody it covers, with a small bias
//! toward I/IV/V and toward keeping the previous chord. The chord is then
//! written as `BASS`, `ACC` and `DRUMS` parts in a pattern set by the style
//! and the meter. The piano part is never doubled: when the left hand is
//! played there is no `ACC`; a sustained strings `PAD` holds the chord
//! instead, with the bass an octave below the left hand. Pure and
//! deterministic.

use crate::notation::{parse_bar, Event};
use crate::pitch::pitch_name;
use crate::song::Song;

/// (pitch classes, preference) for I, ii, IV, V, vi in C major.
const CHORDS: [([u8; 3], f64); 5] = [
    ([0, 4, 7], 0.3),
    ([2, 5, 9], 0.0),
    ([5, 9, 0], 0.2),
    ([7, 11, 2], 0.2),
    ([9, 0, 4], 0.1),
];

/// Meters we have patterns for; other meters get no accompaniment.
#[derive(Clone, Copy, PartialEq)]
enum Meter {
    Four,
    Three,
    Two,
    SixEight,
}

fn meter(time: &str) -> Option<Meter> {
    match time {
        "4/4" => Some(Meter::Four),
        "3/4" => Some(Meter::Three),
        "2/4" => Some(Meter::Two),
        "6/8" => Some(Meter::SixEight),
        _ => None,
    }
}

/// Melody notes of a bar as (pitch class, length as a fraction of a whole, first in bar).
fn melody(bar: &std::collections::BTreeMap<String, String>) -> Vec<(u8, f64, bool)> {
    let mut out = Vec::new();
    for hand in ["RH", "LH"] {
        let Some(text) = bar.get(hand) else { continue };
        let Ok(events) = parse_bar(text) else {
            continue;
        };
        let mut first = true;
        for e in events {
            if let Event::Note { pitches, dur, .. } = e {
                for p in pitches {
                    out.push((p % 12, dur.as_f64(), first));
                }
                first = false;
            } else if matches!(e, Event::Rest { .. }) {
                first = false;
            }
        }
    }
    out
}

/// Index into [CHORDS] that best fits `notes`.
fn pick(notes: &[(u8, f64, bool)], prev: Option<usize>) -> usize {
    let score = |i: usize| {
        let (pcs, bias) = CHORDS[i];
        let fit: f64 = notes
            .iter()
            .map(|&(pc, len, first)| {
                let w = if first { 2.0 * len } else { len };
                if pcs.contains(&pc) {
                    w
                } else {
                    -0.5 * w
                }
            })
            .sum();
        fit + bias + if prev == Some(i) { 0.2 } else { 0.0 }
    };
    (0..CHORDS.len())
        .max_by(|&a, &b| score(a).total_cmp(&score(b)))
        .unwrap_or(0)
}

fn name(midi: u8) -> String {
    pitch_name(midi)
}

/// Chord tones voiced in octave 3 (C3–B3), low to high, as one token head.
fn voicing(pcs: [u8; 3]) -> String {
    let mut m: Vec<u8> = pcs.iter().map(|&pc| 48 + pc).collect();
    m.sort_unstable();
    m.into_iter().map(name).collect()
}

fn bass(pcs: [u8; 3], style: &str, m: Meter) -> String {
    let root = name(36 + pcs[0]);
    let fifth = name(36 + pcs[2]);
    let third = name(36 + pcs[1]);
    match (style, m) {
        ("pop" | "rock" | "game", Meter::Four) => format!("{root}:4 {root}:4 {root}:4 {root}:4"),
        ("jazz", Meter::Four) => format!("{root}:4 {third}:4 {fifth}:4 {third}:4"),
        (_, Meter::Four) => format!("{root}:2 {fifth}:2"),
        (_, Meter::Three) => format!("{root}:2."),
        (_, Meter::Two) => format!("{root}:4 {fifth}:4"),
        (_, Meter::SixEight) => format!("{root}:4. {fifth}:4."),
    }
}

fn acc(pcs: [u8; 3], style: &str, m: Meter) -> String {
    let c = voicing(pcs);
    let mut tones: Vec<u8> = pcs.iter().map(|&pc| 48 + pc).collect();
    tones.sort_unstable();
    let [lo, mid, hi] = [name(tones[0]), name(tones[1]), name(tones[2])];
    match (style, m) {
        ("classical", Meter::Four) => {
            format!("{lo}:8 {hi}:8 {mid}:8 {hi}:8 {lo}:8 {hi}:8 {mid}:8 {hi}:8")
        }
        ("game", Meter::Four) => {
            format!("{lo}:8 {mid}:8 {hi}:8 {mid}:8 {lo}:8 {mid}:8 {hi}:8 {mid}:8")
        }
        ("jazz", Meter::Four) => format!("r:4 {c}:4 r:4 {c}:4"),
        ("pop" | "rock", Meter::Four) => format!("{c}:4 {c}:4 {c}:4 {c}:4"),
        (_, Meter::Four) => format!("{c}:2 {c}:2"),
        (_, Meter::Three) => format!("r:4 {c}:4 {c}:4"),
        (_, Meter::Two) => format!("r:8 {c}:8 r:8 {c}:8"),
        ("classical", Meter::SixEight) => format!("{lo}:8 {mid}:8 {hi}:8 {lo}:8 {mid}:8 {hi}:8"),
        (_, Meter::SixEight) => format!("r:8 {c}:8 {c}:8 r:8 {c}:8 {c}:8"),
    }
}

/// The chord held for the whole bar on strings (left hand played).
fn pad(pcs: [u8; 3], m: Meter) -> String {
    let c = voicing(pcs);
    match m {
        Meter::Four => format!("{c}:1"),
        Meter::Three | Meter::SixEight => format!("{c}:2."),
        Meter::Two => format!("{c}:2"),
    }
}

/// Drum pattern (General MIDI: kick C2, snare D2, closed hat F#2); only the
/// band-like styles get drums.
fn drums(style: &str, m: Meter) -> Option<&'static str> {
    match (style, m) {
        ("pop" | "rock" | "game", Meter::Four) => {
            Some("C2F#2:8 F#2:8 D2F#2:8 F#2:8 C2F#2:8 C2F#2:8 D2F#2:8 F#2:8")
        }
        ("pop" | "rock" | "game", Meter::Three) => Some("C2F#2:4 D2F#2:4 D2F#2:4"),
        ("pop" | "rock" | "game", Meter::Two) => Some("C2F#2:8 F#2:8 D2F#2:8 F#2:8"),
        ("pop" | "rock" | "game", Meter::SixEight) => {
            Some("C2F#2:8 F#2:8 F#2:8 D2F#2:8 F#2:8 F#2:8")
        }
        ("jazz", Meter::Four) => Some("F#2:4 D2F#2:4 F#2:4 D2F#2:4"),
        _ => None,
    }
}

/// `song` with `BASS`, `ACC` and `DRUMS` written into every bar. `style` is a
/// model style token (`pop`, `jazz`, `classical`, …; anything else gets the
/// plain pattern). `played` lists the hands the learner plays (`RH`, `LH`).
/// Bars that already have backing parts are left as they are.
pub fn accompany(song: &Song, style: &str, played: &[&str]) -> Song {
    let mut out = song.clone();
    let Some(m) = meter(&song.time) else {
        return out;
    };
    if song.key != "C" {
        return out; // chords are C major only
    }
    let left = played.contains(&"LH");
    let mut prev = None;
    for bar in &mut out.bars {
        if ["ACC", "BASS", "DRUMS"]
            .iter()
            .any(|k| bar.contains_key(*k))
        {
            continue;
        }
        let i = pick(&melody(bar), prev);
        prev = Some(i);
        let pcs = CHORDS[i].0;
        bar.insert("BASS".into(), bass(pcs, style, m));
        if left {
            bar.insert("PAD".into(), pad(pcs, m));
        } else {
            bar.insert("ACC".into(), acc(pcs, style, m));
        }
        if let Some(d) = drums(style, m) {
            bar.insert("DRUMS".into(), d.into());
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn song(time: &str, bars: &str) -> Song {
        Song::from_json(&format!(
            r#"{{"id":"g","title":"G","composer":"m","arranger":"m","source":"generated",
            "license":"CC0-1.0","composition_license":"CC0-1.0","bpm":90,"time":"{time}","key":"C",
            "generator":{{"method":"melody-model"}},"bars":{bars}}}"#
        ))
        .unwrap()
    }

    #[test]
    fn chords_follow_the_melody() {
        let s = song(
            "4/4",
            r#"[{"RH":"C4:4 E4:4 G4:4 E4:4"},{"RH":"F4:4 A4:4 C5:4 A4:4"},{"RH":"G4:4 B4:4 D5:4 B4:4"}]"#,
        );
        let a = accompany(&s, "folk", &["RH"]);
        assert_eq!(a.bars[0]["BASS"], "C2:2 G2:2");
        assert_eq!(a.bars[1]["BASS"], "F2:2 C2:2");
        assert_eq!(a.bars[2]["BASS"], "G2:2 D2:2");
        assert_eq!(a.bars[0]["ACC"], "C3E3G3:2 C3E3G3:2");
        assert!(!a.bars[0].contains_key("DRUMS"), "folk has no drums");
    }

    #[test]
    fn every_style_and_meter_validates() {
        for (time, bar) in [
            ("4/4", r#"{"RH":"C4:4 D4:4 E4:4 F4:4"}"#),
            ("3/4", r#"{"RH":"C4:2 E4:4"}"#),
            ("2/4", r#"{"RH":"G4:2"}"#),
            ("6/8", r#"{"RH":"C4:4. E4:4."}"#),
        ] {
            for style in [
                "",
                "classical",
                "folk",
                "children",
                "pop",
                "rock",
                "jazz",
                "game",
            ] {
                let a = accompany(&song(time, &format!("[{bar},{bar}]")), style, &["RH"]);
                assert!(
                    a.validate().is_empty(),
                    "{time} {style}: {:?}",
                    a.validate()
                );
                assert!(a
                    .bars
                    .iter()
                    .all(|b| b.contains_key("ACC") && b.contains_key("BASS")));
            }
        }
    }

    #[test]
    fn left_hand_gets_strings_not_piano_and_other_cases_pass_through() {
        let s = song("4/4", r#"[{"RH":"E4:1","LH":"C3:1"}]"#);
        let a = accompany(&s, "pop", &["RH", "LH"]);
        assert!(
            !a.bars[0].contains_key("ACC"),
            "no piano chords over the left hand"
        );
        assert_eq!(a.bars[0]["PAD"], "C3E3G3:1");
        assert!(a.bars[0].contains_key("BASS") && a.bars[0].contains_key("DRUMS"));
        for time in ["3/4", "2/4", "6/8"] {
            let bar = if time == "2/4" {
                r#"{"RH":"E4:2","LH":"C3:2"}"#
            } else {
                r#"{"RH":"E4:2.","LH":"C3:2."}"#
            };
            let b = accompany(&song(time, &format!("[{bar}]")), "folk", &["RH", "LH"]);
            assert!(b.validate().is_empty(), "{time}: {:?}", b.validate());
        }
        let odd = song("5/4", r#"[{"RH":"C4:1 C4:4"}]"#);
        assert_eq!(accompany(&odd, "pop", &["RH"]).bars, odd.bars);
    }
}
