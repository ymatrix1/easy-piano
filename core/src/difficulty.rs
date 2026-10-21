//! Song difficulty (docs/specs/difficulty.md, D26).
//!
//! `features` measures a song per hand and per bar (graded hands only), `skills`
//! folds those into 8 scores in 0..1, and `Model` maps the scores to a level
//! 1-10 with a cumulative-logit model whose weights are non-negative. Every
//! feature grows with difficulty and every skill is a mean of capped features,
//! so more of any difficulty never lowers the level.
//!
//! `node_fit` is the earliest journey node whose taught set the song fits, by
//! the rubric's own `taught_violations`.

use crate::notation::{parse_bar, Dur, Event};
use crate::pitch::parse_pitch;
use crate::rubric::{dur_label, taught_violations, TaughtSet, GRADED};
use crate::song::Song;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};

/// Skill names, in the order of `Skills` arrays and model weights.
pub const SKILLS: [&str; 8] = ["reading", "hand_position", "intervals", "rhythm", "key", "coordination", "texture", "speed"];
pub type Skills = [f64; 8];
/// Widest span one hand covers without moving: five white keys, C to G.
pub const HAND_WINDOW: u8 = 7;
const EPS: f64 = 1e-9;

/// One note or chord of a graded hand.
#[derive(Debug, Clone)]
struct Hit {
    bar: usize,
    /// Onset from the start of the song, in whole notes.
    at: f64,
    pitches: Vec<u8>,
    dur: Dur,
}

#[derive(Debug, Default)]
struct Hand {
    hits: Vec<Hit>,
    rests: usize,
    ties: usize,
}

/// Measurements a level is built from. `*_per_bar` counts are divided by the
/// bar count (never by the note count), so adding notes never lowers them.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Features {
    pub bars: usize,
    pub hands: usize,
    // Reading.
    /// Widest pitch range of one hand, semitones.
    pub range: u8,
    pub distinct_pitches: usize,
    /// Notes on ledger lines (RH on treble staff, LH on bass staff).
    pub ledger_per_bar: f64,
    /// RH notes below middle C or LH notes above it.
    pub clef_crossings_per_bar: f64,
    // Hand position.
    /// Moves out of a 5-finger window (`HAND_WINDOW`), fewest possible.
    pub shifts_per_bar: f64,
    /// Widest chord, semitones.
    pub max_stretch: u8,
    // Intervals (melodic line: RH top note, LH bottom note).
    /// Thirds (3-4 semitones).
    pub skips_per_bar: f64,
    /// Fourths and wider (5+ semitones).
    pub leaps_per_bar: f64,
    pub max_leap: u8,
    // Rhythm.
    /// Shortest note, in whole notes (0.25 = quarter). 1 when there are no notes.
    pub fastest: f64,
    pub distinct_durations: usize,
    pub dotted_per_bar: f64,
    /// Notes that start off the beat and sound across the next beat.
    pub syncopations_per_bar: f64,
    pub ties_per_bar: f64,
    pub rests_per_bar: f64,
    /// Notes whose length is not a power-of-two fraction (triplets etc.).
    pub tuplets_per_bar: f64,
    // Key.
    /// Sharps or flats in the key signature.
    pub key_signature: u8,
    /// `key` is not a key name we know; it is read as C major.
    pub unknown_key: bool,
    /// Notes outside the key's scale (minor keys allow the raised 7th).
    pub out_of_key_per_bar: f64,
    pub black_keys_per_bar: f64,
    // Coordination (zero with one hand).
    /// Onsets where both hands strike.
    pub together_per_bar: f64,
    /// Moments where either hand starts a note (union of both hands' onsets).
    /// Unlike "LH onsets without RH", this cannot drop when a note is added.
    pub onsets_per_bar: f64,
    pub lh_notes_per_bar: f64,
    pub lh_distinct_durations: usize,
    // Texture.
    pub max_notes_at_once: usize,
    pub chords_per_bar: f64,
    /// Hands that play chords.
    pub chord_hands: usize,
    // Speed and load.
    pub notes_per_second: f64,
    /// Busiest bar.
    pub peak_notes_per_second: f64,
    /// Bars that differ in their graded hands (repeats compressed).
    pub unique_bars: usize,
}

