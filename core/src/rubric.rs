//! Rubric for generated practice songs (docs/specs/skill-specs.md).
//!
//! `TaughtSet` is what a learner has seen up to a journey node (pitches per hand,
//! durations, meters, accidentals, largest leap, chord size), derived from songs.
//! `NodeSpec` is the node's target from `content/skill-specs/<course>.json`.
//! `check` lists every way a song leaves the taught set or misses the node's
//! required patterns. Empty means the song passes.

use crate::notation::{parse_bar, Dur, Event};
use crate::pitch::{parse_pitch, pitch_name};
use crate::song::Song;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::{BTreeMap, BTreeSet};

/// Graded hands. Backing parts are played by the app and never checked.
pub const GRADED: [&str; 2] = ["RH", "LH"];
/// Widest chord a beginner hand can hold, in semitones (an octave).
pub const MAX_CHORD_SPAN: u8 = 12;
/// Pitch classes of the black keys (C#, D#, F#, G#, A#).
const BLACK: [u8; 5] = [1, 3, 6, 8, 10];

/// One note or chord of a graded hand.
#[derive(Debug, Clone)]
struct Hit {
    bar: usize,
    /// Onset from the start of the song, in whole notes.
    at: f64,
    pitches: Vec<u8>,
    dur: Dur,
    fingers: Vec<u8>,
}

/// Graded notes of a song, per hand, in time order.
#[derive(Debug, Default)]
struct Analysis {
    hits: BTreeMap<&'static str, Vec<Hit>>,
    /// Rest duration labels per hand, with the first bar each appears in.
    rests: BTreeMap<&'static str, BTreeMap<String, usize>>,
    /// Bars that do not parse (`bar N HAND: error`).
    errors: Vec<String>,
}

impl Analysis {
    fn has_rests(&self) -> bool {
        self.rests.values().any(|r| !r.is_empty())
    }
}

fn analyse(song: &Song) -> Analysis {
    let mut a = Analysis::default();
    let bar_len = song
        .time_signature()
        .map_or(1.0, |(n, d)| n as f64 / d as f64);
    for (i, bar) in song.bars.iter().enumerate() {
        for hand in GRADED {
            let Some(text) = bar.get(hand) else { continue };
            let mut t = Dur::ZERO;
            let events = match parse_bar(text) {
                Ok(ev) => ev,
                Err(e) => {
                    a.errors.push(format!("bar {} {hand}: {e}", i + 1));
                    continue;
                }
            };
            for e in events {
                match &e {
                    Event::Note {
                        pitches,
                        dur,
                        fingers,
                        ..
                    } => a.hits.entry(hand).or_default().push(Hit {
                        bar: i,
                        at: i as f64 * bar_len + t.as_f64(),
                        pitches: pitches.clone(),
                        dur: *dur,
                        fingers: fingers.clone(),
                    }),
                    Event::Rest { dur } => {
                        a.rests
                            .entry(hand)
                            .or_default()
                            .entry(dur_label(*dur))
                            .or_insert(i);
                    }
                    Event::Directive { .. } => {}
                }
                t = t.add(e.dur());
            }
        }
    }
    a
}

/// Duration as the notation writes it: `4`, `8`, `2.`, else `num/den`.
pub fn dur_label(d: Dur) -> String {
    match d.num {
        1 => d.den.to_string(),
        3 if d.den.is_multiple_of(2) => format!("{}.", d.den / 2),
        7 if d.den.is_multiple_of(4) => format!("{}..", d.den / 4),
        _ => d.to_string(),
    }
}

/// Pitch class of an accidental name such as `F#` or `Bb`.
pub fn accidental_class(name: &str) -> Option<u8> {
    parse_pitch(&format!("{name}4")).ok().map(|p| p % 12)
}

fn uses_flats(key: &str) -> bool {
    ["F", "Bb", "Eb", "Ab", "Db", "Dm", "Gm", "Cm", "Fm"].contains(&key)
}

fn class_name(pc: u8, flats: bool) -> &'static str {
    const SHARP: [&str; 12] = [
        "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B",
    ];
    const FLAT: [&str; 12] = [
        "C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B",
    ];
    if flats {
        FLAT[pc as usize]
    } else {
        SHARP[pc as usize]
    }
}

