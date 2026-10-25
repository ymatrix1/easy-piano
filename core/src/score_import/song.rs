//! Converts an [`ImportedScore`] into a content song (docs/specs/content-format.md),
//! so an imported score plays through the same session code as bundled songs.
//!
//! Layout: notes of one hand that start and end together form one chord. Chords of
//! one hand are split into at most two voices (`RH` / `RH2`, `LH` / `LH2`); a bar
//! with no notes in a voice is filled with rests. Notes that cross a bar line are
//! split with `{tie}`. Limits are recorded in docs/specs/score-import-and-page-view.md
//! section 5.2.

use super::{Hand, ImportedNote, ImportedScore};
use crate::pitch::pitch_name;
use serde_json::json;
use std::collections::BTreeMap;

/// Ticks per quarter note. 120 is divisible by 2, 3, 4, 5, 6, 8, 10, 12, 15, 16, ...
/// so triplets and quintuplets stay exact.
const TICKS_PER_BEAT: f64 = 120.0;
/// Ticks in a whole note (4 quarter notes).
const WHOLE: u32 = 480;

/// Parses `data` with the parser for `file_name` and returns the content song as JSON.
pub fn import_song_json(file_name: &str, data: &[u8]) -> Result<String, String> {
    let score = super::import(file_name, data)?;
    score_to_song_json(&score, &song_id(file_name), file_name)
}

/// Builds the content song JSON for a parsed score. `id` must be a valid song id.
pub fn score_to_song_json(
    score: &ImportedScore,
    id: &str,
    file_name: &str,
) -> Result<String, String> {
    let first = score.measures.first().ok_or("score has no measures")?;
    if score.measures.iter().any(|m| m.time != first.time) {
        return Err("meter changes inside the piece are not supported".into());
    }
    let (num, unit) = first.time;
    let key = key_name(first.key_fifths)?;
    // Content bpm counts the time signature's beat unit (content-format.md).
    let bpm = (score.tempo_bpm.unwrap_or(120.0) * unit as f64 / 4.0).clamp(20.0, 300.0);
    let bounds: Vec<(u32, u32)> = score
        .measures
        .iter()
        .map(|m| (ticks(m.start), ticks(m.start + m.beats)))
        .collect();

    let mut bars = vec![BTreeMap::<String, String>::new(); bounds.len()];
    for (hand, prefix) in [(Hand::Right, "RH"), (Hand::Left, "LH")] {
        let groups = groups_of(score.notes.iter().filter(|n| n.hand == hand));
        let mut voices = layer(groups)?;
        if voices.is_empty() {
            voices.push(Vec::new());
        }
        for (bar, &(bs, be)) in bars.iter_mut().zip(&bounds) {
            for (v, voice) in voices.iter().enumerate() {
                let (text, used) = bar_text(voice, bs, be);
                if v == 0 || used {
                    let key = if v == 0 {
                        prefix.to_string()
                    } else {
                        format!("{prefix}2")
                    };
                    bar.insert(key, text);
                }
            }
        }
    }

    let title = if score.title.trim().is_empty() {
        match file_stem(file_name) {
            stem if stem.is_empty() => "Untitled".to_string(),
            stem => stem,
        }
    } else {
        score.title.clone()
    };
    let composer = if score.composer.trim().is_empty() {
        "Unknown".to_string()
    } else {
        score.composer.clone()
    };
    // Imported files carry no license information; the app does not check it.
    // The content lint would reject these values (see specs section 5.5).
    let song = json!({
        "id": id,
        "title": title,
        "composer": composer,
        "arranger": "Imported",
        "source": "custom",
        "source_url": null,
        "license": "user-provided",
        "composition_license": "user-provided",
        "bpm": bpm,
        "time": format!("{num}/{unit}"),
        "key": key,
        "bars": bars,
        "critical": [],
    });
    serde_json::to_string(&song).map_err(|e| format!("json: {e}"))
}