fn cap(x: f64, max: f64) -> f64 {
    (x / max).clamp(0.0, 1.0)
}

/// Weighted mean of (weight, value) pairs.
fn mean(xs: &[(f64, f64)]) -> f64 {
    xs.iter().map(|(w, x)| w * x).sum::<f64>() / xs.iter().map(|(w, _)| w).sum::<f64>()
}

fn line_note(hand: &str, pitches: &[u8]) -> u8 {
    let it = pitches.iter().copied();
    if hand == "LH" { it.min().unwrap_or(0) } else { it.max().unwrap_or(0) }
}

fn is_black(p: u8) -> bool {
    [1, 3, 6, 8, 10].contains(&(p % 12))
}

fn on_ledger(hand: &str, p: u8) -> bool {
    // Treble staff E4 (64)..F5 (77): C#4 and below, A5 and above need ledgers.
    // Bass staff G2 (43)..A3 (57): E2 and below, C4 and above.
    if hand == "LH" { p <= 40 || p >= 60 } else { p <= 61 || p >= 81 }
}

/// Sharps/flats of a key and the pitch classes of its scale (minor keys add
/// the raised 7th). `None` for a key name we do not know.
pub fn key_info(key: &str) -> Option<(u8, BTreeSet<u8>)> {
    const MAJOR: [(&str, u8); 15] = [
        ("C", 0), ("G", 1), ("D", 2), ("A", 3), ("E", 4), ("B", 5), ("F#", 6), ("C#", 7),
        ("F", 1), ("Bb", 2), ("Eb", 3), ("Ab", 4), ("Db", 5), ("Gb", 6), ("Cb", 7),
    ];
    const MINOR: [(&str, u8); 15] = [
        ("A", 0), ("E", 1), ("B", 2), ("F#", 3), ("C#", 4), ("G#", 5), ("D#", 6), ("A#", 7),
        ("D", 1), ("G", 2), ("C", 3), ("F", 4), ("Bb", 5), ("Eb", 6), ("Ab", 7),
    ];
    let (name, table, steps): (&str, &[(&str, u8)], &[u8]) = match key.strip_suffix('m') {
        Some(t) => (t, &MINOR, &[0, 2, 3, 5, 7, 8, 10, 11]),
        None => (key, &MAJOR, &[0, 2, 4, 5, 7, 9, 11]),
    };
    let size = table.iter().find(|(n, _)| *n == name)?.1;
    // `Cb4` parses one octave off, but only the pitch class matters here.
    let tonic = parse_pitch(&format!("{name}4")).ok()? % 12;
    Some((size, steps.iter().map(|s| (tonic + s) % 12).collect()))
}

fn hands(song: &Song) -> BTreeMap<&'static str, Hand> {
    let bar_len = song.time_signature().map_or(1.0, |(n, d)| n as f64 / d as f64);
    let mut out: BTreeMap<&'static str, Hand> = BTreeMap::new();
    for (i, bar) in song.bars.iter().enumerate() {
        for hand in GRADED {
            let Some(events) = bar.get(hand).and_then(|t| parse_bar(t).ok()) else { continue };
            let h = out.entry(hand).or_default();
            let mut t = Dur::ZERO;
            for e in events {
                match &e {
                    Event::Note { pitches, dur, .. } => h.hits.push(Hit { bar: i, at: i as f64 * bar_len + t.as_f64(), pitches: pitches.clone(), dur: *dur }),
                    Event::Rest { .. } => h.rests += 1,
                    Event::Directive { name, .. } if name == "tie" => h.ties += 1,
                    Event::Directive { .. } => {}
                }
                t = t.add(e.dur());
            }
        }
    }
    out.retain(|_, h| !h.hits.is_empty());
    out
}

/// Fewest moves out of a `HAND_WINDOW` window. Greedy is optimal here, and
/// adding a note can never lower it.
fn shifts(hits: &[Hit]) -> usize {
    let mut n = 0;
    let mut win: Option<(u8, u8)> = None;
    for h in hits {
        let (lo, hi) = (*h.pitches.iter().min().unwrap_or(&0), *h.pitches.iter().max().unwrap_or(&0));
        win = Some(match win {
            None => (lo, hi),
            Some((a, b)) if b.max(hi) - a.min(lo) <= HAND_WINDOW => (a.min(lo), b.max(hi)),
            Some(_) => {
                n += 1;
                (lo, hi)
            }
        });
    }
    n
}

