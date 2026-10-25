//! Song files (docs/specs/content-format.md): metadata, license, bars per hand.
//! `validate` is what `content lint` runs; `timeline` feeds the session engine.

use crate::dynamics::{Mark, TimedMark};
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
    /// Optional changes effective at the start of a one-based bar.
    #[serde(default)]
    pub changes: Vec<SignatureChange>,
    /// One entry per bar: hand ("RH" / "LH" / "RH2" / "LH2") to bar string.
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
    /// Regions where the composition is still protected (D33): the app must not
    /// offer the song there before `until`.
    #[serde(default)]
    pub restricted_in: Vec<Restriction>,
}

/// Key and/or meter change at the start of a bar.
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SignatureChange {
    pub bar: usize,
    #[serde(default)]
    pub key: Option<String>,
    #[serde(default)]
    pub time: Option<String>,
}

/// A region where a song may not be offered yet.
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Restriction {
    /// ISO 3166-1 alpha-2 code, e.g. `US`.
    pub region: String,
    /// First day the song may be offered there, `YYYY-MM-DD`.
    pub until: String,
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

pub const GENERATOR_METHODS: [&str; 6] = [
    "rules",
    "pd-variation",
    "llm",
    "magenta",
    "hand",
    "melody-model",
];

/// Licenses we can redistribute (content-and-licensing rule).
pub const ALLOWED_LICENSES: [&str; 4] = ["CC0-1.0", "CC-BY-4.0", "CC-BY-SA-4.0", "public-domain"];
/// `RH2` and `LH2` are second voices for the hands.
/// `ACC`, `DRUMS`, `BASS`, `PAD` and `CHOIR` are backing parts: played by the app,
/// never graded.
const HANDS: [&str; 9] = [
    "RH", "LH", "RH2", "LH2", "ACC", "DRUMS", "BASS", "PAD", "CHOIR",
];
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
            "LH" | "LH2" => Part::Left,
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
    pub voice: u8,
    /// Tied into the next note of the same pitch.
    pub tie: bool,
}

#[derive(Debug, Default, Clone)]
struct BarStructure {
    repeat_start: bool,
    repeat_end: bool,
    volta_start: Option<u8>,
    volta_end: bool,
    navigation: Vec<String>,
}

#[derive(Debug)]
struct PlayedBar {
    source: usize,
    start_beat: f64,
}

#[derive(Debug)]
struct VoltaSpan {
    start: usize,
    end: usize,
    number: u8,
}

impl Song {
    pub fn from_json(text: &str) -> Result<Song, String> {
        serde_json::from_str(text).map_err(|e| format!("json: {e}"))
    }

    /// (beats per bar, beat unit), e.g. "3/4" → (3, 4).
    pub fn time_signature(&self) -> Option<(u32, u32)> {
        parse_time_signature(&self.time)
    }

    /// Effective key and time signature at a zero-based source bar.
    pub fn signature_at_bar(&self, bar: usize) -> (String, (u32, u32)) {
        let mut key = self.key.clone();
        let mut time = self.time_signature().unwrap_or((4, 4));
        for change in &self.changes {
            if change.bar > bar + 1 {
                break;
            }
            if let Some(next_key) = &change.key {
                key = next_key.clone();
            }
            if let Some(next_time) = change.time.as_deref().and_then(parse_time_signature) {
                time = next_time;
            }
        }
        (key, time)
    }

    fn source_bar_starts(&self) -> Vec<f64> {
        let mut starts = Vec::with_capacity(self.bars.len());
        let mut beat = 0.0;
        let base_unit = self.time_signature().unwrap_or((4, 4)).1;
        for i in 0..self.bars.len() {
            starts.push(beat);
            let (_, (num, den)) = self.signature_at_bar(i);
            beat += num as f64 * base_unit as f64 / den as f64;
        }
        starts
    }

    pub fn source_bar_beat(&self, bar: usize) -> f64 {
        self.source_bar_starts().get(bar).copied().unwrap_or(0.0)
    }

    pub fn measure_starts(&self) -> Vec<f64> {
        let mut starts: Vec<f64> = self
            .played_bars()
            .into_iter()
            .map(|bar| bar.start_beat)
            .collect();
        starts.push(self.total_beats());
        starts
    }

    pub fn played_signature_changes(&self) -> Vec<(f64, String, u32, u32)> {
        let mut changes = Vec::new();
        let mut previous: Option<(String, (u32, u32))> = None;
        for bar in self.played_bars() {
            let signature = self.signature_at_bar(bar.source);
            if previous.as_ref().is_some_and(|old| old != &signature) {
                changes.push((
                    bar.start_beat,
                    signature.0.clone(),
                    signature.1 .0,
                    signature.1 .1,
                ));
            }
            previous = Some(signature);
        }
        changes
    }

