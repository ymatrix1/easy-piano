//! Turns raw transcription output into playable arrangements per level (D11).
//!
//! Pipeline: `clean` (drop overtone ghosts and blips) → `melody` (skyline) →
//! `arrange` (quantize, transpose, fit range, add left hand per level).
//! Deterministic and pure; see docs/research/song-import.md.

/// A transcribed note in seconds, as produced by Basic Pitch.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct RawNote {
    pub pitch: u8,
    pub start: f64,
    pub dur: f64,
    pub amp: f32,
}

impl RawNote {
    fn end(&self) -> f64 {
        self.start + self.dur
    }
}

/// A note in an arrangement, positioned in beats.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ArrangedNote {
    pub pitch: u8,
    pub beat: f64,
    pub beats: f64,
    pub left_hand: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Level {
    /// Right-hand melody in C, five-finger range C4–G4, whole beats.
    Beginner,
    /// Melody on half-beat grid plus a left-hand root per bar.
    Intermediate,
    /// All cleaned notes on a quarter-beat grid, hands split at middle C.
    Advanced,
}

/// Tunables for [`clean`].
#[derive(Debug, Clone, Copy)]
pub struct CleanConfig {
    /// Notes shorter than this are dropped (seconds).
    pub min_dur: f64,
    /// Onset slack when checking whether a lower note is sounding (seconds).
    pub onset_slack: f64,
    /// A candidate overtone must be quieter than its fundamental by this factor.
    pub amp_ratio: f32,
}

impl Default for CleanConfig {
    fn default() -> Self {
        Self { min_dur: 0.06, onset_slack: 0.06, amp_ratio: 0.8 }
    }
}

/// Semitone distances of the strongest overtones: octave, twelfth, double octave.
const OVERTONES: [u8; 3] = [12, 19, 24];

/// Drops blips and notes that look like overtones of a louder lower note
/// sounding at the same time.
pub fn clean(notes: &[RawNote], cfg: &CleanConfig) -> Vec<RawNote> {
    let mut out: Vec<RawNote> = notes
        .iter()
        .copied()
        .filter(|n| n.dur >= cfg.min_dur)
        .filter(|n| {
            !notes.iter().any(|f| {
                n.pitch > f.pitch
                    && OVERTONES.contains(&(n.pitch - f.pitch))
                    && n.amp < f.amp * cfg.amp_ratio
                    && n.start >= f.start - cfg.onset_slack
                    && n.start <= f.end()
            })
        })
        .collect();
    out.sort_by(|a, b| a.start.total_cmp(&b.start).then(a.pitch.cmp(&b.pitch)));
    out
}

/// Skyline melody: drops notes that start while a higher note is already
/// sounding (accompaniment under a held melody note), then keeps the highest
/// note of each onset cluster within `slack` seconds.
pub fn melody(notes: &[RawNote], slack: f64) -> Vec<RawNote> {
    let mut sorted: Vec<RawNote> = notes
        .iter()
        .copied()
        .filter(|n| {
            !notes.iter().any(|m| {
                m.pitch > n.pitch && m.start < n.start - slack && m.end() > n.start + slack
            })
        })
        .collect();
    sorted.sort_by(|a, b| a.start.total_cmp(&b.start));
    let mut out: Vec<RawNote> = Vec::new();
    for n in sorted {
        match out.last_mut() {
            Some(last) if n.start - last.start <= slack => {
                if n.pitch > last.pitch {
                    *last = n;
                }
            }
            _ => out.push(n),
        }
    }
    out
}

/// Note-level precision, recall and F1 against `truth` (pitch, start seconds):
/// a hit has the same pitch and an onset within `tol` seconds.
pub fn note_f1(found: &[RawNote], truth: &[(u8, f64)], tol: f64) -> (f64, f64, f64) {
    let mut used = vec![false; found.len()];
    let mut hits = 0usize;
    for &(p, t) in truth {
        if let Some(i) = (0..found.len())
            .find(|&i| !used[i] && found[i].pitch == p && (found[i].start - t).abs() <= tol)
        {
            used[i] = true;
            hits += 1;
        }
    }
    let p = if found.is_empty() { 0.0 } else { hits as f64 / found.len() as f64 };
    let r = if truth.is_empty() { 0.0 } else { hits as f64 / truth.len() as f64 };
    let f1 = if p + r == 0.0 { 0.0 } else { 2.0 * p * r / (p + r) };
    (p, r, f1)
}