pub fn features(song: &Song) -> Features {
    let hs = hands(song);
    let (num, unit) = song.time_signature().unwrap_or((4, 4));
    let beat = 1.0 / unit as f64;
    let bars = song.bars.len().max(1);
    let per_bar = |n: usize| n as f64 / bars as f64;
    let known = key_info(&song.key);
    let unknown_key = known.is_none();
    let (key_signature, scale) = known.unwrap_or_else(|| key_info("C").expect("C is a key"));
    let mut f = Features { bars: song.bars.len(), hands: hs.len(), key_signature, unknown_key, fastest: 1.0, ..Default::default() };
    let (mut ledger, mut cross, mut shift, mut skips, mut leaps) = (0, 0, 0, 0, 0);
    let (mut dotted, mut sync, mut ties, mut rests, mut tuplets) = (0, 0, 0, 0, 0);
    let (mut out_key, mut black, mut chords) = (0, 0, 0);
    let mut pitches: BTreeSet<u8> = BTreeSet::new();
    let mut durs = BTreeSet::new();
    for (&hand, h) in &hs {
        let all: Vec<u8> = h.hits.iter().flat_map(|x| x.pitches.iter().copied()).collect();
        f.range = f.range.max(all.iter().max().unwrap_or(&0) - all.iter().min().unwrap_or(&0));
        pitches.extend(&all);
        ledger += all.iter().filter(|&&p| on_ledger(hand, p)).count();
        cross += all.iter().filter(|&&p| if hand == "LH" { p > 60 } else { p < 60 }).count();
        out_key += all.iter().filter(|&&p| !scale.contains(&(p % 12))).count();
        black += all.iter().filter(|&&p| is_black(p)).count();
        shift += shifts(&h.hits);
        for w in h.hits.windows(2) {
            let d = line_note(hand, &w[0].pitches).abs_diff(line_note(hand, &w[1].pitches));
            f.max_leap = f.max_leap.max(d);
            skips += usize::from((3..=4).contains(&d));
            leaps += usize::from(d >= 5);
        }
        for x in &h.hits {
            f.fastest = f.fastest.min(x.dur.as_f64());
            durs.insert(dur_label(x.dur));
            dotted += usize::from(dur_label(x.dur).ends_with('.'));
            tuplets += usize::from(!x.dur.den.is_power_of_two());
            let pos = x.at % beat;
            sync += usize::from(pos > EPS && beat - pos > EPS && pos + x.dur.as_f64() > beat + EPS);
            let span = x.pitches.iter().max().unwrap_or(&0) - x.pitches.iter().min().unwrap_or(&0);
            f.max_stretch = f.max_stretch.max(span);
            f.max_notes_at_once = f.max_notes_at_once.max(x.pitches.len());
            chords += usize::from(x.pitches.len() > 1);
        }
        f.chord_hands += usize::from(h.hits.iter().any(|x| x.pitches.len() > 1));
        ties += h.ties;
        rests += h.rests;
    }
    if let (Some(r), Some(l)) = (hs.get("RH"), hs.get("LH")) {
        let together = |x: &Hit| r.hits.iter().any(|y| (x.at - y.at).abs() < EPS);
        let n = l.hits.iter().filter(|x| together(x)).count();
        f.together_per_bar = per_bar(n);
        let mut at: Vec<f64> = r.hits.iter().chain(&l.hits).map(|x| x.at).collect();
        at.sort_by(f64::total_cmp);
        at.dedup_by(|a, b| (*a - *b).abs() < EPS);
        f.onsets_per_bar = per_bar(at.len());
        f.lh_notes_per_bar = per_bar(l.hits.len());
        f.lh_distinct_durations = l.hits.iter().map(|x| dur_label(x.dur)).collect::<BTreeSet<_>>().len();
    }
    f.distinct_pitches = pitches.len();
    f.distinct_durations = durs.len();
    (f.ledger_per_bar, f.clef_crossings_per_bar, f.shifts_per_bar) = (per_bar(ledger), per_bar(cross), per_bar(shift));
    (f.skips_per_bar, f.leaps_per_bar) = (per_bar(skips), per_bar(leaps));
    (f.dotted_per_bar, f.syncopations_per_bar, f.ties_per_bar) = (per_bar(dotted), per_bar(sync), per_bar(ties));
    (f.rests_per_bar, f.tuplets_per_bar) = (per_bar(rests), per_bar(tuplets));
    (f.out_of_key_per_bar, f.black_keys_per_bar, f.chords_per_bar) = (per_bar(out_key), per_bar(black), per_bar(chords));
    // `bpm` counts the meter's beat unit (the denominator note), as the session
    // engine plays it: 6/8 at 120 is 120 eighths a minute, 2/2 at 60 is 60 halves.
    let bar_secs = num as f64 * 60.0 / song.bpm.max(1.0);
    let onsets: usize = hs.values().map(|h| h.hits.len()).sum();
    f.notes_per_second = onsets as f64 / (bars as f64 * bar_secs);
    let mut by_bar = vec![0usize; bars];
    hs.values().flat_map(|h| &h.hits).for_each(|x| by_bar[x.bar.min(bars - 1)] += 1);
    f.peak_notes_per_second = by_bar.iter().max().copied().unwrap_or(0) as f64 / bar_secs;
    let graded = |b: &BTreeMap<String, String>| GRADED.map(|h| b.get(h).cloned());
    f.unique_bars = song.bars.iter().map(graded).collect::<BTreeSet<_>>().len();
    f
}

