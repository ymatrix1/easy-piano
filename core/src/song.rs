//! Song files (docs/specs/content-format.md): metadata, license, bars per hand.
//! `validate` is what `content lint` runs; `timeline` feeds the session engine.

use crate::notation::{bar_length, parse_bar, Dur, Event};
use serde::Deserialize;
use std::collections::BTreeMap;

#[derive(Debug, Clone, Deserialize)]
pub struct Song {
    pub id: String,
    pub title: String,
    pub composer: String,
    pub arranger: String,
    pub source: String,
    pub source_url: Option<String>,
    pub license: String,
    pub composition_license: String,
    pub bpm: f64,
    pub time: String,
    pub key: String,
    /// One entry per bar: hand ("RH" / "LH") to bar string.
    pub bars: Vec<BTreeMap<String, String>>,
    /// Critical sections as [first_bar, last_bar_exclusive].
    #[serde(default)]
    pub critical: Vec<[usize; 2]>,
    /// How a `source: "generated"` song was made (D17).
    #[serde(default)]
    pub generator: Option<Generator>,
    /// Journey node this song targets, `"course/node"`; lint then runs the rubric.
    #[serde(default)]
    pub spec_node: Option<String>,
}

/// Provenance of a generated song (docs/specs/skill-specs.md).
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Generator {
    /// One of `GENERATOR_METHODS`.
    pub method: String,
    /// Program or skill that produced it, e.g. `compose-song`.
    pub tool: Option<String>,
    /// Model id when an ML model or LLM was used.
    pub model: Option<String>,
    pub seed: Option<u64>,
    /// Song id the variation started from (`pd-variation`).
    pub source_song: Option<String>,
    /// Path or id of the prompt / settings used.
    pub prompt_ref: Option<String>,
}

pub const GENERATOR_METHODS: [&str; 5] = ["rules", "pd-variation", "llm", "magenta", "hand"];

/// Licenses we can redistribute (content-and-licensing rule).
pub const ALLOWED_LICENSES: [&str; 4] = ["CC0-1.0", "CC-BY-4.0", "CC-BY-SA-4.0", "public-domain"];
/// `ACC`, `DRUMS`, `BASS`, `PAD` and `CHOIR` are backing parts: played by the app,
/// never graded.
const HANDS: [&str; 7] = ["RH", "LH", "ACC", "DRUMS", "BASS", "PAD", "CHOIR"];
/// Drum kit pieces a `DRUMS` part may use, as General MIDI percussion numbers:
/// kick 36 (C2), snare 38 (D2), closed hi-hat 42 (F#2), open hi-hat 46 (A#2),
/// crash 49 (C#3).
pub const DRUM_PITCHES: [u8; 5] = [36, 38, 42, 46, 49];

/// Which part of the score a note belongs to.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Part {
    Right,
    Left,
    /// Accompaniment chords on the piano.
    Acc,
    /// Drum kit; pitch is a General MIDI percussion number.
    Drums,
    /// Bass instrument.
    Bass,
    /// Sustained strings pad.
    Pad,
    /// Wordless "ooh" voices.
    Choir,
}

impl Part {
    fn from_key(key: &str) -> Part {
        match key {
            "LH" => Part::Left,
            "ACC" => Part::Acc,
            "DRUMS" => Part::Drums,
            "BASS" => Part::Bass,
            "PAD" => Part::Pad,
            "CHOIR" => Part::Choir,
            _ => Part::Right,
        }
    }