    /// Every problem a content author must fix. Empty means the song is valid.
    pub fn validate(&self) -> Vec<String> {
        let mut errs = Vec::new();
        for (field, v) in [
            ("id", &self.id),
            ("title", &self.title),
            ("composer", &self.composer),
            ("arranger", &self.arranger),
            ("source", &self.source),
        ] {
            if v.trim().is_empty() {
                errs.push(format!("`{field}` is empty"));
            }
        }
        if !ALLOWED_LICENSES.contains(&self.license.as_str()) {
            errs.push(format!(
                "license `{}` not in {:?}",
                self.license, ALLOWED_LICENSES
            ));
        }
        if !ALLOWED_LICENSES.contains(&self.composition_license.as_str()) {
            errs.push(format!(
                "composition_license `{}` not in {:?}",
                self.composition_license, ALLOWED_LICENSES
            ));
        }
        let generated = self.source == "generated";
        match (&self.generator, generated) {
            (None, true) => errs.push("`generator` required when source is `generated`".into()),
            (Some(_), false) => {
                errs.push("`generator` only allowed when source is `generated`".into())
            }
            (Some(g), true) => {
                if !GENERATOR_METHODS.contains(&g.method.as_str()) {
                    errs.push(format!(
                        "generator.method `{}` not in {:?}",
                        g.method, GENERATOR_METHODS
                    ));
                }
                if g.method == "pd-variation" && g.source_song.as_deref().unwrap_or("").is_empty() {
                    errs.push("generator.source_song required for `pd-variation`".into());
                }
            }
            (None, false) => {}
        }
        if generated && self.license != "CC0-1.0" {
            errs.push(format!(
                "generated songs must be CC0-1.0, not `{}`",
                self.license
            ));
        }
        if let Some(n) = self.spec_node.as_deref().filter(|n| {
            n.split_once('/')
                .is_none_or(|(c, k)| c.is_empty() || k.is_empty())
        }) {
            errs.push(format!("spec_node `{n}` must be `course/node`"));
        }
        for r in &self.restricted_in {
            if r.region.len() != 2 || !r.region.bytes().all(|b| b.is_ascii_uppercase()) {
                errs.push(format!(
                    "restricted_in region `{}` must be an ISO 3166-1 alpha-2 code",
                    r.region
                ));
            }
            if !is_iso_date(&r.until) {
                errs.push(format!(
                    "restricted_in until `{}` must be YYYY-MM-DD",
                    r.until
                ));
            }
        }
        if !matches!(self.source.as_str(), "original" | "generated")
            && self.source_url.as_deref().unwrap_or("").is_empty()
        {
            errs.push("source_url required unless source is `original` or `generated`".into());
        }
        if !(20.0..=300.0).contains(&self.bpm) {
            errs.push(format!("bpm {} out of 20..300", self.bpm));
        }
        let Some((_num, unit)) = self.time_signature() else {
            errs.push(format!("bad time signature `{}`", self.time));
            return errs;
        };
        let mut changes_seen = std::collections::BTreeSet::new();
        let mut previous_change_bar = 1;
        for change in &self.changes {
            if change.bar < 2 || change.bar > self.bars.len() {
                errs.push(format!(
                    "signature change bar {} must be within 2..{}",
                    change.bar,
                    self.bars.len()
                ));
            }
            if !changes_seen.insert(change.bar) {
                errs.push(format!("multiple signature changes at bar {}", change.bar));
            }
            if change.bar < previous_change_bar {
                errs.push("signature changes must be ordered by bar".into());
            }
            previous_change_bar = change.bar;
            if change.key.as_deref().is_some_and(|k| !valid_key(k)) {
                errs.push(format!(
                    "signature change at bar {} has invalid key",
                    change.bar
                ));
            }
            if let Some(t) = &change.time {
                if parse_time_signature(t).is_none() {
                    errs.push(format!(
                        "signature change at bar {} has invalid time `{t}`",
                        change.bar
                    ));
                }
            }
            if change.key.is_none() && change.time.is_none() {
                errs.push(format!(
                    "signature change at bar {} must set key or time",
                    change.bar
                ));
            }
        }
        if self.bars.is_empty() {
            errs.push("no bars".into());
        }
        for (i, bar) in self.bars.iter().enumerate() {
            let (_, (bar_num, bar_unit)) = self.signature_at_bar(i);
            let bar_len = Dur::new(bar_num, bar_unit);
            for hand in bar.keys().filter(|h| !HANDS.contains(&h.as_str())) {
                errs.push(format!("bar {}: unknown hand `{hand}`", i + 1));
            }
            if bar.contains_key("RH2") && !bar.contains_key("RH") {
                errs.push(format!("bar {}: RH2 without RH", i + 1));
            }
            if bar.contains_key("LH2") && !bar.contains_key("LH") {
                errs.push(format!("bar {}: LH2 without LH", i + 1));
            }
            for (hand, text) in bar {
                match parse_bar(text) {
                    Err(e) => errs.push(format!("bar {} {hand}: {e}", i + 1)),
                    Ok(events) => {
                        let len = bar_length(&events);
                        for (event_index, e) in events.iter().enumerate() {
                            if let Event::Directive { name, arg } = e {
                                if let Err(msg) = Mark::from_directive(name, arg.as_deref()) {
                                    errs.push(format!("bar {} {hand}: {msg}", i + 1));
                                }
                                let pos = events[..event_index]
                                    .iter()
                                    .fold(Dur::ZERO, |sum, before| sum.add(before.dur()));
                                let at_start = pos == Dur::ZERO;
                                let at_end = pos == len;
                                match name.as_str() {
                                    "repeat_start" | "volta" | "volta_end" if !at_start => {
                                        errs.push(format!(
                                            "bar {} {hand}: `{{{name}}}` must be at a bar line",
                                            i + 1
                                        ));
                                    }
                                    "repeat_end" if !at_end => {
                                        errs.push(format!("bar {} {hand}: `{{repeat_end}}` must follow the last note", i + 1));
                                    }
                                    "repeat_start" | "repeat_end" | "volta_end" | "segno"
                                    | "coda" | "dc_al_fine" | "dc_al_coda" | "ds_al_fine"
                                    | "ds_al_coda" | "fine" | "to_coda"
                                        if arg.is_some() =>
                                    {
                                        errs.push(format!(
                                            "bar {} {hand}: `{{{name}}}` takes no argument",
                                            i + 1
                                        ));
                                    }
                                    "volta"
                                        if arg
                                            .as_deref()
                                            .and_then(parse_volta_number)
                                            .is_none() =>
                                    {
                                        errs.push(format!(
                                            "bar {} {hand}: `{{volta}}` must be `[1]` or `[2]`",
                                            i + 1
                                        ));
                                    }
                                    "tie" => {
                                        if arg.is_some() {
                                            errs.push(format!(
                                                "bar {} {hand}: `{{tie}}` takes no argument",
                                                i + 1
                                            ));
                                        }
                                        let previous =
                                            event_index.checked_sub(1).and_then(|p| events.get(p));
                                        let previous_pitches = match previous {
                                            Some(Event::Note { pitches, .. }) => {
                                                Some(pitches.clone())
                                            }
                                            _ => None,
                                        };
                                        let following = events[event_index + 1..]
                                            .iter()
                                            .find(|next| !matches!(next, Event::Directive { .. }));
                                        let next_pitches = match following {
                                            Some(Event::Note { pitches, .. }) => {
                                                Some(pitches.clone())
                                            }
                                            Some(_) => None,
                                            None if pos == len => self
                                                .bars
                                                .get(i + 1)
                                                .and_then(|next_bar| next_bar.get(hand))
                                                .and_then(|next_text| parse_bar(next_text).ok())
                                                .and_then(|next_events| {
                                                    next_events.into_iter().find(|next| {
                                                        !matches!(next, Event::Directive { .. })
                                                    })
                                                })
                                                .and_then(|next| match next {
                                                    Event::Note { pitches, .. } => Some(pitches),
                                                    _ => None,
                                                }),
                                            None => None,
                                        };
                                        if previous_pitches.is_none()
                                            || next_pitches.is_none()
                                            || previous_pitches != next_pitches
                                        {
                                            errs.push(format!(
                                                "bar {} {hand}: `{{tie}}` must connect equal pitches in consecutive notes",
                                                i + 1
                                            ));
                                        }
                                    }
                                    _ => {}
                                }
                            }
                        }
                        if len != bar_len {
                            errs.push(format!(
                                "bar {} {hand}: length {len}, expected {bar_len} for {}",
                                i + 1,
                                self.time
                            ));
                        }
                        for e in &events {
                            if let Event::Note { pitches, .. } = e {
                                if hand == "DRUMS" {
                                    if let Some(p) =
                                        pitches.iter().find(|p| !DRUM_PITCHES.contains(*p))
                                    {
                                        errs.push(format!(
                                            "bar {} DRUMS: pitch {p} is not a drum in {:?}",
                                            i + 1,
                                            DRUM_PITCHES
                                        ));
                                    }
                                } else if let Some(p) =
                                    pitches.iter().find(|p| !(21..=108).contains(*p))
                                {
                                    errs.push(format!(
                                        "bar {} {hand}: pitch {p} outside piano range",
                                        i + 1
                                    ));
                                }
                            }
                        }
                    }
                }
            }
        }
        for (v1_key, v2_key) in [("RH", "RH2"), ("LH", "LH2")] {
            let mut v1_notes = Vec::new();
            let mut v2_notes = Vec::new();
            let bar_starts = self.source_bar_starts();
            for (i, bar) in self.bars.iter().enumerate() {
                let bar_start = bar_starts[i];
                if let Some(text) = bar.get(v1_key) {
                    if let Ok(events) = parse_bar(text) {
                        let mut t = Dur::ZERO;
                        for e in &events {
                            if let Event::Note { pitches, dur, .. } = e {
                                for &p in pitches {
                                    v1_notes.push((
                                        p,
                                        bar_start + t.beats(unit),
                                        dur.beats(unit),
                                        i,
                                    ));
                                }
                            }
                            t = t.add(e.dur());
                        }
                    }
                }
                if let Some(text) = bar.get(v2_key) {
                    if let Ok(events) = parse_bar(text) {
                        let mut t = Dur::ZERO;
                        for e in &events {
                            if let Event::Note { pitches, dur, .. } = e {
                                for &p in pitches {
                                    v2_notes.push((
                                        p,
                                        bar_start + t.beats(unit),
                                        dur.beats(unit),
                                        i,
                                    ));
                                }
                            }
                            t = t.add(e.dur());
                        }
                    }
                }
            }
            for &(p1, s1, d1, b1) in &v1_notes {
                for &(p2, s2, d2, b2) in &v2_notes {
                    if p1 == p2 && (s1 - s2).abs() > 1e-6 {
                        let e1 = s1 + d1;
                        let e2 = s2 + d2;
                        if (s1 < s2 && s2 < e1 - 1e-6) || (s2 < s1 && s1 < e2 - 1e-6) {
                            let bar_num = b1.max(b2) + 1;
                            errs.push(format!(
                                "bar {bar_num}: pitch {p1} overlaps between voice 1 and voice 2"
                            ));
                        }
                    }
                }
            }
        }
        let structure = self.bar_structure();
        let mut repeat_open = false;
        for (i, marks) in structure.iter().enumerate() {
            if marks.repeat_start {
                if repeat_open {
                    errs.push(format!("bar {}: nested repeats are not supported", i + 1));
                } else {
                    repeat_open = true;
                }
            }
            if marks.repeat_end && repeat_open {
                repeat_open = false;
            }
            if marks.volta_start.is_some() && !structure[..=i].iter().any(|m| m.repeat_end) {
                errs.push(format!("bar {}: volta is not attached to a repeat", i + 1));
            }
        }
        if repeat_open {
            errs.push("repeat_start has no repeat_end".into());
        }
        for [a, b] in &self.critical {
            if a >= b || *b > self.bars.len() {
                errs.push(format!(
                    "critical section [{a}, {b}] out of bars 0..{}",
                    self.bars.len()
                ));
            }
        }
        errs
    }