/// Melodic line of a hand: top note for RH, bottom note for LH.
fn line_note(hand: &str, h: &Hit) -> u8 {
    let it = h.pitches.iter().copied();
    if hand == "LH" {
        it.min().unwrap_or(0)
    } else {
        it.max().unwrap_or(0)
    }
}

fn max_leap(hand: &str, hits: &[Hit]) -> u8 {
    hits.windows(2)
        .map(|w| line_note(hand, &w[0]).abs_diff(line_note(hand, &w[1])))
        .max()
        .unwrap_or(0)
}

/// Both hands start a note at the same moment somewhere.
fn hands_together(a: &Analysis) -> bool {
    let (Some(r), Some(l)) = (a.hits.get("RH"), a.hits.get("LH")) else {
        return false;
    };
    r.iter()
        .any(|x| l.iter().any(|y| (x.at - y.at).abs() < 1e-9))
}

/// What a learner has been taught. Union of the songs seen so far.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct TaughtSet {
    /// MIDI pitches per graded hand.
    pub pitches: BTreeMap<String, BTreeSet<u8>>,
    /// Note duration labels (`4`, `8`, `2.`).
    pub durations: BTreeSet<String>,
    /// Rest duration labels.
    pub rest_durations: BTreeSet<String>,
    pub times: BTreeSet<String>,
    /// Black-key pitch classes (1 = C#/Db … 10 = A#/Bb).
    pub accidentals: BTreeSet<u8>,
    /// Largest melodic leap in one hand, in semitones.
    pub max_interval: u8,
    /// Most notes struck at once per hand.
    pub polyphony: BTreeMap<String, usize>,
    pub rests: bool,
    pub hands_together: bool,
    /// Keys seen, used only to spell accidentals.
    pub keys: BTreeSet<String>,
}

impl TaughtSet {
    /// Fails with the bars that do not parse (lint reports those too).
    pub fn from_song(song: &Song) -> Result<TaughtSet, Vec<String>> {
        let a = analyse(song);
        if !a.errors.is_empty() {
            return Err(a.errors);
        }
        let mut t = TaughtSet {
            rests: a.has_rests(),
            hands_together: hands_together(&a),
            ..Default::default()
        };
        t.rest_durations = a.rests.values().flat_map(|r| r.keys().cloned()).collect();
        t.times.insert(song.time.clone());
        t.keys.insert(song.key.clone());
        for (hand, hits) in &a.hits {
            let set = t.pitches.entry(hand.to_string()).or_default();
            for h in hits {
                set.extend(&h.pitches);
                t.durations.insert(dur_label(h.dur));
                t.accidentals.extend(
                    h.pitches
                        .iter()
                        .map(|p| p % 12)
                        .filter(|c| BLACK.contains(c)),
                );
            }
            t.max_interval = t.max_interval.max(max_leap(hand, hits));
            t.polyphony.insert(
                hand.to_string(),
                hits.iter().map(|h| h.pitches.len()).max().unwrap_or(0),
            );
        }
        Ok(t)
    }

    pub fn merge(&mut self, o: &TaughtSet) {
        for (h, s) in &o.pitches {
            self.pitches.entry(h.clone()).or_default().extend(s);
        }
        for (h, &n) in &o.polyphony {
            let e = self.polyphony.entry(h.clone()).or_default();
            *e = (*e).max(n);
        }
        self.durations.extend(o.durations.iter().cloned());
        self.rest_durations.extend(o.rest_durations.iter().cloned());
        self.times.extend(o.times.iter().cloned());
        self.accidentals.extend(&o.accidentals);
        self.keys.extend(o.keys.iter().cloned());
        self.max_interval = self.max_interval.max(o.max_interval);
        self.rests |= o.rests;
        self.hands_together |= o.hands_together;
    }

    fn flats(&self) -> bool {
        self.keys.iter().any(|k| uses_flats(k))
    }