/// Skill scores in 0..1, each a weighted mean of capped features (weights and
/// caps in the spec). Component weights say what dominates a skill: the
/// fastest note for rhythm, range for reading.
pub fn skills(f: &Features) -> Skills {
    // Shortest note: quarter or longer 0, eighth 0.5, sixteenth 1.
    let fastest = ((1.0 / f.fastest).log2() - 2.0) / 2.0;
    [
        mean(&[(2.0, cap(f.range as f64, 24.0)), (1.0, cap(f.distinct_pitches as f64, 20.0)), (0.5, cap(f.ledger_per_bar, 4.0)), (1.0, cap(f.clef_crossings_per_bar, 1.0))]),
        mean(&[(2.0, cap(f.shifts_per_bar, 1.0)), (1.0, cap(f.max_stretch as f64, 12.0))]),
        mean(&[(1.0, cap(f.skips_per_bar, 4.0)), (1.0, cap(f.leaps_per_bar, 2.0)), (1.0, cap(f.max_leap as f64, 12.0))]),
        mean(&[
            (3.0, fastest.clamp(0.0, 1.0)),
            (1.0, cap(f.distinct_durations.saturating_sub(1) as f64, 5.0)),
            (1.0, cap(f.dotted_per_bar, 1.0)),
            (1.0, cap(f.syncopations_per_bar, 1.0)),
            (0.5, cap(f.ties_per_bar, 1.0)),
            (0.5, cap(f.rests_per_bar, 1.0)),
            (1.0, cap(f.tuplets_per_bar, 1.0)),
        ]),
        mean(&[(1.0, cap(f.key_signature as f64, 4.0)), (2.0, cap(f.out_of_key_per_bar, 1.0)), (1.0, cap(f.black_keys_per_bar, 2.0))]),
        mean(&[
            (1.0, cap(f.hands.saturating_sub(1) as f64, 1.0)),
            (1.0, cap(f.together_per_bar, 2.0)),
            (1.0, cap(f.onsets_per_bar, 8.0)),
            (1.0, cap(f.lh_notes_per_bar, 4.0)),
            (1.0, cap(f.lh_distinct_durations as f64, 3.0)),
        ]),
        mean(&[(1.0, cap(f.max_notes_at_once.saturating_sub(1) as f64, 3.0)), (1.0, cap(f.chords_per_bar, 2.0)), (1.0, cap(f.chord_hands as f64, 2.0))]),
        // `unique_bars` is reported but not scored: adding a note can make two bars
        // equal and lower it, which would break monotonicity.
        mean(&[(2.0, cap(f.notes_per_second, 4.0)), (1.0, cap(f.peak_notes_per_second, 6.0))]),
    ]
}