fn snap(x: f64, grid: f64) -> f64 {
    (x / grid).round() * grid
}

const C_MAJOR: [u8; 7] = [0, 2, 4, 5, 7, 9, 11];

/// Semitone shift (−6..=5) that puts the most notes in C major, smallest shift on ties.
pub fn shift_to_c(pitches: &[u8]) -> i32 {
    (-6..=5)
        .min_by_key(|&s: &i32| {
            let outside = pitches
                .iter()
                .filter(|&&p| !C_MAJOR.contains(&(((p as i32 + s).rem_euclid(12)) as u8)))
                .count();
            (outside, s.abs())
        })
        .unwrap_or(0)
}

/// Nearest C-major pitch (ties go down).
fn snap_to_c_major(pitch: i32) -> i32 {
    (0..=6)
        .flat_map(|d| [pitch - d, pitch + d])
        .find(|p| C_MAJOR.contains(&(p.rem_euclid(12) as u8)))
        .unwrap_or(pitch)
}

/// Moves `pitch` by octaves into `lo..=hi` when possible.
fn fold(pitch: i32, lo: i32, hi: i32) -> i32 {
    let mut p = pitch;
    while p < lo {
        p += 12;
    }
    while p > hi && p - 12 >= lo {
        p -= 12;
    }
    p.clamp(lo, hi)
}

/// Builds an arrangement for `level` from raw transcription at tempo `bpm`.
pub fn arrange(raw: &[RawNote], bpm: f64, level: Level) -> Vec<ArrangedNote> {
    let beat = |s: f64| s * bpm / 60.0;
    let cleaned = clean(raw, &CleanConfig::default());
    let tune = melody(&cleaned, 0.06);
    match level {
        Level::Beginner => {
            let shift = shift_to_c(&tune.iter().map(|n| n.pitch).collect::<Vec<_>>());
            // Pick the octave placement that keeps most notes inside C4–G4 unfolded.
            let best_oct = (-2..=2)
                .max_by_key(|o| {
                    tune.iter()
                        .filter(|n| (60..=67).contains(&(n.pitch as i32 + shift + 12 * o)))
                        .count()
                })
                .unwrap_or(0);
            let mut out: Vec<ArrangedNote> = Vec::new();
            for n in &tune {
                let b = snap(beat(n.start), 1.0);
                if out.last().is_some_and(|l| l.beat == b) {
                    continue;
                }
                let p = fold(snap_to_c_major(n.pitch as i32 + shift + 12 * best_oct), 60, 67);
                out.push(ArrangedNote { pitch: p as u8, beat: b, beats: 1.0, left_hand: false });
            }
            fill_durations(&mut out, &[1.0, 2.0, 4.0]);
            out
        }
        Level::Intermediate => {
            let mut out: Vec<ArrangedNote> = Vec::new();
            for n in &tune {
                let b = snap(beat(n.start), 0.5);
                if out.last().is_some_and(|l| l.beat == b) {
                    continue;
                }
                out.push(ArrangedNote { pitch: n.pitch, beat: b, beats: 0.5, left_hand: false });
            }
            fill_durations(&mut out, &[0.5, 1.0, 1.5, 2.0, 3.0, 4.0]);
            let bars = out.last().map_or(0, |l| (l.beat / 4.0).floor() as usize + 1);
            for bar in 0..bars {
                let (b0, b1) = (bar as f64 * 4.0, bar as f64 * 4.0 + 4.0);
                // Lowest cleaned note sounding in the bar, else the bar's lowest melody note.
                let root = cleaned
                    .iter()
                    .filter(|n| n.pitch < 60 && beat(n.start) < b1 && beat(n.end()) > b0)
                    .map(|n| n.pitch)
                    .min()
                    .or_else(|| {
                        out.iter()
                            .filter(|n| !n.left_hand && n.beat >= b0 && n.beat < b1)
                            .map(|n| n.pitch)
                            .min()
                    });
                if let Some(r) = root {
                    let p = fold(r as i32, 48, 59) as u8;
                    out.push(ArrangedNote { pitch: p, beat: b0, beats: 4.0, left_hand: true });
                }
            }
            out.sort_by(|a, b| a.beat.total_cmp(&b.beat).then(a.left_hand.cmp(&b.left_hand)));
            out
        }
        Level::Advanced => {
            let mut out: Vec<ArrangedNote> = cleaned
                .iter()
                .map(|n| ArrangedNote {
                    pitch: n.pitch,
                    beat: snap(beat(n.start), 0.25),
                    beats: snap(beat(n.dur), 0.25).max(0.25),
                    left_hand: n.pitch < 60,
                })
                .collect();
            out.sort_by(|a, b| a.beat.total_cmp(&b.beat).then(a.pitch.cmp(&b.pitch)));
            out.dedup_by(|a, b| a.beat == b.beat && a.pitch == b.pitch);
            out
        }
    }
}