    /// Readable JSON for `content specs` (pitch names, accidental names).
    pub fn to_json(&self) -> Value {
        let flats = self.flats();
        let pitches: BTreeMap<&String, Vec<String>> = self
            .pitches
            .iter()
            .map(|(h, s)| (h, s.iter().map(|&p| pitch_name(p)).collect()))
            .collect();
        let accidentals: Vec<String> = self
            .accidentals
            .iter()
            .flat_map(|&c| {
                let (s, f) = (class_name(c, false), class_name(c, true));
                if flats && s != f {
                    vec![s.to_string(), f.to_string()]
                } else {
                    vec![s.to_string()]
                }
            })
            .collect();
        json!({
            "pitches": pitches,
            "durations": self.durations,
            "rest_durations": self.rest_durations,
            "times": self.times,
            "accidentals": accidentals,
            "max_interval": self.max_interval,
            "polyphony": self.polyphony,
            "rests": self.rests,
            "hands_together": self.hands_together,
        })
    }
}

/// A musical feature a node's songs must show. Every key present must hold.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Pattern {
    /// Duration label that must appear (`8`, `2.`).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rhythm: Option<String>,
    /// With `rhythm`: share of bars (0..1) that contain it. Default: any bar.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub min_bar_share: Option<f64>,
    /// A melodic interval of at least this size, as an interval number
    /// (2 = second, 3 = third … 8 = octave).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub interval_min: Option<u8>,
    /// An accidental that must appear (`F#`, `Bb`).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub accidental: Option<String>,
    /// A pitch that must appear (`A4`), in `hand` if given.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub pitch: Option<String>,
    /// Limits `pitch`, `chord`, `rhythm` to one hand (`RH` / `LH`).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hand: Option<String>,
    /// At least one rest in a graded hand.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rest: Option<bool>,
    /// At least one chord (2+ notes at once).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub chord: Option<bool>,
    /// Both hands start a note together somewhere.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hands_together: Option<bool>,
}

/// Smallest semitone size of an interval number (minor third = 3 for `3`).
pub fn interval_semitones(number: u8) -> Option<u8> {
    [0, 0, 1, 3, 5, 7, 8, 10, 12]
        .get(number as usize)
        .copied()
        .filter(|_| number >= 2)
}

impl Pattern {
    /// Problems with the pattern itself (for linting spec files).
    pub fn validate(&self) -> Vec<String> {
        let mut errs = Vec::new();
        let keys = [
            self.rhythm.is_some(),
            self.interval_min.is_some(),
            self.accidental.is_some(),
            self.pitch.is_some(),
            self.rest.is_some(),
            self.chord.is_some(),
            self.hands_together.is_some(),
        ];
        if !keys.contains(&true) {
            errs.push("pattern has no requirement".into());
        }
        if let Some(s) = self.min_bar_share {
            if self.rhythm.is_none() || !(0.0..=1.0).contains(&s) {
                errs.push(format!("min_bar_share {s} needs `rhythm` and 0..1"));
            }
        }
        if let Some(n) = self
            .interval_min
            .filter(|&n| interval_semitones(n).is_none())
        {
            errs.push(format!("interval_min {n} not in 2..8"));
        }
        if let Some(a) = self
            .accidental
            .as_deref()
            .filter(|a| accidental_class(a).is_none_or(|c| !BLACK.contains(&c)))
        {
            errs.push(format!("accidental `{a}` is not a black key"));
        }
        if let Some(p) = self.pitch.as_deref().filter(|p| parse_pitch(p).is_err()) {
            errs.push(format!("bad pitch `{p}`"));
        }
        if let Some(h) = self.hand.as_deref().filter(|h| !GRADED.contains(h)) {
            errs.push(format!("unknown hand `{h}`"));
        }
        errs
    }

    fn describe(&self) -> String {
        serde_json::to_string(&self.as_json()).unwrap_or_default()
    }

    fn as_json(&self) -> Value {
        let mut o = serde_json::Map::new();
        macro_rules! put { ($($f:ident),*) => { $( if let Some(v) = &self.$f { o.insert(stringify!($f).into(), json!(v)); } )* } }
        put!(
            rhythm,
            min_bar_share,
            interval_min,
            accidental,
            pitch,
            hand,
            rest,
            chord,
            hands_together
        );
        Value::Object(o)
    }