    /// The content key (`RH`, `LH`, `ACC`, `DRUMS`, `BASS`).
    pub fn key(self) -> &'static str {
        match self {
            Part::Right => "RH",
            Part::Left => "LH",
            Part::Acc => "ACC",
            Part::Drums => "DRUMS",
            Part::Bass => "BASS",
            Part::Pad => "PAD",
            Part::Choir => "CHOIR",
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct TimedNote {
    pub pitch: u8,
    pub start_beat: f64,
    pub beats: f64,
    pub left_hand: bool,
    /// Backing part (`ACC`, `DRUMS`, `BASS`, `PAD`, `CHOIR`): played by the app, never a target.
    pub accomp: bool,
    pub part: Part,
    pub finger: Option<u8>,
    pub bar: usize,
}

impl Song {
    pub fn from_json(text: &str) -> Result<Song, String> {
        serde_json::from_str(text).map_err(|e| format!("json: {e}"))
    }

    /// (beats per bar, beat unit), e.g. "3/4" → (3, 4).
    pub fn time_signature(&self) -> Option<(u32, u32)> {
        let (n, d) = self.time.split_once('/')?;
        let (n, d) = (n.trim().parse().ok()?, d.trim().parse().ok()?);
        (n > 0 && d > 0).then_some((n, d))
    }

    /// Every problem a content author must fix. Empty means the song is valid.
    pub fn validate(&self) -> Vec<String> {
        let mut errs = Vec::new();
        for (field, v) in [("id", &self.id), ("title", &self.title), ("composer", &self.composer), ("arranger", &self.arranger), ("source", &self.source)] {
            if v.trim().is_empty() {
                errs.push(format!("`{field}` is empty"));
            }
        }
        if !ALLOWED_LICENSES.contains(&self.license.as_str()) {
            errs.push(format!("license `{}` not in {:?}", self.license, ALLOWED_LICENSES));
        }
        if !ALLOWED_LICENSES.contains(&self.composition_license.as_str()) {
            errs.push(format!("composition_license `{}` not in {:?}", self.composition_license, ALLOWED_LICENSES));
        }
        let generated = self.source == "generated";
        match (&self.generator, generated) {
            (None, true) => errs.push("`generator` required when source is `generated`".into()),
            (Some(_), false) => errs.push("`generator` only allowed when source is `generated`".into()),
            (Some(g), true) => {
                if !GENERATOR_METHODS.contains(&g.method.as_str()) {
                    errs.push(format!("generator.method `{}` not in {:?}", g.method, GENERATOR_METHODS));
                }
                if g.method == "pd-variation" && g.source_song.as_deref().unwrap_or("").is_empty() {
                    errs.push("generator.source_song required for `pd-variation`".into());
                }
            }
            (None, false) => {}
        }
        if generated && self.license != "CC0-1.0" {
            errs.push(format!("generated songs must be CC0-1.0, not `{}`", self.license));
        }
        if let Some(n) = self.spec_node.as_deref().filter(|n| n.split_once('/').is_none_or(|(c, k)| c.is_empty() || k.is_empty())) {
            errs.push(format!("spec_node `{n}` must be `course/node`"));
        }
        if !matches!(self.source.as_str(), "original" | "generated") && self.source_url.as_deref().unwrap_or("").is_empty() {
            errs.push("source_url required unless source is `original` or `generated`".into());
        }
        if !(20.0..=300.0).contains(&self.bpm) {
            errs.push(format!("bpm {} out of 20..300", self.bpm));
        }
        let Some((num, unit)) = self.time_signature() else {
            errs.push(format!("bad time signature `{}`", self.time));
            return errs;
        };
        let bar_len = Dur::new(num, unit);
        if self.bars.is_empty() {
            errs.push("no bars".into());
        }
        for (i, bar) in self.bars.iter().enumerate() {
            for hand in bar.keys().filter(|h| !HANDS.contains(&h.as_str())) {
                errs.push(format!("bar {}: unknown hand `{hand}`", i + 1));
            }
            for (hand, text) in bar {
                match parse_bar(text) {
                    Err(e) => errs.push(format!("bar {} {hand}: {e}", i + 1)),
                    Ok(events) => {
                        let len = bar_length(&events);
                        if len != bar_len {
                            errs.push(format!("bar {} {hand}: length {len}, expected {bar_len} for {}", i + 1, self.time));
                        }
                        for e in &events {
                            if let Event::Note { pitches, .. } = e {
                                if hand == "DRUMS" {
                                    if let Some(p) = pitches.iter().find(|p| !DRUM_PITCHES.contains(*p)) {
                                        errs.push(format!("bar {} DRUMS: pitch {p} is not a drum in {:?}", i + 1, DRUM_PITCHES));
                                    }
                                } else if let Some(p) = pitches.iter().find(|p| !(21..=108).contains(*p)) {
                                    errs.push(format!("bar {} {hand}: pitch {p} outside piano range", i + 1));
                                }
                            }
                        }
                    }
                }
            }
        }
        for [a, b] in &self.critical {
            if a >= b || *b > self.bars.len() {
                errs.push(format!("critical section [{a}, {b}] out of bars 0..{}", self.bars.len()));
            }
        }
        errs
    }

    /// Notes in beats from the start of the song (assumes `validate` passed).
    pub fn timeline(&self) -> Vec<TimedNote> {
        let (num, unit) = self.time_signature().unwrap_or((4, 4));
        let mut out = Vec::new();
        for (i, bar) in self.bars.iter().enumerate() {
            let bar_start = (i as u32 * num) as f64;
            for (hand, text) in bar {
                let part = Part::from_key(hand);
                let mut t = Dur::ZERO;
                for e in parse_bar(text).unwrap_or_default() {
                    if let Event::Note { pitches, dur, fingers, .. } = &e {
                        for (k, &p) in pitches.iter().enumerate() {
                            out.push(TimedNote {
                                pitch: p,
                                start_beat: bar_start + t.beats(unit),
                                beats: dur.beats(unit),
                                left_hand: part == Part::Left,
                                accomp: matches!(part, Part::Acc | Part::Drums | Part::Bass | Part::Pad | Part::Choir),
                                part,
                                finger: fingers.get(k).copied(),
                                bar: i,
                            });
                        }
                    }
                    t = t.add(e.dur());
                }
            }
        }
        out.sort_by(|a, b| a.start_beat.total_cmp(&b.start_beat).then(a.pitch.cmp(&b.pitch)));
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn song(bars: &str, extra: &str) -> String {
        format!(
            r#"{{"id":"t","title":"T","composer":"Trad.","arranger":"Easy Piano contributors",
            "source":"original","source_url":null,"license":"CC-BY-SA-4.0",
            "composition_license":"public-domain","bpm":90,"time":"4/4","key":"C",
            "bars":{bars}{extra}}}"#
        )
    }

    #[test]
    fn valid_song_has_no_errors_and_a_timeline() {
        let s = Song::from_json(&song(r#"[{"RH":"E4:4@3 D4:4@2 C4:2@1","LH":"C3:1@5"}]"#, "")).unwrap();
        assert_eq!(s.validate(), Vec::<String>::new());
        let t = s.timeline();
        assert_eq!(t.len(), 4);
        assert_eq!((t[0].pitch, t[0].start_beat, t[0].beats, t[0].left_hand), (48, 0.0, 4.0, true));
        let c4 = t.iter().find(|n| n.pitch == 60).unwrap();
        assert_eq!((c4.start_beat, c4.beats, c4.finger), (2.0, 2.0, Some(1)));
    }

    #[test]
    fn bar_length_mismatch_is_reported() {
        let s = Song::from_json(&song(r#"[{"RH":"C4:4 D4:4"}]"#, "")).unwrap();
        assert!(s.validate().iter().any(|e| e.contains("length 1/2, expected 1/1")));
    }

    #[test]
    fn license_and_source_rules() {
        let text = song(r#"[{"RH":"C4:1"}]"#, "").replace("CC-BY-SA-4.0", "All rights reserved").replace(r#""source":"original""#, r#""source":"musescore""#);
        let errs = Song::from_json(&text).unwrap().validate();
        assert!(errs.iter().any(|e| e.contains("license `All rights reserved`")));
        assert!(errs.iter().any(|e| e.contains("source_url required")));
    }

    #[test]
    fn generated_songs_need_provenance_and_cc0() {
        let base = song(r#"[{"RH":"C4:1"}]"#, "").replace(r#""source":"original""#, r#""source":"generated""#);
        let errs = Song::from_json(&base).unwrap().validate();
        assert!(errs.iter().any(|e| e.contains("`generator` required")), "{errs:?}");
        assert!(errs.iter().any(|e| e.contains("must be CC0-1.0")), "{errs:?}");
        let ok = base.replace("CC-BY-SA-4.0", "CC0-1.0");
        let ok = ok.replace(r#""bars""#, r#""generator":{"method":"llm","tool":"compose-song","model":"m","seed":7},"spec_node":"essentials-1/eighths","bars""#);
        assert_eq!(Song::from_json(&ok).unwrap().validate(), Vec::<String>::new());
        let bad = ok.replace(r#""method":"llm""#, r#""method":"pd-variation""#).replace("essentials-1/eighths", "eighths");
        let errs = Song::from_json(&bad).unwrap().validate();
        assert!(errs.iter().any(|e| e.contains("source_song required")), "{errs:?}");
        assert!(errs.iter().any(|e| e.contains("must be `course/node`")), "{errs:?}");
        let stray = song(r#"[{"RH":"C4:1"}]"#, r#","generator":{"method":"hand"}"#);
        assert!(Song::from_json(&stray).unwrap().validate().iter().any(|e| e.contains("only allowed")));
    }

    #[test]
    fn drums_and_bass_are_backing_parts() {
        let s = Song::from_json(&song(r#"[{"RH":"C4:1","DRUMS":"C2F#2:4 D2F#2:4 C2F#2:4 D2F#2:4","BASS":"C2:2 G1:2"}]"#, "")).unwrap();
        assert_eq!(s.validate(), Vec::<String>::new());
        let t = s.timeline();
        assert!(t.iter().filter(|n| n.part == Part::Drums).all(|n| n.accomp && DRUM_PITCHES.contains(&n.pitch)));
        assert_eq!(t.iter().filter(|n| n.part == Part::Drums).count(), 8);
        let bass: Vec<u8> = t.iter().filter(|n| n.part == Part::Bass).map(|n| n.pitch).collect();
        assert_eq!(bass, vec![36, 31]);
        assert!(t.iter().any(|n| n.part == Part::Right && !n.accomp));
    }

    #[test]
    fn pad_is_a_backing_part() {
        let s = Song::from_json(&song(r#"[{"RH":"C4:1","PAD":"C3E3G3:1","CHOIR":"G4:2 E4:2"}]"#, "")).unwrap();
        assert_eq!(s.validate(), Vec::<String>::new());
        let pad: Vec<TimedNote> = s.timeline().into_iter().filter(|n| n.part == Part::Pad).collect();
        assert_eq!(pad.len(), 3);
        assert!(pad.iter().all(|n| n.accomp && n.beats == 4.0));
        let choir: Vec<u8> = s.timeline().into_iter().filter(|n| n.part == Part::Choir && n.accomp).map(|n| n.pitch).collect();
        assert_eq!(choir, vec![67, 64]);
    }

    #[test]
    fn drums_reject_unknown_kit_pieces() {
        let s = Song::from_json(&song(r#"[{"RH":"C4:1","DRUMS":"C4:1"}]"#, "")).unwrap();
        assert!(s.validate().iter().any(|e| e.contains("DRUMS: pitch 60 is not a drum")));
    }

    #[test]
    fn three_four_time_counts_three_beats() {
        let s = Song::from_json(&song(r#"[{"RH":"C4:2."}, {"RH":"D4:2 E4:4"}]"#, "").replace("4/4", "3/4")).unwrap();
        assert!(s.validate().is_empty());
        assert_eq!(s.timeline()[1].start_beat, 3.0);
    }
}