/// Song id for an imported file: `custom-` plus the file stem as a slug.
pub fn song_id(file_name: &str) -> String {
    let mut slug = String::new();
    for c in file_stem(file_name).chars() {
        if c.is_ascii_alphanumeric() {
            slug.push(c.to_ascii_lowercase());
        } else if !slug.ends_with('-') {
            slug.push('-');
        }
    }
    let slug = slug.trim_matches('-');
    if slug.is_empty() {
        "custom-score".to_string()
    } else {
        format!("custom-{slug}")
    }
}

fn file_stem(file_name: &str) -> String {
    let name = file_name.rsplit(['/', '\\']).next().unwrap_or(file_name);
    match name.rsplit_once('.') {
        Some((stem, _)) => stem.to_string(),
        _ => name.to_string(),
    }
}

fn ticks(beats: f64) -> u32 {
    (beats * TICKS_PER_BEAT).round().max(0.0) as u32
}

/// Major key name for a number of sharps (positive) or flats (negative).
fn key_name(fifths: i8) -> Result<String, String> {
    const KEYS: [&str; 15] = [
        "Cb", "Gb", "Db", "Ab", "Eb", "Bb", "F", "C", "G", "D", "A", "E", "B", "F#", "C#",
    ];
    if !(-7..=7).contains(&fifths) {
        return Err(format!("key signature {fifths} out of range"));
    }
    Ok(KEYS[(fifths + 7) as usize].to_string())
}

/// Notes of one hand that start and end together, as one sounding chord.
#[derive(Debug, Clone, PartialEq, Eq)]
struct Group {
    start: u32,
    end: u32,
    pitches: Vec<u8>,
}

fn groups_of<'a>(notes: impl Iterator<Item = &'a ImportedNote>) -> Vec<Group> {
    let mut map: BTreeMap<(u32, u32), Vec<u8>> = BTreeMap::new();
    for n in notes {
        let (start, end) = (ticks(n.start), ticks(n.start + n.beats));
        if end <= start {
            continue;
        }
        map.entry((start, end)).or_default().push(n.midi);
    }
    // BTreeMap order is (start, end); the start order is what layering needs.
    map.into_iter()
        .map(|((start, end), mut pitches)| {
            pitches.sort_unstable();
            pitches.dedup();
            Group {
                start,
                end,
                pitches,
            }
        })
        .collect()
}

/// Splits groups (sorted by start) into voices: a group goes to the first voice that
/// is free at its start. Two voices at most.
fn layer(groups: Vec<Group>) -> Result<Vec<Vec<Group>>, String> {
    let mut voices: Vec<Vec<Group>> = Vec::new();
    for g in groups {
        let free = voices
            .iter()
            .position(|v| v.last().is_none_or(|last| last.end <= g.start));
        match free {
            Some(i) => voices[i].push(g),
            None if voices.len() < 2 => voices.push(vec![g]),
            None => {
                return Err(format!(
                    "more than two voices in one hand at beat {:.2}",
                    g.start as f64 / TICKS_PER_BEAT
                ))
            }
        }
    }
    Ok(voices)
}

/// Text of one voice in the bar `[bs, be)` and whether it holds any note there.
fn bar_text(voice: &[Group], bs: u32, be: u32) -> (String, bool) {
    let mut parts = Vec::new();
    let mut at = bs;
    let mut used = false;
    for g in voice {
        if g.end <= bs || g.start >= be {
            continue;
        }
        let (s, e) = (g.start.max(bs), g.end.min(be));
        if s > at {
            parts.push(format!("r:{}", dur(s - at)));
        }
        let names: String = g.pitches.iter().map(|&p| pitch_name(p)).collect();
        let mut token = format!("{names}:{}", dur(e - s));
        if g.end > be {
            token.push_str(" {tie}");
        }
        parts.push(token);
        at = e;
        used = true;
    }
    if at < be {
        parts.push(format!("r:{}", dur(be - at)));
    }
    (parts.join(" "), used)
}