    fn holds(&self, a: &Analysis, n_bars: usize) -> bool {
        let hits: Vec<(&str, &Hit)> = a
            .hits
            .iter()
            .filter(|(h, _)| self.hand.as_deref().is_none_or(|w| w == **h))
            .flat_map(|(h, v)| v.iter().map(move |x| (*h, x)))
            .collect();
        if let Some(r) = &self.rhythm {
            let bars: BTreeSet<usize> = hits
                .iter()
                .filter(|(_, x)| &dur_label(x.dur) == r)
                .map(|(_, x)| x.bar)
                .collect();
            let need = self.min_bar_share.unwrap_or(0.0);
            if bars.is_empty() || (bars.len() as f64) < need * n_bars as f64 - 1e-9 {
                return false;
            }
        }
        if let Some(n) = self.interval_min {
            let min = interval_semitones(n).unwrap_or(u8::MAX);
            let lines = a
                .hits
                .iter()
                .filter(|(h, _)| self.hand.as_deref().is_none_or(|w| w == **h));
            if !lines.into_iter().any(|(h, v)| max_leap(h, v) >= min) {
                return false;
            }
        }
        if let Some(c) = self.accidental.as_deref().and_then(accidental_class) {
            if !hits
                .iter()
                .any(|(_, x)| x.pitches.iter().any(|p| p % 12 == c))
            {
                return false;
            }
        }
        if let Some(p) = self.pitch.as_deref().and_then(|p| parse_pitch(p).ok()) {
            if !hits.iter().any(|(_, x)| x.pitches.contains(&p)) {
                return false;
            }
        }
        if self.rest == Some(true) && !a.has_rests() {
            return false;
        }
        if self.chord == Some(true) && !hits.iter().any(|(_, x)| x.pitches.len() > 1) {
            return false;
        }
        if self.hands_together == Some(true) && !hands_together(a) {
            return false;
        }
        true
    }
}

/// Target for generated songs at one journey node.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct NodeSpec {
    pub node: String,
    /// What this node teaches, in words.
    pub new_skill: String,
    #[serde(default)]
    pub required: Vec<Pattern>,
    /// Bar count range, inclusive.
    pub bars: [usize; 2],
    /// Tempo range, inclusive.
    pub bpm: [f64; 2],
    /// `RH`, `LH` or `both`.
    pub hands: String,
    pub time: String,
}

/// One `content/skill-specs/<course>.json` file.
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CourseSpecs {
    pub course: String,
    pub nodes: Vec<NodeSpec>,
}

impl NodeSpec {
    /// Problems with the spec itself.
    pub fn validate(&self) -> Vec<String> {
        let mut errs = Vec::new();
        if self.new_skill.trim().is_empty() {
            errs.push("`new_skill` is empty".into());
        }
        if self.bars[0] == 0 || self.bars[0] > self.bars[1] {
            errs.push(format!("bars {:?} must be 1..=max", self.bars));
        }
        if !(20.0..=300.0).contains(&self.bpm[0])
            || self.bpm[0] > self.bpm[1]
            || self.bpm[1] > 300.0
        {
            errs.push(format!("bpm {:?} must be a range in 20..300", self.bpm));
        }
        if !["RH", "LH", "both"].contains(&self.hands.as_str()) {
            errs.push(format!("unknown hands `{}`", self.hands));
        }
        for (i, p) in self.required.iter().enumerate() {
            errs.extend(
                p.validate()
                    .into_iter()
                    .map(|e| format!("required[{i}]: {e}")),
            );
        }
        errs
    }
}

/// Every way `song` breaks the taught set or the node spec. Empty = pass.
pub fn check(song: &Song, taught: &TaughtSet, spec: &NodeSpec) -> Vec<String> {
    let a = analyse(song);
    if !a.errors.is_empty() {
        return a.errors;
    }
    let mut errs = Vec::new();
    if song.time != spec.time {
        errs.push(format!("time {} but node wants {}", song.time, spec.time));
    }
    if !(spec.bpm[0]..=spec.bpm[1]).contains(&song.bpm) {
        errs.push(format!("bpm {} outside {:?}", song.bpm, spec.bpm));
    }
    if !(spec.bars[0]..=spec.bars[1]).contains(&song.bars.len()) {
        errs.push(format!("{} bars outside {:?}", song.bars.len(), spec.bars));
    }
    let has = |h: &str| a.hits.get(h).is_some_and(|v| !v.is_empty());
    let want: &[&str] = match spec.hands.as_str() {
        "RH" => &["RH"],
        "LH" => &["LH"],
        _ => &["RH", "LH"],
    };
    for h in GRADED {
        match (want.contains(&h), has(h)) {
            (true, false) => errs.push(format!("node wants {h} notes, song has none")),
            (false, true) => errs.push(format!("node is {}-only, song has {h} notes", spec.hands)),
            _ => {}
        }
    }
    errs.extend(taught_errors(song, &a, taught));
    for p in &spec.required {
        if !p.holds(&a, song.bars.len()) {
            errs.push(format!("missing required pattern {}", p.describe()));
        }
    }
    errs
}