    /// Notes in beats from the start of the song (assumes `validate` passed).
    /// Length of the song in beats (bars times the numerator).
    pub fn total_beats(&self) -> f64 {
        self.played_bars().last().map_or(0.0, |bar| {
            let (_, (num, den)) = self.signature_at_bar(bar.source);
            bar.start_beat
                + num as f64 * self.time_signature().unwrap_or((4, 4)).1 as f64 / den as f64
        })
    }

    fn bar_structure(&self) -> Vec<BarStructure> {
        let mut out = vec![BarStructure::default(); self.bars.len()];
        for (i, bar) in self.bars.iter().enumerate() {
            let (num, unit) = self.signature_at_bar(i).1;
            let bar_len = Dur::new(num, unit);
            for (hand, text) in bar {
                if !matches!(hand.as_str(), "RH" | "LH" | "RH2" | "LH2") {
                    continue;
                }
                let mut t = Dur::ZERO;
                for event in parse_bar(text).unwrap_or_default() {
                    if let Event::Directive { name, arg } = &event {
                        let at_start = t == Dur::ZERO;
                        let at_end = t == bar_len;
                        match name.as_str() {
                            "repeat_start" if at_start => out[i].repeat_start = true,
                            "repeat_end" if at_end => out[i].repeat_end = true,
                            "volta" if at_start => {
                                if let Some(number) = arg.as_deref().and_then(parse_volta_number) {
                                    out[i].volta_start = Some(number);
                                }
                            }
                            "volta_end" if at_start => out[i].volta_end = true,
                            "segno" | "coda" | "dc_al_fine" | "dc_al_coda" | "ds_al_fine"
                            | "ds_al_coda" | "fine" | "to_coda" => {
                                if !out[i].navigation.contains(name) {
                                    out[i].navigation.push(name.clone());
                                }
                            }
                            _ => {}
                        }
                    }
                    t = t.add(event.dur());
                }
            }
        }
        out
    }