/// Duration text for a length in ticks: a denominator (`4`), a dotted one (`2.`), or
/// an explicit fraction of a whole note (`5/24`).
fn dur(ticks: u32) -> String {
    let g = gcd(ticks, WHOLE);
    let (n, d) = (ticks / g, WHOLE / g);
    if n == 1 && d.is_power_of_two() && d <= 64 {
        return d.to_string();
    }
    if n == 3 && d % 2 == 0 && (d / 2).is_power_of_two() && d / 2 <= 64 {
        return format!("{}.", d / 2);
    }
    format!("{n}/{d}")
}

fn gcd(a: u32, b: u32) -> u32 {
    if b == 0 {
        a
    } else {
        gcd(b, a % b)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::score_import::{Clef, ImportedMeasure};
    use crate::song::Song;

    fn measure(number: u32, start: f64, time: (u32, u32), key_fifths: i8) -> ImportedMeasure {
        ImportedMeasure {
            number,
            start,
            beats: time.0 as f64 * 4.0 / time.1 as f64,
            time,
            key_fifths,
        }
    }

    fn note(midi: u8, start: f64, beats: f64, hand: Hand) -> ImportedNote {
        ImportedNote {
            midi,
            start,
            beats,
            hand,
            articulations: Vec::new(),
        }
    }

    fn score(measures: Vec<ImportedMeasure>, notes: Vec<ImportedNote>) -> ImportedScore {
        ImportedScore {
            title: "Test Tune".into(),
            composer: "Anon.".into(),
            tempo_bpm: Some(90.0),
            right_clef: Clef::Treble,
            left_clef: Clef::Bass,
            measures,
            notes,
            expression: Vec::new(),
        }
    }

    /// Parses the JSON and returns the song. Only license and source checks may fail:
    /// imported files have no content license (see the module docs).
    fn song_of(json: &str) -> Song {
        let song = Song::from_json(json).expect("valid song json");
        let errs: Vec<String> = song
            .validate()
            .into_iter()
            .filter(|e| !e.contains("license") && !e.contains("source"))
            .collect();
        assert!(errs.is_empty(), "lint errors: {errs:?}");
        song
    }

    fn bars_of(json: &str) -> Vec<BTreeMap<String, String>> {
        let v: serde_json::Value = serde_json::from_str(json).unwrap();
        serde_json::from_value(v["bars"].clone()).unwrap()
    }

    #[test]
    fn quarter_notes_become_one_token_each() {
        let s = score(
            vec![measure(1, 0.0, (4, 4), 0)],
            vec![
                note(60, 0.0, 1.0, Hand::Right),
                note(62, 1.0, 1.0, Hand::Right),
                note(64, 2.0, 1.0, Hand::Right),
                note(65, 3.0, 1.0, Hand::Right),
                note(48, 0.0, 4.0, Hand::Left),
            ],
        );
        let json = score_to_song_json(&s, "custom-test", "test.xml").unwrap();
        let bars = bars_of(&json);
        assert_eq!(bars[0]["RH"], "C4:4 D4:4 E4:4 F4:4");
        assert_eq!(bars[0]["LH"], "C3:1");
        assert!(!bars[0].contains_key("RH2"));
        let song = song_of(&json);
        assert_eq!(song.time, "4/4");
        assert_eq!(song.key, "C");
        assert_eq!(song.bpm, 90.0);
        assert_eq!(song.source, "custom");
    }

    #[test]
    fn chord_and_rest_in_one_bar() {
        let s = score(
            vec![measure(1, 0.0, (4, 4), 0)],
            vec![
                note(60, 0.0, 2.0, Hand::Right),
                note(64, 0.0, 2.0, Hand::Right),
                note(67, 0.0, 2.0, Hand::Right),
            ],
        );
        let json = score_to_song_json(&s, "custom-test", "test.xml").unwrap();
        assert_eq!(bars_of(&json)[0]["RH"], "C4E4G4:2 r:2");
    }

    #[test]
    fn dotted_and_triplet_durations() {
        assert_eq!(dur(ticks(1.5)), "4.");
        assert_eq!(dur(ticks(0.5)), "8");
        assert_eq!(dur(ticks(1.0 / 3.0)), "1/12");
        assert_eq!(dur(ticks(0.25)), "16");
        assert_eq!(dur(ticks(1.25)), "5/16");
    }

    #[test]
    fn note_crossing_bar_line_is_split_with_tie() {
        let s = score(
            vec![measure(1, 0.0, (4, 4), 0), measure(2, 4.0, (4, 4), 0)],
            vec![note(60, 3.0, 2.0, Hand::Right)],
        );
        let json = score_to_song_json(&s, "custom-test", "test.xml").unwrap();
        let bars = bars_of(&json);
        assert_eq!(bars[0]["RH"], "r:2. C4:4 {tie}");
        assert_eq!(bars[1]["RH"], "C4:4 r:2.");
        song_of(&json);
    }

    #[test]
    fn second_voice_gets_rh2_with_rests() {
        // Half-note chord in voice 1; a quarter-note line inside it in voice 2.
        let s = score(
            vec![measure(1, 0.0, (4, 4), 0)],
            vec![
                note(48, 0.0, 2.0, Hand::Left),
                note(52, 0.0, 2.0, Hand::Left),
                note(55, 2.0, 1.0, Hand::Left),
                note(43, 0.0, 1.0, Hand::Left),
                note(41, 1.0, 1.0, Hand::Left),
                note(60, 0.0, 4.0, Hand::Right),
            ],
        );
        let json = score_to_song_json(&s, "custom-test", "test.xml").unwrap();
        let bars = bars_of(&json);
        assert_eq!(bars[0]["LH"], "G2:4 F2:4 G3:4 r:4");
        assert_eq!(bars[0]["LH2"], "C3E3:2 r:2");
        song_of(&json);
    }

    #[test]
    fn three_simultaneous_voices_are_rejected() {
        let s = score(
            vec![measure(1, 0.0, (4, 4), 0)],
            vec![
                note(60, 0.0, 4.0, Hand::Right),
                note(64, 0.0, 2.0, Hand::Right),
                note(67, 0.5, 1.0, Hand::Right),
            ],
        );
        let err = score_to_song_json(&s, "custom-test", "test.xml").unwrap_err();
        assert!(err.contains("more than two voices"), "{err}");
    }

    #[test]
    fn mid_piece_meter_change_is_rejected() {
        let s = score(
            vec![measure(1, 0.0, (4, 4), 0), measure(2, 4.0, (3, 4), 0)],
            vec![note(60, 0.0, 1.0, Hand::Right)],
        );
        let err = score_to_song_json(&s, "custom-test", "test.xml").unwrap_err();
        assert!(err.contains("meter changes"), "{err}");
    }

    #[test]
    fn key_signature_and_compound_meter() {
        let s = score(
            vec![measure(1, 0.0, (6, 8), 2)],
            vec![note(62, 0.0, 1.5, Hand::Right)],
        );
        let json = score_to_song_json(&s, "custom-test", "test.xml").unwrap();
        let song = song_of(&json);
        assert_eq!(song.key, "D");
        assert_eq!(song.time, "6/8");
        assert_eq!(song.bpm, 180.0); // 90 quarters = 180 eighths
        assert_eq!(bars_of(&json)[0]["RH"], "D4:4. r:4.");
        assert_eq!(key_name(-7).unwrap(), "Cb");
        assert!(key_name(8).is_err());
    }

    #[test]
    fn song_id_is_a_slug() {
        assert_eq!(song_id("Für Elise (v2).mid"), "custom-f-r-elise-v2");
        assert_eq!(song_id("/tmp/My Tune.ly"), "custom-my-tune");
        assert_eq!(song_id(".mid"), "custom-score");
    }

    #[test]
    fn import_song_json_reads_abc() {
        let abc = "X:1\nT:Scale\nM:4/4\nL:1/4\nK:C\nCDEF|\n";
        let json = import_song_json("scale.abc", abc.as_bytes()).unwrap();
        let bars = bars_of(&json);
        assert_eq!(bars[0]["RH"], "C4:4 D4:4 E4:4 F4:4");
        assert_eq!(song_of(&json).id, "custom-scale");
    }
}