/// Cumulative-logit ordinal model: P(level > j) = sigmoid(z - thresholds[j-1]),
/// z = weights · skills. Loaded from `core/data/difficulty-weights.json`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Model {
    /// One per skill, in `SKILLS` order, all >= 0.
    pub weights: Vec<f64>,
    /// 9 ascending cut points between levels 1..10.
    pub thresholds: Vec<f64>,
    /// Expected level at the first and the last course node (lint's yardstick).
    pub course_levels: [f64; 2],
}

pub const WEIGHTS_JSON: &str = include_str!("../data/difficulty-weights.json");

impl Model {
    pub fn from_json(text: &str) -> Result<Model, String> {
        let m: Model = serde_json::from_str(text).map_err(|e| format!("json: {e}"))?;
        if m.weights.len() != SKILLS.len() || m.weights.iter().any(|w| !(*w >= 0.0)) {
            return Err(format!("need {} non-negative weights", SKILLS.len()));
        }
        if m.thresholds.len() != 9 || m.thresholds.windows(2).any(|w| w[0] >= w[1]) {
            return Err("need 9 strictly ascending thresholds".into());
        }
        Ok(m)
    }

    /// The calibrated weights shipped with core.
    pub fn builtin() -> Model {
        Model::from_json(WEIGHTS_JSON).expect("core/data/difficulty-weights.json is valid")
    }

    pub fn z(&self, s: &Skills) -> f64 {
        self.weights.iter().zip(s).map(|(w, x)| w * x).sum()
    }

    /// Expected level, 1.0..10.0, non-decreasing in z.
    pub fn level_score(&self, z: f64) -> f64 {
        1.0 + self.thresholds.iter().map(|t| 1.0 / (1.0 + (t - z).exp())).sum::<f64>()
    }

    pub fn level(&self, s: &Skills) -> u8 {
        self.level_score(self.z(s)).round().clamp(1.0, 10.0) as u8
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct BarScore {
    /// 1-based, as lint and authors count bars.
    pub bar: usize,
    pub level_score: f64,
}

#[derive(Debug, Clone, Serialize)]
pub struct Report {
    pub level: u8,
    pub level_score: f64,
    pub skills: BTreeMap<&'static str, f64>,
    pub features: Features,
    /// Up to 3 bars, hardest first, each scored as a one-bar song.
    pub hardest_bars: Vec<BarScore>,
    pub reasons: Vec<String>,
}

fn round3(x: f64) -> f64 {
    (x * 1000.0).round() / 1000.0
}

fn fraction_name(d: f64) -> String {
    match (1.0 / d).round() as u32 {
        1 => "whole".into(),
        2 => "half".into(),
        4 => "quarter".into(),
        8 => "eighth".into(),
        16 => "sixteenth".into(),
        32 => "thirty-second".into(),
        _ => format!("{d:.3} whole note"),
    }
}

/// One plain sentence per skill, from its strongest features.
fn reason(skill: usize, f: &Features) -> String {
    match skill {
        0 => format!("range of {} semitones over {} different pitches", f.range, f.distinct_pitches),
        1 => format!("{:.1} hand-position shifts per bar, widest chord {} semitones", f.shifts_per_bar, f.max_stretch),
        2 => format!("leaps up to {} semitones, {:.1} skips and {:.1} leaps per bar", f.max_leap, f.skips_per_bar, f.leaps_per_bar),
        3 => format!("fastest note a {}, {} note values", fraction_name(f.fastest), f.distinct_durations),
        4 => format!("{} sharps/flats in the key, {:.1} accidentals per bar", f.key_signature, f.out_of_key_per_bar),
        5 => format!("both hands: {:.1} notes together, {:.1} onsets per bar", f.together_per_bar, f.onsets_per_bar),
        6 => format!("up to {} notes at once, {:.1} chords per bar", f.max_notes_at_once, f.chords_per_bar),
        _ => format!("{:.1} notes per second (peak {:.1}), {} different bars", f.notes_per_second, f.peak_notes_per_second, f.unique_bars),
    }
}

/// Level, skills, hardest bars and reasons. `node_fit` and node exceedances need
/// the course walk, which lives in `content-cli`; see `node_fit` and `exceeds`.
pub fn evaluate(song: &Song, model: &Model) -> Report {
    let f = features(song);
    let s = skills(&f);
    let score = model.level_score(model.z(&s));
    let mut bars: Vec<BarScore> = (0..song.bars.len())
        .map(|i| {
            let one = Song { bars: vec![song.bars[i].clone()], critical: vec![], ..song.clone() };
            BarScore { bar: i + 1, level_score: round3(model.level_score(model.z(&skills(&features(&one))))) }
        })
        .collect();
    bars.sort_by(|a, b| b.level_score.total_cmp(&a.level_score).then(a.bar.cmp(&b.bar)));
    bars.truncate(3);
    let mut order: Vec<usize> = (0..SKILLS.len()).collect();
    order.sort_by(|&a, &b| (model.weights[b] * s[b]).total_cmp(&(model.weights[a] * s[a])));
    let unknown = f.unknown_key.then(|| format!("key: unknown key `{}`, read as C major", song.key));
    let reasons = unknown.into_iter().chain(order.iter().filter(|&&k| s[k] >= 0.25 && model.weights[k] > 0.0).take(3).map(|&k| format!("{}: {}", SKILLS[k], reason(k, &f)))).collect();
    Report {
        level: score.round().clamp(1.0, 10.0) as u8,
        level_score: round3(score),
        skills: SKILLS.iter().zip(s).map(|(k, v)| (*k, round3(v))).collect(),
        features: f,
        hardest_bars: bars,
        reasons,
    }
}

/// Earliest node (in learning order) whose taught set the song fits, by
/// `rubric::taught_violations`. Taught sets only grow, so every later node fits too.
pub fn node_fit<'a>(song: &Song, nodes: &'a [(String, TaughtSet)]) -> Option<&'a str> {
    nodes.iter().find(|(_, t)| taught_violations(song, t).is_empty()).map(|(k, _)| k.as_str())
}