    /// Source bar indices in the order the learner hears them. Repeats run
    /// twice; endings and navigation jumps are resolved at bar boundaries.
    fn play_order(&self) -> Vec<usize> {
        let structure = self.bar_structure();
        let n = structure.len();
        if n == 0 {
            return Vec::new();
        }

        let mut voltas = Vec::new();
        let mut open_volta: Option<(usize, u8)> = None;
        for (i, marks) in structure.iter().enumerate() {
            if let Some(number) = marks.volta_start {
                if let Some((start, old_number)) = open_volta.replace((i, number)) {
                    voltas.push(VoltaSpan {
                        start,
                        end: i,
                        number: old_number,
                    });
                }
            }
            if marks.repeat_end {
                if let Some((start, number)) = open_volta.take() {
                    voltas.push(VoltaSpan {
                        start,
                        end: i + 1,
                        number,
                    });
                }
            } else if marks.volta_end {
                if let Some((start, number)) = open_volta.take() {
                    voltas.push(VoltaSpan {
                        start,
                        end: i,
                        number,
                    });
                }
            }
        }
        if let Some((start, number)) = open_volta {
            voltas.push(VoltaSpan {
                start,
                end: n,
                number,
            });
        }

        let segno = structure
            .iter()
            .position(|m| m.navigation.iter().any(|n| n == "segno"));
        let coda = structure
            .iter()
            .position(|m| m.navigation.iter().any(|n| n == "coda"));
        let mut order = Vec::new();
        let mut repeat_pass: BTreeMap<usize, u8> = BTreeMap::new();
        let mut repeat_start = 0usize;
        let mut dc_used = false;
        let mut ds_used = false;
        let mut coda_armed = false;
        let mut fine_armed = false;
        let mut i = 0usize;
        // The hard cap makes malformed or self-referential navigation fail
        // closed instead of hanging the audio/session thread.
        for _ in 0..(n.saturating_mul(64).saturating_add(256)) {
            if i >= n {
                break;
            }
            if structure[i].repeat_start {
                repeat_start = i;
            }

            if let Some(v) = voltas.iter().find(|v| v.start == i) {
                let pass = repeat_pass.get(&repeat_start).copied().unwrap_or(1);
                if (v.number == 1 && pass >= 2) || (v.number == 2 && pass < 2) {
                    i = v.end;
                    continue;
                }
            }

            order.push(i);
            let nav = &structure[i].navigation;
            if coda_armed && nav.iter().any(|n| n == "to_coda") {
                if let Some(at) = coda {
                    i = at;
                    coda_armed = false;
                    continue;
                }
            }
            if fine_armed && nav.iter().any(|n| n == "fine") {
                break;
            }

            let mut jump = None;
            if !dc_used && nav.iter().any(|n| n == "dc_al_fine" || n == "dc_al_coda") {
                dc_used = true;
                fine_armed = nav.iter().any(|n| n == "dc_al_fine");
                coda_armed = nav.iter().any(|n| n == "dc_al_coda");
                jump = Some(0);
            } else if !ds_used && nav.iter().any(|n| n == "ds_al_fine" || n == "ds_al_coda") {
                ds_used = true;
                fine_armed = nav.iter().any(|n| n == "ds_al_fine");
                coda_armed = nav.iter().any(|n| n == "ds_al_coda");
                jump = segno;
            }
            if let Some(at) = jump {
                i = at;
                continue;
            }

            if structure[i].repeat_end {
                let pass = repeat_pass.entry(repeat_start).or_insert(1);
                if *pass == 1 {
                    *pass = 2;
                    i = repeat_start;
                    continue;
                }
                repeat_pass.remove(&repeat_start);
                repeat_start = 0;
            }
            i += 1;
        }
        order
    }