/// What practice mode needs to judge a generated tune at one node (D28):
/// the cumulative taught set and the node's spec, as `content practice-pack`
/// writes them.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PracticeNode {
    pub taught: TaughtSet,
    pub spec: NodeSpec,
}

/// Rubric gate for a tune generated at run time. Empty = it may be shown.
/// Fails closed: bad JSON, or a song not marked `source: generated` with a
/// `melody-model` generator, is an error, never a pass.
pub fn check_generated(song_json: &str, node_json: &str) -> Vec<String> {
    let node: PracticeNode = match serde_json::from_str(node_json) {
        Ok(n) => n,
        Err(e) => return vec![format!("practice node: {e}")],
    };
    let song = match Song::from_json(song_json) {
        Ok(s) => s,
        Err(e) => return vec![format!("song: {e}")],
    };
    let mut errs = Vec::new();
    if song.source != "generated"
        || song.generator.as_ref().map(|g| g.method.as_str()) != Some("melody-model")
    {
        errs.push("practice tunes must be marked source `generated` by `melody-model`".to_string());
    }
    errs.extend(check(&song, &node.taught, &node.spec));
    errs
}

/// The part of `check` that compares a song with a taught set only (no node
/// spec). Empty means a learner who reached that set has seen everything in it.
/// `difficulty::node_fit` uses this, so the two never disagree.
pub fn taught_violations(song: &Song, taught: &TaughtSet) -> Vec<String> {
    let a = analyse(song);
    if !a.errors.is_empty() {
        return a.errors;
    }
    taught_errors(song, &a, taught)
}

fn taught_errors(song: &Song, a: &Analysis, taught: &TaughtSet) -> Vec<String> {
    let mut errs = Vec::new();
    let flats = uses_flats(&song.key) || taught.flats();
    if !taught.times.contains(&song.time) {
        errs.push(format!("time {} not taught yet", song.time));
    }
    for (hand, hits) in &a.hits {
        let allowed = taught.pitches.get(*hand);
        let extra: BTreeSet<u8> = hits
            .iter()
            .flat_map(|h| h.pitches.iter().copied())
            .filter(|p| !allowed.is_some_and(|s| s.contains(p)))
            .collect();
        if !extra.is_empty() {
            let names: Vec<String> = extra.iter().map(|&p| pitch_name(p)).collect();
            errs.push(format!("{hand}: pitches not taught: {}", names.join(" ")));
        }
        let durs: BTreeSet<String> = hits
            .iter()
            .map(|h| dur_label(h.dur))
            .filter(|d| !taught.durations.contains(d))
            .collect();
        if !durs.is_empty() {
            errs.push(format!(
                "{hand}: durations not taught: {}",
                durs.into_iter().collect::<Vec<_>>().join(" ")
            ));
        }
        let leap = max_leap(hand, hits);
        if leap > taught.max_interval {
            errs.push(format!(
                "{hand}: leap of {leap} semitones, taught up to {}",
                taught.max_interval
            ));
        }
        let poly = hits.iter().map(|h| h.pitches.len()).max().unwrap_or(0);
        let taught_poly = taught.polyphony.get(*hand).copied().unwrap_or(0);
        if poly > taught_poly {
            errs.push(format!(
                "{hand}: {poly} notes at once, taught up to {taught_poly}"
            ));
        }
        for h in hits {
            let span = h.pitches.iter().max().unwrap_or(&0) - h.pitches.iter().min().unwrap_or(&0);
            if span > MAX_CHORD_SPAN {
                errs.push(format!(
                    "bar {} {hand}: chord spans {span} semitones (max {MAX_CHORD_SPAN})",
                    h.bar + 1
                ));
            }
            if h.fingers.len() == h.pitches.len() && h.pitches.len() > 1 {
                let mut pf: Vec<(u8, u8)> = h
                    .pitches
                    .iter()
                    .copied()
                    .zip(h.fingers.iter().copied())
                    .collect();
                pf.sort();
                let ok = pf.windows(2).all(|w| {
                    if *hand == "LH" {
                        w[0].1 > w[1].1
                    } else {
                        w[0].1 < w[1].1
                    }
                });
                if !ok {
                    errs.push(format!(
                        "bar {} {hand}: chord fingering out of order",
                        h.bar + 1
                    ));
                }
            }
        }
    }
    let used: BTreeSet<u8> = a
        .hits
        .values()
        .flatten()
        .flat_map(|h| h.pitches.iter().map(|p| p % 12))
        .filter(|c| BLACK.contains(c))
        .collect();
    let extra: Vec<&str> = used
        .difference(&taught.accidentals)
        .map(|&c| class_name(c, flats))
        .collect();
    if !extra.is_empty() {
        errs.push(format!("accidentals not taught: {}", extra.join(" ")));
    }
    if a.has_rests() && !taught.rests {
        errs.push("rests not taught yet".into());
    }
    for (hand, rests) in &a.rests {
        let extra: Vec<String> = rests
            .iter()
            .filter(|(d, _)| taught.rests && !taught.rest_durations.contains(*d))
            .map(|(d, bar)| format!("{d} (bar {})", bar + 1))
            .collect();
        if !extra.is_empty() {
            errs.push(format!(
                "{hand}: rest durations not taught: {}",
                extra.join(" ")
            ));
        }
    }
    if hands_together(a) && !taught.hands_together {
        errs.push("hands together not taught yet".into());
    }
    errs
}