/// What a song has beyond a node: the rubric's taught-set violations, then every
/// skill above `envelope` (the most of each skill the node's songs so far show).
pub fn exceeds(song: &Song, taught: &TaughtSet, envelope: Option<&Skills>) -> Vec<String> {
    let mut out = taught_violations(song, taught);
    if let Some(env) = envelope {
        let s = skills(&features(song));
        for (k, name) in SKILLS.iter().enumerate() {
            if s[k] > env[k] + 0.05 {
                out.push(format!("{name} {:.2} above node's {:.2}", s[k], env[k]));
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn song(key: &str, bpm: u32, bars: &str) -> Song {
        Song::from_json(&format!(
            r#"{{"id":"t","title":"T","composer":"Trad.","arranger":"A","source":"original","source_url":null,
            "license":"CC0-1.0","composition_license":"public-domain","bpm":{bpm},"time":"4/4","key":"{key}","bars":{bars}}}"#
        ))
        .unwrap()
    }

    const TWINKLE: &str = r#"[{"RH":"C4:4 C4:4 G4:4 G4:4"},{"RH":"A4:4 A4:4 G4:2"},{"RH":"F4:4 F4:4 E4:4 E4:4"},{"RH":"D4:4 D4:4 C4:2"}]"#;

    fn level(s: &Song) -> f64 {
        let m = Model::builtin();
        m.level_score(m.z(&skills(&features(s))))
    }

    #[test]
    fn builtin_weights_load_and_are_monotonic() {
        let m = Model::builtin();
        assert!(m.weights.iter().all(|w| *w >= 0.0));
        let mut prev = 0.0;
        for i in 0..=80 {
            let l = m.level_score(i as f64 * 0.1);
            assert!(l >= prev - EPS);
            prev = l;
        }
        assert!(Model::from_json(r#"{"weights":[-1,0,0,0,0,0,0,0],"thresholds":[1,2,3,4,5,6,7,8,9],"course_levels":[1,6]}"#).is_err());
        assert!(Model::from_json(r#"{"weights":[1,1,1,1,1,1,1,1],"thresholds":[1,2,3,4,5,6,7,8,8],"course_levels":[1,6]}"#).is_err());
    }

    #[test]
    fn key_signatures() {
        let size = |k| key_info(k).map(|x| x.0);
        for (k, n) in [("C", 0), ("G", 1), ("F", 1), ("Am", 0), ("Dm", 1), ("Eb", 3), ("C#", 7), ("Cb", 7), ("Db", 5), ("Gb", 6), ("G#m", 5), ("Ebm", 6)] {
            assert_eq!(size(k), Some(n), "{k}");
        }
        assert_eq!(size("G#"), None, "G# major is not a written key");
        assert_eq!(size("H"), None);
        assert!(key_info("Am").unwrap().1.contains(&8), "G# allowed in A minor");
        assert!(!key_info("C").unwrap().1.contains(&6));
        assert!(key_info("Cb").unwrap().1.contains(&11), "Cb major has Cb");
    }

    #[test]
    fn unknown_key_reads_as_c_with_a_reason() {
        let s = song("H", 96, TWINKLE);
        assert!(features(&s).unknown_key);
        let r = evaluate(&s, &Model::builtin());
        assert!(r.reasons[0].contains("unknown key `H`"), "{:?}", r.reasons);
        assert_eq!(r.level, evaluate(&song("C", 96, TWINKLE), &Model::builtin()).level);
    }

    fn meter(time: &str, bpm: u32, bars: &str) -> Song {
        let s = song("C", bpm, bars);
        Song { time: time.into(), ..s }
    }

    #[test]
    fn notes_per_second_follow_the_meter_beat_unit() {
        // 3/4 at 60: three quarters, one second each.
        let f = features(&meter("3/4", 60, r#"[{"RH":"C4:4 D4:4 E4:4"}]"#));
        assert!((f.notes_per_second - 1.0).abs() < EPS);
        // 6/8 at 120: six eighths a bar, half a second each.
        let f = features(&meter("6/8", 120, r#"[{"RH":"C4:8 D4:8 E4:8 F4:8 E4:8 D4:8"}]"#));
        assert!((f.notes_per_second - 2.0).abs() < EPS);
        // 2/2 at 60: two halves a bar, one second each.
        let f = features(&meter("2/2", 60, r#"[{"RH":"C4:2 D4:2"}]"#));
        assert!((f.notes_per_second - 1.0).abs() < EPS);
    }

    #[test]
    fn features_of_twinkle() {
        let f = features(&song("C", 96, TWINKLE));
        assert_eq!((f.range, f.distinct_pitches, f.hands, f.max_leap), (9, 6, 1, 7));
        assert_eq!((f.fastest, f.distinct_durations, f.unique_bars), (0.25, 2, 4));
        assert_eq!(f.shifts_per_bar, 0.5, "C-G, then D-A, then C again");
        assert_eq!((f.out_of_key_per_bar, f.black_keys_per_bar, f.key_signature), (0.0, 0.0, 0));
        assert_eq!(f.ledger_per_bar, 0.75, "three C4s on a ledger line");
    }

    #[test]
    fn rhythm_features() {
        let f = features(&song("C", 90, r#"[{"RH":"C4:8 D4:4 E4:8 F4:4. G4:16 G4:16"},{"RH":"r:4 C4:4 {tie} C4:2"}]"#));
        assert_eq!(f.fastest, 1.0 / 16.0);
        assert_eq!(f.syncopations_per_bar, 0.5, "D4 on the and of 1 crosses beat 2");
        assert_eq!((f.dotted_per_bar, f.ties_per_bar, f.rests_per_bar), (0.5, 0.5, 0.5));
        let t = features(&song("C", 90, r#"[{"RH":"C4:1/12 D4:1/12 E4:1/12 F4:2."}]"#));
        assert_eq!(t.tuplets_per_bar, 3.0);
    }

    #[test]
    fn coordination_and_texture() {
        let f = features(&song("C", 90, r#"[{"RH":"E4:4 D4:4 C4:2","LH":"C3E3G3:2 G2:4 G2:4"}]"#));
        assert_eq!((f.hands, f.together_per_bar, f.onsets_per_bar), (2, 2.0, 4.0));
        assert_eq!((f.max_notes_at_once, f.chords_per_bar, f.chord_hands, f.max_stretch), (3, 1.0, 1, 7));
    }

    // Monotonicity: each change adds difficulty and must never lower the level.

    #[test]
    fn an_rh_note_on_an_lh_onset_never_lowers_coordination() {
        // Regression: splitting LH onsets into "together" and "independent" let
        // this extra RH note lower coordination.
        let lh = "C3:4 C3:4 C3:4 C3:4";
        let a = song("C", 96, &format!(r#"[{{"RH":"C4:4 D4:4 E4:2","LH":"{lh}"}}]"#));
        let b = song("C", 96, &format!(r#"[{{"RH":"C4:4 D4:4 E4:4 F4:4","LH":"{lh}"}}]"#));
        let (sa, sb) = (skills(&features(&a)), skills(&features(&b)));
        assert!(sb[5] >= sa[5], "coordination {} < {}", sb[5], sa[5]);
        // The other skills move too (the half note becomes two quarters), so only
        // coordination is compared.
    }

    #[test]
    fn sixteenths_never_lower_the_level() {
        let base = song("C", 96, TWINKLE);
        let fast = song("C", 96, &TWINKLE.replacen("C4:4 C4:4 G4:4", "C4:16 D4:16 E4:16 D4:16 C4:4 G4:4", 1));
        assert!(level(&fast) > level(&base), "{} vs {}", level(&fast), level(&base));
    }

    #[test]
    fn accidentals_never_lower_the_level() {
        let base = song("C", 96, TWINKLE);
        let sharp = song("C", 96, &TWINKLE.replace("F4:4 F4:4", "F#4:4 F#4:4"));
        assert!(level(&sharp) > level(&base));
    }

    #[test]
    fn hands_together_never_lowers_the_level() {
        let base = song("C", 96, TWINKLE);
        let lh = TWINKLE.replace(r#""}"#, r#"","LH":"C3:1"}"#);
        let both = song("C", 96, &lh);
        assert!(level(&both) > level(&base));
        let chords = song("C", 96, &TWINKLE.replace(r#""}"#, r#"","LH":"C3E3G3:1"}"#));
        assert!(level(&chords) > level(&both), "Twinkle with LH chords is harder than Twinkle with LH notes");
    }

    #[test]
    fn faster_tempo_and_more_notes_never_lower_the_level() {
        let slow = song("C", 72, TWINKLE);
        let fast = song("C", 132, TWINKLE);
        assert!(level(&fast) > level(&slow));
        // Random additions: every one keeps the level the same or higher.
        let adds = ["C4:8 C4:8 G4:4 G4:4", "C4:4 C4:4 G4:4 G#4:4", "C4:4 C4:4 G4:4 G5:4", "C4:4 C4:4 G4B4:4 G4:4"];
        let base = level(&slow);
        for a in adds {
            let s = song("C", 72, &TWINKLE.replacen("C4:4 C4:4 G4:4 G4:4", a, 1));
            assert!(level(&s) >= base - EPS, "{a}: {} < {base}", level(&s));
        }
    }

    #[test]
    fn report_has_reasons_and_hardest_bars() {
        let s = song("C", 96, &TWINKLE.replacen("A4:4 A4:4 G4:2", "A4:16 B4:16 C5:16 B4:16 A4:8 G4:8 G4:2", 1));
        let r = evaluate(&s, &Model::builtin());
        assert_eq!(r.hardest_bars[0].bar, 2);
        assert_eq!(r.hardest_bars.len(), 3);
        assert!((1..=10).contains(&r.level));
        assert!(r.reasons.iter().any(|x| x.starts_with("rhythm:") && x.contains("sixteenth")), "{:?}", r.reasons);
    }

    #[test]
    fn node_fit_is_the_earliest_node_by_the_rubric() {
        let five = TaughtSet::from_song(&song("C", 90, r#"[{"RH":"C4:4 D4:4 E4:4 F4:4"},{"RH":"G4:1"}]"#)).unwrap();
        let mut six = five.clone();
        six.merge(&TaughtSet::from_song(&song("C", 90, r#"[{"RH":"A4:4 G4:4 C4:2"}]"#)).unwrap());
        let nodes = vec![("c/five".to_string(), five.clone()), ("c/six".to_string(), six)];
        let tw = song("C", 96, TWINKLE);
        assert_eq!(node_fit(&tw, &nodes), Some("c/six"));
        assert!(exceeds(&tw, &five, None).iter().any(|e| e.contains("A4")));
        let sharp = song("C", 96, &TWINKLE.replace("F4:4 F4:4", "F#4:4 F#4:4"));
        assert_eq!(node_fit(&sharp, &nodes), None);
        let env = [0.0; 8];
        assert!(exceeds(&tw, &nodes[1].1, Some(&env)).iter().any(|e| e.starts_with("reading")));
    }
}