    pub(crate) fn played_bar_sources(&self) -> Vec<usize> {
        self.play_order()
    }

    fn played_bars(&self) -> Vec<PlayedBar> {
        let base_unit = self.time_signature().unwrap_or((4, 4)).1;
        self.play_order()
            .into_iter()
            .scan(0.0, |start, source| {
                let played = PlayedBar {
                    source,
                    start_beat: *start,
                };
                let (_, (num, den)) = self.signature_at_bar(source);
                *start += num as f64 * base_unit as f64 / den as f64;
                Some(played)
            })
            .collect()
    }

    /// Dynamic and hairpin marks on the beat line, deduplicated across hands.
    /// Malformed directives are skipped here; `validate` reports them.
    pub fn marks(&self) -> Vec<TimedMark> {
        let unit = self.time_signature().unwrap_or((4, 4)).1;
        let mut out: Vec<TimedMark> = Vec::new();
        for played in self.played_bars() {
            let bar = &self.bars[played.source];
            let bar_start = played.start_beat;
            for text in bar.values() {
                let mut t = Dur::ZERO;
                for e in parse_bar(text).unwrap_or_default() {
                    if let Event::Directive { name, arg } = &e {
                        if let Ok(Some(mark)) = Mark::from_directive(name, arg.as_deref()) {
                            let beat = bar_start + t.beats(unit);
                            let seen = out
                                .iter()
                                .any(|m| (m.beat - beat).abs() < 1e-9 && m.mark == mark);
                            if !seen {
                                out.push(TimedMark { beat, mark });
                            }
                        }
                    }
                    t = t.add(e.dur());
                }
            }
        }
        out
    }

    pub fn timeline(&self) -> Vec<TimedNote> {
        let unit = self.time_signature().unwrap_or((4, 4)).1;
        let mut out = Vec::new();
        for (played_index, played) in self.played_bars().into_iter().enumerate() {
            let bar = &self.bars[played.source];
            let bar_start = played.start_beat;
            for (hand, text) in bar {
                let part = Part::from_key(hand);
                let voice = if hand.ends_with('2') { 2 } else { 1 };
                let mut t = Dur::ZERO;
                let events = parse_bar(text).unwrap_or_default();
                for (idx, e) in events.iter().enumerate() {
                    if let Event::Note {
                        pitches,
                        dur,
                        fingers,
                        ..
                    } = e
                    {
                        let tie = events.get(idx + 1).is_some_and(|next_e| {
                            matches!(next_e, Event::Directive { name, .. } if name == "tie")
                        });
                        for (k, &p) in pitches.iter().enumerate() {
                            out.push(TimedNote {
                                pitch: p,
                                start_beat: bar_start + t.beats(unit),
                                beats: dur.beats(unit),
                                left_hand: part == Part::Left,
                                accomp: matches!(
                                    part,
                                    Part::Acc | Part::Drums | Part::Bass | Part::Pad | Part::Choir
                                ),
                                part,
                                finger: fingers.get(k).copied(),
                                bar: played_index,
                                voice,
                                tie,
                            });
                        }
                    }
                    t = t.add(e.dur());
                }
            }
        }
        out.sort_by(|a, b| {
            a.start_beat
                .total_cmp(&b.start_beat)
                .then(a.pitch.cmp(&b.pitch))
        });
        let mut tied: Vec<TimedNote> = Vec::with_capacity(out.len());
        for note in out {
            if let Some(prev) = tied.iter_mut().rev().find(|prev| {
                prev.pitch == note.pitch
                    && prev.part == note.part
                    && prev.voice == note.voice
                    && prev.tie
                    && (prev.start_beat + prev.beats - note.start_beat).abs() < 1e-9
            }) {
                prev.beats += note.beats;
                // Keep the leading tie flag for notation rendering. The app
                // reconstructs the intermediate noteheads from the source.
                continue;
            }
            tied.push(note);
        }
        tied
    }
}

fn parse_time_signature(value: &str) -> Option<(u32, u32)> {
    let (n, d) = value.split_once('/')?;
    let (n, d): (u32, u32) = (n.trim().parse().ok()?, d.trim().parse().ok()?);
    (n > 0 && d > 0 && d.is_power_of_two()).then_some((n, d))
}

fn valid_key(key: &str) -> bool {
    matches!(
        key,
        "C" | "G"
            | "D"
            | "A"
            | "E"
            | "B"
            | "F#"
            | "C#"
            | "F"
            | "Bb"
            | "Eb"
            | "Ab"
            | "Db"
            | "Gb"
            | "Cb"
            | "Am"
            | "Em"
            | "Bm"
            | "F#m"
            | "C#m"
            | "G#m"
            | "D#m"
            | "A#m"
            | "Dm"
            | "Gm"
            | "Cm"
            | "Fm"
            | "Bbm"
            | "Ebm"
            | "Abm"
    )
}

fn parse_volta_number(arg: &str) -> Option<u8> {
    let values: Vec<u8> = serde_json::from_str(arg).ok()?;
    (values.len() == 1 && matches!(values[0], 1 | 2)).then_some(values[0])
}