#[cfg(test)]
mod tests {
    use super::*;

    fn song(time: &str, bars: &str) -> Song {
        Song::from_json(&format!(
            r#"{{"id":"t","title":"T","composer":"Trad.","arranger":"X","source":"original",
            "license":"CC0-1.0","composition_license":"public-domain","bpm":90,"time":"{time}","key":"C","bars":{bars}}}"#
        ))
        .unwrap()
    }

    fn spec(hands: &str, required: &str) -> NodeSpec {
        serde_json::from_str(&format!(
            r#"{{"node":"n","new_skill":"x","required":{required},"bars":[1,16],"bpm":[60,120],"hands":"{hands}","time":"4/4"}}"#
        ))
        .unwrap()
    }

    fn taught_from(bars: &str) -> TaughtSet {
        TaughtSet::from_song(&song("4/4", bars)).unwrap()
    }

    #[test]
    fn untaught_rest_values_fail() {
        let t = taught_from(r#"[{"RH":"C4:2 r:2"}]"#);
        assert_eq!(t.rest_durations, BTreeSet::from(["2".to_string()]));
        let s = song("4/4", r#"[{"RH":"C4:2 r:2"},{"RH":"C4:2 r:4 r:4"}]"#);
        let e = check(&s, &t, &spec("RH", "[]"));
        assert_eq!(
            e,
            vec!["RH: rest durations not taught: 4 (bar 2)".to_string()]
        );
    }

    #[test]
    fn broken_bars_are_errors_not_empty_bars() {
        let s = song("4/4", r#"[{"RH":"C4:4 Q9:4 C4:2"}]"#);
        let t = taught_from(r#"[{"RH":"C4:1"}]"#);
        let e = check(&s, &t, &spec("RH", "[]"));
        assert_eq!(e.len(), 1, "{e:?}");
        assert!(e[0].starts_with("bar 1 RH:"), "{e:?}");
        assert!(TaughtSet::from_song(&s).is_err());
    }

    #[test]
    fn taught_set_collects_hands_durations_leaps_and_chords() {
        let t = taught_from(
            r#"[{"RH":"C4:4@1 E4:4@3 G4:2@5","LH":"C3E3G3:1@531"},{"RH":"F#4:8 G4:8 r:4 C4:2"}]"#,
        );
        assert_eq!(t.pitches["RH"], BTreeSet::from([60, 64, 66, 67]));
        assert_eq!(t.pitches["LH"], BTreeSet::from([48, 52, 55]));
        assert_eq!(
            t.durations,
            BTreeSet::from(["1", "2", "4", "8"].map(String::from))
        );
        assert_eq!(t.accidentals, BTreeSet::from([6]));
        assert_eq!(t.max_interval, 7); // G4 -> C4
        assert_eq!((t.polyphony["RH"], t.polyphony["LH"]), (1, 3));
        assert!(t.rests && t.hands_together);
        assert_eq!(t.to_json()["accidentals"], json!(["F#"]));
    }

    #[test]
    fn merge_is_a_union() {
        let mut a = taught_from(r#"[{"RH":"C4:1"}]"#);
        a.merge(&taught_from(r#"[{"RH":"D4:2. E4:4","LH":"C3:1"}]"#));
        assert_eq!(a.pitches["RH"].len(), 3);
        assert!(a.durations.contains("2.") && a.pitches.contains_key("LH"));
        assert_eq!(a.max_interval, 2);
    }

    #[test]
    fn song_inside_taught_set_passes() {
        let t = taught_from(r#"[{"RH":"C4:4 D4:4 E4:4 F4:4"},{"RH":"G4:2 E4:2"}]"#);
        let s = song("4/4", r#"[{"RH":"E4:4 D4:4 C4:2"}]"#);
        assert_eq!(check(&s, &t, &spec("RH", "[]")), Vec::<String>::new());
    }

    #[test]
    fn new_pitch_duration_accidental_and_leap_fail() {
        let t = taught_from(r#"[{"RH":"C4:4 D4:4 E4:2"}]"#);
        let s = song("4/4", r#"[{"RH":"C4:8 A4:8 F#4:4 C4:2"}]"#);
        let e = check(&s, &t, &spec("RH", "[]")).join("\n");
        assert!(e.contains("RH: pitches not taught: F#4 A4"), "{e}");
        assert!(e.contains("RH: durations not taught: 8"), "{e}");
        assert!(e.contains("accidentals not taught: F#"), "{e}");
        assert!(e.contains("leap of 9 semitones, taught up to 2"), "{e}");
    }

    #[test]
    fn hands_meter_tempo_and_length_follow_the_spec() {
        let t = taught_from(r#"[{"RH":"C4:1","LH":"C3:1"}]"#);
        let s = song("4/4", r#"[{"LH":"C3:1"}]"#);
        let e = check(&s, &t, &spec("RH", "[]")).join("\n");
        assert!(
            e.contains("node wants RH notes") && e.contains("RH-only, song has LH"),
            "{e}"
        );
        let mut sp = spec("LH", "[]");
        sp.bpm = [100.0, 120.0];
        sp.bars = [4, 8];
        sp.time = "3/4".into();
        let e = check(&s, &t, &sp).join("\n");
        assert!(
            e.contains("bpm 90 outside")
                && e.contains("1 bars outside [4, 8]")
                && e.contains("node wants 3/4"),
            "{e}"
        );
    }

    #[test]
    fn chords_need_teaching_sane_span_and_fingering() {
        let t = taught_from(r#"[{"LH":"C3E3G3:1@531"}]"#);
        let s = song("4/4", r#"[{"LH":"C3G3:2@15 C3D4:2"}]"#);
        let e = check(&s, &t, &spec("LH", "[]")).join("\n");
        assert!(e.contains("chord fingering out of order"), "{e}");
        assert!(e.contains("chord spans 14 semitones"), "{e}");
        let rh = song("4/4", r#"[{"RH":"C4E4:1"}]"#);
        let t2 = taught_from(r#"[{"RH":"C4:2 E4:2"}]"#);
        assert!(check(&rh, &t2, &spec("RH", "[]"))
            .iter()
            .any(|e| e.contains("2 notes at once, taught up to 1")));
    }

    #[test]
    fn rests_and_hands_together_must_be_taught() {
        let t = taught_from(r#"[{"RH":"C4:1"},{"LH":"C3:1"}]"#);
        let s = song("4/4", r#"[{"RH":"C4:2 r:2","LH":"C3:1"}]"#);
        let e = check(&s, &t, &spec("both", "[]")).join("\n");
        assert!(
            e.contains("rests not taught") && e.contains("hands together not taught"),
            "{e}"
        );
    }

    #[test]
    fn required_patterns() {
        let t = taught_from(
            r#"[{"RH":"C4:8 E4:8 D4:8 F4:8 G4:4 F#4:4","LH":"C3E3G3:1"},{"RH":"C4:2 r:2"},{"RH":"C4:1"}]"#,
        );
        let eighths = song(
            "4/4",
            r#"[{"RH":"C4:8 D4:8 E4:8 D4:8 C4:2"},{"RH":"C4:1"}]"#,
        );
        let need = |req: &str| check(&eighths, &t, &spec("RH", req));
        assert!(need(r#"[{"rhythm":"8","min_bar_share":0.5}]"#).is_empty());
        assert!(need(r#"[{"rhythm":"8","min_bar_share":0.75}]"#)[0]
            .contains("missing required pattern"));
        assert!(need(r#"[{"interval_min":2}]"#).is_empty());
        assert!(!need(r#"[{"interval_min":3}]"#).is_empty());
        assert!(!need(r#"[{"accidental":"Gb"}]"#).is_empty());
        assert!(need(r#"[{"pitch":"D4","hand":"RH"}]"#).is_empty());
        assert!(!need(r#"[{"pitch":"D4","hand":"LH"}]"#).is_empty());
        assert!(!need(r#"[{"rest":true}]"#).is_empty());
        assert!(!need(r#"[{"chord":true}]"#).is_empty());
        let sharp = song("4/4", r#"[{"RH":"E4:4 G4:4 F#4:2"}]"#);
        assert!(check(
            &sharp,
            &t,
            &spec("RH", r#"[{"accidental":"Gb"},{"interval_min":3}]"#)
        )
        .is_empty());
    }

    #[test]
    fn spec_validation() {
        let mut s = spec(
            "both",
            r#"[{"rhythm":"8","min_bar_share":2},{"accidental":"E"},{},{"interval_min":9}]"#,
        );
        s.bars = [4, 2];
        let e = s.validate().join("\n");
        assert!(
            e.contains("bars [4, 2]")
                && e.contains("min_bar_share 2")
                && e.contains("`E` is not a black key"),
            "{e}"
        );
        assert!(
            e.contains("no requirement") && e.contains("interval_min 9"),
            "{e}"
        );
        assert!(serde_json::from_str::<Pattern>(r#"{"rythm":"8"}"#).is_err());
    }

    #[test]
    fn labels_and_intervals() {
        assert_eq!(dur_label(Dur::new(1, 4)), "4");
        assert_eq!(dur_label(Dur::new(3, 8)), "4.");
        assert_eq!(dur_label(Dur::new(3, 4)), "2.");
        assert_eq!(dur_label(Dur::new(5, 8)), "5/8");
        assert_eq!(accidental_class("Bb"), Some(10));
        assert_eq!(interval_semitones(3), Some(3));
        assert_eq!(interval_semitones(1), None);
    }

    #[test]
    fn check_generated_round_trips_and_fails_closed() {
        let t = taught_from(r#"[{"RH":"C4:4 D4:4 E4:4 F4:4"}]"#);
        let node = serde_json::to_string(&PracticeNode {
            taught: t.clone(),
            spec: spec("RH", r#"[{"rhythm":"4"}]"#),
        })
        .unwrap();
        let back: PracticeNode = serde_json::from_str(&node).unwrap();
        assert_eq!(back.taught, t);
        let mut ok: Value = json!({"id":"g","title":"G","composer":"m","arranger":"m","source":"x",
            "license":"CC0-1.0","composition_license":"CC0-1.0","bpm":90,"time":"4/4","key":"C",
            "bars":[{"RH":"C4:4 D4:4 E4:4 D4:4"},{"RH":"E4:4 F4:4 E4:4 D4:4"}]});
        ok["source"] = json!("generated");
        ok["generator"] = json!({"method": "melody-model"});
        assert_eq!(
            check_generated(&ok.to_string(), &node),
            Vec::<String>::new()
        );
        let mut wide = ok.clone();
        wide["bars"][0]["RH"] = json!("C4:4 D4:4 E4:4 G4:4");
        assert!(
            check_generated(&wide.to_string(), &node)
                .iter()
                .any(|e| e.contains("G4")),
            "untaught pitch must fail"
        );
        let mut course = ok.clone();
        course["source"] = json!("own");
        assert!(!check_generated(&course.to_string(), &node).is_empty());
        assert!(!check_generated("{", &node).is_empty());
        assert!(!check_generated(&ok.to_string(), "{}").is_empty());
    }
}