/// Sets each note's length to the gap before the next note, rounded down to the
/// largest allowed value (the last note gets the largest value that fits a bar).
fn fill_durations(notes: &mut [ArrangedNote], allowed: &[f64]) {
    for i in 0..notes.len() {
        let gap = notes.get(i + 1).map_or(4.0, |n| n.beat - notes[i].beat);
        notes[i].beats = allowed.iter().copied().filter(|&a| a <= gap + 1e-9).fold(allowed[0], f64::max);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn n(pitch: u8, start: f64, dur: f64, amp: f32) -> RawNote {
        RawNote { pitch, start, dur, amp }
    }

    #[test]
    fn drops_octave_ghost_of_louder_note() {
        let raw = [n(64, 0.0, 0.6, 0.7), n(76, 0.01, 0.1, 0.35)];
        assert_eq!(clean(&raw, &CleanConfig::default()), vec![raw[0]]);
    }

    #[test]
    fn keeps_loud_octave_and_non_harmonic_notes() {
        // Bass C3 under melody C4: the C4 is louder, so it is a real note.
        let raw = [n(48, 0.0, 1.0, 0.45), n(60, 0.0, 0.6, 0.7), n(64, 0.0, 0.6, 0.3)];
        assert_eq!(clean(&raw, &CleanConfig::default()).len(), 3);
    }

    #[test]
    fn drops_ghost_starting_while_fundamental_sounds() {
        let raw = [n(67, 1.8, 0.58, 0.66), n(79, 2.2, 0.16, 0.27)];
        assert_eq!(clean(&raw, &CleanConfig::default()).len(), 1);
    }

    #[test]
    fn drops_blips() {
        let raw = [n(60, 0.0, 0.03, 0.9)];
        assert!(clean(&raw, &CleanConfig::default()).is_empty());
    }

    #[test]
    fn skyline_keeps_highest_of_cluster() {
        let raw = [n(48, 0.0, 1.0, 0.5), n(64, 0.02, 0.5, 0.7), n(65, 0.6, 0.5, 0.7)];
        let m = melody(&raw, 0.06);
        assert_eq!(m.iter().map(|n| n.pitch).collect::<Vec<_>>(), vec![64, 65]);
    }

    #[test]
    fn skyline_ignores_bass_under_held_melody_note() {
        let raw = [n(64, 0.0, 1.0, 0.7), n(36, 0.3, 0.2, 0.5), n(65, 1.0, 0.5, 0.7)];
        let m = melody(&raw, 0.06);
        assert_eq!(m.iter().map(|n| n.pitch).collect::<Vec<_>>(), vec![64, 65]);
    }

    #[test]
    fn snaps_black_keys_to_c_major() {
        assert_eq!(snap_to_c_major(61), 60);
        assert_eq!(snap_to_c_major(66), 65);
        assert_eq!(snap_to_c_major(64), 64);
    }

    #[test]
    fn transposes_g_major_tune_to_c() {
        // G A B C D with F#: G major → shift −7 ≡ +5, limited range gives +5.
        let g_major = [67, 69, 71, 72, 74, 66];
        assert_eq!(shift_to_c(&g_major), 5);
        assert_eq!(shift_to_c(&[60, 62, 64, 65, 67]), 0);
    }

    #[test]
    fn f1_counts_pitch_and_onset_matches() {
        let found = [n(60, 0.0, 0.5, 1.0), n(62, 0.5, 0.5, 1.0), n(72, 0.0, 0.1, 0.3)];
        let truth = [(60, 0.01), (62, 0.52)];
        let (p, r, f1) = note_f1(&found, &truth, 0.05);
        assert!((p - 2.0 / 3.0).abs() < 1e-9 && r == 1.0 && (f1 - 0.8).abs() < 1e-9);
    }
}