/// `YYYY-MM-DD` with a month 1-12 and a day 1-31.
fn is_iso_date(s: &str) -> bool {
    let parts: Vec<&str> = s.split('-').collect();
    let num = |p: &str, len: usize| p.len() == len && p.bytes().all(|b| b.is_ascii_digit());
    if parts.len() != 3 || !num(parts[0], 4) || !num(parts[1], 2) || !num(parts[2], 2) {
        return false;
    }
    let (m, d): (u32, u32) = (parts[1].parse().unwrap(), parts[2].parse().unwrap());
    (1..=12).contains(&m) && (1..=31).contains(&d)
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

    fn bar(rh: &str) -> String {
        format!(r#"{{"RH":"{rh}"}}"#)
    }

    #[test]
    fn expands_repeat_with_first_and_second_endings() {
        let bars = format!(
            "[{}, {}, {}]",
            bar("{repeat_start} C4:4 D4:4 E4:4 F4:4"),
            bar("{volta: [1]} G4:4 A4:4 B4:4 C5:4 {repeat_end}"),
            bar("{volta: [2]} D5:4 E5:4 F5:4 G5:4")
        );
        let s = Song::from_json(&song(&bars, "")).unwrap();
        assert!(s.validate().is_empty(), "{:?}", s.validate());
        assert_eq!(s.played_bar_sources(), vec![0, 1, 0, 2]);
        assert_eq!(s.total_beats(), 16.0);
        let timeline = s.timeline();
        assert_eq!(timeline.iter().filter(|n| n.pitch == 60).count(), 2);
        assert_eq!(
            timeline.iter().find(|n| n.pitch == 74).unwrap().start_beat,
            12.0
        );
    }

    #[test]
    fn da_capo_al_fine_jumps_once_and_stops_at_fine() {
        let bars = format!(
            "[{}, {}, {}]",
            bar("C4:1"),
            bar("D4:1 {fine}"),
            bar("E4:1 {dc_al_fine}")
        );
        let s = Song::from_json(&song(&bars, "")).unwrap();
        assert_eq!(s.played_bar_sources(), vec![0, 1, 2, 0, 1]);
    }

    #[test]
    fn segno_to_coda_jumps_at_to_coda_once() {
        let bars = format!(
            "[{}, {}, {}, {}, {}, {}]",
            bar("C4:1 {segno}"),
            bar("D4:1"),
            bar("E4:1"),
            bar("F4:1 {ds_al_coda}"),
            bar("G4:1 {to_coda}"),
            bar("A4:1 {coda}")
        );
        let s = Song::from_json(&song(&bars, "")).unwrap();
        assert_eq!(s.played_bar_sources(), vec![0, 1, 2, 3, 0, 1, 2, 3, 4, 5]);
    }

    #[test]
    fn valid_song_has_no_errors_and_a_timeline() {
        let s = Song::from_json(&song(
            r#"[{"RH":"E4:4@3 D4:4@2 C4:2@1","LH":"C3:1@5"}]"#,
            "",
        ))
        .unwrap();
        assert_eq!(s.validate(), Vec::<String>::new());
        let t = s.timeline();
        assert_eq!(t.len(), 4);
        assert_eq!(
            (t[0].pitch, t[0].start_beat, t[0].beats, t[0].left_hand),
            (48, 0.0, 4.0, true)
        );
        let c4 = t.iter().find(|n| n.pitch == 60).unwrap();
        assert_eq!((c4.start_beat, c4.beats, c4.finger), (2.0, 2.0, Some(1)));
        assert_eq!(c4.voice, 1);
    }

    #[test]
    fn two_voices_per_hand_and_spacers() {
        let s = Song::from_json(&song(
            r#"[{"RH":"E4:4 F4:4 G4:4 A4:4","RH2":"C4:1","LH":"C3:1"},{"RH":"s:2 G4:2","RH2":"E4:1","LH":"C3:1"}]"#,
            "",
        ))
        .unwrap();
        assert_eq!(s.validate(), Vec::<String>::new());
        let t = s.timeline();
        let rh2: Vec<&TimedNote> = t.iter().filter(|n| n.voice == 2).collect();
        assert_eq!(rh2.len(), 2);
        assert_eq!(rh2[0].pitch, 60); // C4
        assert_eq!(rh2[0].part, Part::Right);
        assert!(!rh2[0].left_hand);
        assert_eq!(rh2[1].pitch, 64); // E4
    }

    #[test]
    fn voice_2_without_voice_1_is_rejected() {
        let s = Song::from_json(&song(r#"[{"RH2":"C4:1","LH":"C3:1"}]"#, "")).unwrap();
        let errs = s.validate();
        assert!(errs.iter().any(|e| e.contains("RH2 without RH")));

        let s2 = Song::from_json(&song(r#"[{"RH":"C4:1","LH2":"C3:1"}]"#, "")).unwrap();
        let errs2 = s2.validate();
        assert!(errs2.iter().any(|e| e.contains("LH2 without LH")));
    }

    #[test]
    fn unison_in_two_voices_is_allowed() {
        let s = Song::from_json(&song(
            r#"[{"RH":"C4:4 D4:4 E4:4 F4:4","RH2":"C4:1","LH":"C3:1"}]"#,
            "",
        ))
        .unwrap();
        assert_eq!(s.validate(), Vec::<String>::new());
    }

    #[test]
    fn overlap_in_two_voices_with_different_onsets_is_rejected() {
        // Voice 1 holds C4 for half note at beat 0; voice 2 strikes C4 at beat 1
        let s = Song::from_json(&song(
            r#"[{"RH":"C4:2 D4:2","RH2":"r:4 C4:4 r:2","LH":"C3:1"}]"#,
            "",
        ))
        .unwrap();
        let errs = s.validate();
        assert!(errs
            .iter()
            .any(|e| e.contains("pitch 60 overlaps between voice 1 and voice 2")));
    }

    #[test]
    fn bar_length_mismatch_is_reported() {
        let s = Song::from_json(&song(r#"[{"RH":"C4:4 D4:4"}]"#, "")).unwrap();
        assert!(s
            .validate()
            .iter()
            .any(|e| e.contains("length 1/2, expected 1/1")));
    }

    #[test]
    fn license_and_source_rules() {
        let text = song(r#"[{"RH":"C4:1"}]"#, "")
            .replace("CC-BY-SA-4.0", "All rights reserved")
            .replace(r#""source":"original""#, r#""source":"musescore""#);
        let errs = Song::from_json(&text).unwrap().validate();
        assert!(errs
            .iter()
            .any(|e| e.contains("license `All rights reserved`")));
        assert!(errs.iter().any(|e| e.contains("source_url required")));
    }

    #[test]
    fn restricted_regions_need_a_code_and_a_date() {
        let ok = song(
            r#"[{"RH":"C4:1"}]"#,
            r#","restricted_in":[{"region":"US","until":"2036-01-01"}]"#,
        );
        let s = Song::from_json(&ok).unwrap();
        assert_eq!(s.validate(), Vec::<String>::new());
        assert_eq!(s.restricted_in[0].region, "US");
        let bad = song(
            r#"[{"RH":"C4:1"}]"#,
            r#","restricted_in":[{"region":"usa","until":"2036-13-01"}]"#,
        );
        let errs = Song::from_json(&bad).unwrap().validate();
        assert!(errs.iter().any(|e| e.contains("region `usa`")));
        assert!(errs.iter().any(|e| e.contains("until `2036-13-01`")));
    }

    #[test]
    fn generated_songs_need_provenance_and_cc0() {
        let base = song(r#"[{"RH":"C4:1"}]"#, "")
            .replace(r#""source":"original""#, r#""source":"generated""#);
        let errs = Song::from_json(&base).unwrap().validate();
        assert!(
            errs.iter().any(|e| e.contains("`generator` required")),
            "{errs:?}"
        );
        assert!(
            errs.iter().any(|e| e.contains("must be CC0-1.0")),
            "{errs:?}"
        );
        let ok = base.replace("CC-BY-SA-4.0", "CC0-1.0");
        let ok = ok.replace(r#""bars""#, r#""generator":{"method":"llm","tool":"compose-song","model":"m","seed":7},"spec_node":"essentials-1/eighths","bars""#);
        assert_eq!(
            Song::from_json(&ok).unwrap().validate(),
            Vec::<String>::new()
        );
        let bad = ok
            .replace(r#""method":"llm""#, r#""method":"pd-variation""#)
            .replace("essentials-1/eighths", "eighths");
        let errs = Song::from_json(&bad).unwrap().validate();
        assert!(
            errs.iter().any(|e| e.contains("source_song required")),
            "{errs:?}"
        );
        assert!(
            errs.iter().any(|e| e.contains("must be `course/node`")),
            "{errs:?}"
        );
        let stray = song(r#"[{"RH":"C4:1"}]"#, r#","generator":{"method":"hand"}"#);
        assert!(Song::from_json(&stray)
            .unwrap()
            .validate()
            .iter()
            .any(|e| e.contains("only allowed")));
    }

    #[test]
    fn drums_and_bass_are_backing_parts() {
        let s = Song::from_json(&song(
            r#"[{"RH":"C4:1","DRUMS":"C2F#2:4 D2F#2:4 C2F#2:4 D2F#2:4","BASS":"C2:2 G1:2"}]"#,
            "",
        ))
        .unwrap();
        assert_eq!(s.validate(), Vec::<String>::new());
        let t = s.timeline();
        assert!(t
            .iter()
            .filter(|n| n.part == Part::Drums)
            .all(|n| n.accomp && DRUM_PITCHES.contains(&n.pitch)));
        assert_eq!(t.iter().filter(|n| n.part == Part::Drums).count(), 8);
        let bass: Vec<u8> = t
            .iter()
            .filter(|n| n.part == Part::Bass)
            .map(|n| n.pitch)
            .collect();
        assert_eq!(bass, vec![36, 31]);
        assert!(t.iter().any(|n| n.part == Part::Right && !n.accomp));
    }

    #[test]
    fn pad_is_a_backing_part() {
        let s = Song::from_json(&song(
            r#"[{"RH":"C4:1","PAD":"C3E3G3:1","CHOIR":"G4:2 E4:2"}]"#,
            "",
        ))
        .unwrap();
        assert_eq!(s.validate(), Vec::<String>::new());
        let pad: Vec<TimedNote> = s
            .timeline()
            .into_iter()
            .filter(|n| n.part == Part::Pad)
            .collect();
        assert_eq!(pad.len(), 3);
        assert!(pad.iter().all(|n| n.accomp && n.beats == 4.0));
        let choir: Vec<u8> = s
            .timeline()
            .into_iter()
            .filter(|n| n.part == Part::Choir && n.accomp)
            .map(|n| n.pitch)
            .collect();
        assert_eq!(choir, vec![67, 64]);
    }

    #[test]
    fn drums_reject_unknown_kit_pieces() {
        let s = Song::from_json(&song(r#"[{"RH":"C4:1","DRUMS":"C4:1"}]"#, "")).unwrap();
        assert!(s
            .validate()
            .iter()
            .any(|e| e.contains("DRUMS: pitch 60 is not a drum")));
    }

    #[test]
    fn three_four_time_counts_three_beats() {
        let s = Song::from_json(
            &song(r#"[{"RH":"C4:2."}, {"RH":"D4:2 E4:4"}]"#, "").replace("4/4", "3/4"),
        )
        .unwrap();
        assert!(s.validate().is_empty());
        assert_eq!(s.timeline()[1].start_beat, 3.0);
    }

    #[test]
    fn key_and_meter_changes_apply_from_the_selected_bar() {
        let text = song(
            r#"[{"RH":"C4:1"},{"RH":"G4:2."},{"RH":"F#4:2."}]"#,
            r#", "changes":[{"bar":2,"time":"3/4","key":"G"}]"#,
        );
        let s = Song::from_json(&text).unwrap();
        assert!(s.validate().is_empty(), "{:?}", s.validate());
        assert_eq!(s.signature_at_bar(0), ("C".into(), (4, 4)));
        assert_eq!(s.signature_at_bar(1), ("G".into(), (3, 4)));
        assert_eq!(s.total_beats(), 10.0);
        let timeline = s.timeline();
        assert_eq!(timeline[1].start_beat, 4.0);
        assert_eq!(timeline[2].start_beat, 7.0);
    }

    #[test]
    fn signature_changes_must_be_valid_and_unique() {
        let text = song(
            r#"[{"RH":"C4:1"},{"RH":"G4:1"},{"RH":"A4:1"}]"#,
            r#", "changes":[{"bar":2,"key":"H"},{"bar":2,"time":"3/7"},{"bar":4,"key":"D"}]"#,
        );
        let errs = Song::from_json(&text).unwrap().validate();
        assert!(errs.iter().any(|e| e.contains("invalid key")), "{errs:?}");
        assert!(errs.iter().any(|e| e.contains("invalid time")), "{errs:?}");
        assert!(
            errs.iter()
                .any(|e| e.contains("multiple signature changes")),
            "{errs:?}"
        );
        assert!(errs.iter().any(|e| e.contains("within 2..3")), "{errs:?}");
    }

    #[test]
    fn measure_starts_follow_expanded_repeat_order() {
        let text = song(
            r#"[{"RH":"{repeat_start} C4:1"},{"RH":"G4:1 {repeat_end}"},{"RH":"A4:1"}]"#,
            "",
        );
        let s = Song::from_json(&text).unwrap();
        assert_eq!(s.measure_starts(), [0., 4., 8., 12., 16., 20.]);
    }

    #[test]
    fn spanish_romance_restores_the_major_strain_and_repeats_both_sections() {
        let song =
            Song::from_json(include_str!("../../content/songs/spanish-romance.json")).unwrap();
        assert!(song.validate().is_empty(), "{:?}", song.validate());
        assert_eq!(song.bars.len(), 32);
        assert_eq!(song.signature_at_bar(16), ("E".into(), (3, 4)));
        assert_eq!(song.played_bar_sources().len(), 64);
        assert_eq!(song.played_signature_changes().len(), 1);
    }

    #[test]
    fn tied_continuation_extends_the_timeline_note_without_a_restrike() {
        let s = Song::from_json(&song(
            r#"[{"RH":"C4:2 D4:2 {tie}"}, {"RH":"D4:2 E4:2"}]"#,
            "",
        ))
        .unwrap();
        assert!(s.validate().is_empty());
        let t = s.timeline();
        assert_eq!(t.len(), 3);
        assert_eq!(t[1].pitch, 62);
        assert!(t[1].tie);
        assert_eq!(t[1].beats, 4.0);
    }

    #[test]
    fn repeat_and_volta_directives_are_linted_for_position_and_nesting() {
        let s = Song::from_json(&song(
            r#"[{"RH":"{repeat_start} C4:4 D4:4 E4:4 F4:4"},{"RH":"{repeat_start} C4:4 D4:4 E4:4 F4:4 {repeat_end}"},{"RH":"C4:4 {repeat_start} D4:4 E4:4 F4:4"}]"#,
            "",
        ))
        .unwrap();
        let errors = s.validate();
        assert!(errors.iter().any(|e| e.contains("must be at a bar line")));
        assert!(errors
            .iter()
            .any(|e| e.contains("nested repeats are not supported")));
    }

    #[test]
    fn unknown_dynamic_is_a_lint_error() {
        let s = Song::from_json(&song(r#"[{"RH":"{dyn:\"x\"} C4:1","LH":"C3:1"}]"#, "")).unwrap();
        let errs = s.validate();
        assert!(
            errs.iter().any(|e| e.contains("unknown dynamic")),
            "{errs:?}"
        );
    }

    #[test]
    fn dynamics_and_hairpins_sit_on_the_beat_line() {
        let s = Song::from_json(&song(
            r#"[{"RH":"{dyn:\"p\"} C4:4 {cresc} D4:4 E4:4 F4:4","LH":"C3:1"},
                {"RH":"{dyn:\"f\"} C4:1","LH":"C3:1"}]"#,
            "",
        ))
        .unwrap();
        assert!(s.validate().is_empty(), "{:?}", s.validate());
        let marks = s.marks();
        let beats: Vec<f64> = marks.iter().map(|m| m.beat).collect();
        assert_eq!(beats, vec![0.0, 1.0, 4.0]);
        let l = crate::dynamics::layout(&marks, s.total_beats());
        assert_eq!(l.dynamics.len(), 2);
        assert_eq!(l.hairpins.len(), 1);
        assert_eq!(l.hairpins[0].end, 4.0);
    }
}
