//! Exercise engine (docs/specs/exercise-engine.md): grades a stage while the
//! student plays. Pure and deterministic: the caller feeds note events and
//! audio-clock ticks in microseconds; the engine never reads a clock itself.

use crate::song::{Song, TimedNote};
use std::collections::BTreeSet;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    /// Song time stops at each chord until it is played.
    Wait,
    /// Song time follows the audio clock; late chords are missed.
    PlayAlong,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Input {
    Midi,
    Mic,
    Touch,
}

impl Input {
    /// Half-width of the hit window in microseconds.
    pub fn window_us(self) -> i64 {
        match self {
            Input::Midi => 150_000,
            Input::Mic | Input::Touch => 200_000,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HandFilter {
    Right,
    Left,
    Both,
}

#[derive(Debug, Clone, Copy)]
pub struct Settings {
    pub mode: Mode,
    pub input: Input,
    /// Playback speed factor (0.7 = 70% tempo).
    pub tempo: f64,
    /// Base pass ratio per critical section (spec default 0.7).
    pub pass_ratio: f64,
    /// Failed attempts so far on this stage; lowers the threshold.
    pub failed_attempts: u32,
    pub hand: HandFilter,
}

impl Default for Settings {
    fn default() -> Self {
        Settings { mode: Mode::PlayAlong, input: Input::Midi, tempo: 1.0, pass_ratio: 0.7, failed_attempts: 0, hand: HandFilter::Right }
    }
}

/// Threshold drops 0.1 for every 2 failed attempts, floor 0.4 (spec).
pub fn effective_threshold(pass_ratio: f64, failed_attempts: u32) -> f64 {
    (pass_ratio - 0.1 * (failed_attempts / 2) as f64).max(0.4)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct NoteEvent {
    pub pitch: u8,
    pub on: bool,
    /// Audio-clock time in microseconds since the stage started.
    pub t_us: i64,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ChordState {
    Pending,
    Hit { delta_us: i64 },
    Missed,
}

/// Notes the student must play at one moment (a single note or a chord).
#[derive(Debug, Clone)]
pub struct Target {
    pub beat: f64,
    pub beats: f64,
    pub bar: usize,
    pub pitches: BTreeSet<u8>,
    pub fingers: Vec<Option<u8>>,
    played: BTreeSet<u8>,
    first_us: Option<i64>,
    pub state: ChordState,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Frame {
    /// Where the playhead is, in beats.
    pub playhead_beat: f64,
    /// Index of the next target to play (Wait) or the first pending one (PlayAlong).
    pub cursor: usize,
    pub hits: usize,
    pub misses: usize,
    pub wrong: usize,
    pub done: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct StageResult {
    pub passed: bool,
    pub stars: u8,
    pub hit_ratio: f64,
    pub wrong: usize,
    /// Mean |timing error| over hits, ms (PlayAlong only).
    pub mean_abs_timing_ms: Option<f64>,
    /// Hit ratio per critical section, in song order.
    pub sections: Vec<f64>,
    pub threshold: f64,
    /// Offer slow practice mode (3+ failed attempts and still failing).
    pub suggest_practice: bool,
}

pub struct Session {
    settings: Settings,
    us_per_beat: f64,
    targets: Vec<Target>,
    critical: Vec<[usize; 2]>,
    cursor: usize,
    wrong: usize,
    now_us: i64,
    /// Wait mode: song time is frozen at the current target.
    wait_beat: f64,
}

fn group_targets(notes: &[TimedNote], hand: HandFilter) -> Vec<Target> {
    let mut out: Vec<Target> = Vec::new();
    for n in notes.iter().filter(|n| match hand {
        HandFilter::Right => !n.left_hand,
        HandFilter::Left => n.left_hand,
        HandFilter::Both => true,
    }) {
        match out.last_mut() {
            Some(t) if (t.beat - n.start_beat).abs() < 1e-9 => {
                t.pitches.insert(n.pitch);
                t.fingers.push(n.finger);
                t.beats = t.beats.min(n.beats);
            }
            _ => out.push(Target {
                beat: n.start_beat,
                beats: n.beats,
                bar: n.bar,
                pitches: BTreeSet::from([n.pitch]),
                fingers: vec![n.finger],
                played: BTreeSet::new(),
                first_us: None,
                state: ChordState::Pending,
            }),
        }
    }
    out
}

impl Session {
    pub fn new(song: &Song, settings: Settings) -> Session {
        let targets = group_targets(&song.timeline(), settings.hand);
        let critical = if song.critical.is_empty() { vec![[0, song.bars.len()]] } else { song.critical.clone() };
        let wait_beat = targets.first().map_or(0.0, |t| t.beat);
        Session {
            us_per_beat: 60e6 / (song.bpm * settings.tempo),
            settings,
            targets,
            critical,
            cursor: 0,
            wrong: 0,
            now_us: 0,
            wait_beat,
        }
    }

    pub fn targets(&self) -> &[Target] {
        &self.targets
    }

    fn target_us(&self, t: &Target) -> i64 {
        (t.beat * self.us_per_beat).round() as i64
    }

    /// Feeds one key press or release.
    pub fn on_note(&mut self, e: NoteEvent) {
        if !e.on {
            return; // grading uses onsets only
        }
        self.now_us = self.now_us.max(e.t_us);
        match self.settings.mode {
            Mode::Wait => self.on_note_wait(e),
            Mode::PlayAlong => self.on_note_play_along(e),
        }
    }

    fn on_note_wait(&mut self, e: NoteEvent) {
        let Some(t) = self.targets.get_mut(self.cursor) else { return };
        if t.pitches.contains(&e.pitch) {
            t.played.insert(e.pitch);
            if t.played.len() == t.pitches.len() {
                t.state = ChordState::Hit { delta_us: 0 };
                self.cursor += 1;
                if let Some(next) = self.targets.get(self.cursor) {
                    self.wait_beat = next.beat;
                } else {
                    self.wait_beat = t_end(&self.targets);
                }
            }
        } else {
            self.wrong += 1;
        }
    }

    fn on_note_play_along(&mut self, e: NoteEvent) {
        self.expire(e.t_us);
        let window = self.settings.input.window_us();
        // Nearest pending target containing this pitch, within the window.
        let best = (self.cursor..self.targets.len())
            .filter(|&i| {
                let t = &self.targets[i];
                t.state == ChordState::Pending && t.pitches.contains(&e.pitch) && !t.played.contains(&e.pitch)
            })
            .map(|i| (i, (e.t_us - self.target_us(&self.targets[i])).abs()))
            .filter(|&(_, d)| d <= window)
            .min_by_key(|&(_, d)| d);
        let Some((i, _)) = best else {
            self.wrong += 1;
            return;
        };
        let target_us = self.target_us(&self.targets[i]);
        let t = &mut self.targets[i];
        t.played.insert(e.pitch);
        t.first_us.get_or_insert(e.t_us);
        if t.played.len() == t.pitches.len() {
            t.state = ChordState::Hit { delta_us: t.first_us.unwrap_or(e.t_us) - target_us };
        }
        self.advance_cursor();
    }

    /// Marks pending targets whose window has closed as missed.
    fn expire(&mut self, now_us: i64) {
        let window = self.settings.input.window_us();
        for i in self.cursor..self.targets.len() {
            let due = self.target_us(&self.targets[i]);
            if due + window >= now_us {
                break;
            }
            if self.targets[i].state == ChordState::Pending {
                self.targets[i].state = ChordState::Missed;
            }
        }
        self.advance_cursor();
    }

    fn advance_cursor(&mut self) {
        while self.cursor < self.targets.len() && self.targets[self.cursor].state != ChordState::Pending {
            self.cursor += 1;
        }
    }

    /// Advances the audio clock and returns what the UI should draw.
    pub fn tick(&mut self, t_us: i64) -> Frame {
        self.now_us = self.now_us.max(t_us);
        let playhead_beat = match self.settings.mode {
            Mode::Wait => self.wait_beat,
            Mode::PlayAlong => {
                self.expire(self.now_us);
                self.now_us as f64 / self.us_per_beat
            }
        };
        let hits = self.targets.iter().filter(|t| matches!(t.state, ChordState::Hit { .. })).count();
        let misses = self.targets.iter().filter(|t| t.state == ChordState::Missed).count();
        Frame { playhead_beat, cursor: self.cursor, hits, misses, wrong: self.wrong, done: self.cursor >= self.targets.len() }
    }

    /// Final grade. Call when `Frame::done` (PlayAlong: after the last window closes).
    pub fn result(&self) -> StageResult {
        let threshold = effective_threshold(self.settings.pass_ratio, self.settings.failed_attempts);
        let total = self.targets.len().max(1);
        let hits: Vec<i64> = self
            .targets
            .iter()
            .filter_map(|t| match t.state {
                ChordState::Hit { delta_us } => Some(delta_us),
                _ => None,
            })
            .collect();
        let hit_ratio = hits.len() as f64 / total as f64;
        let sections: Vec<f64> = self
            .critical
            .iter()
            .map(|&[a, b]| {
                let in_sec: Vec<&Target> = self.targets.iter().filter(|t| t.bar >= a && t.bar < b).collect();
                if in_sec.is_empty() {
                    1.0
                } else {
                    in_sec.iter().filter(|t| matches!(t.state, ChordState::Hit { .. })).count() as f64 / in_sec.len() as f64
                }
            })
            .collect();
        let (passed, mean_abs_timing_ms, stars) = match self.settings.mode {
            Mode::Wait => {
                let passed = self.cursor >= self.targets.len();
                let stars = if !passed { 0 } else if self.wrong <= 1 { 3 } else if self.wrong <= 3 { 2 } else { 1 };
                (passed, None, stars)
            }
            Mode::PlayAlong => {
                let passed = sections.iter().all(|&r| r >= threshold);
                let mean = (!hits.is_empty())
                    .then(|| hits.iter().map(|d| d.abs() as f64).sum::<f64>() / hits.len() as f64 / 1000.0);
                let stars = if !passed {
                    0
                } else if hit_ratio >= 0.95 && mean.is_some_and(|m| m <= 60.0) {
                    3
                } else if hit_ratio >= 0.85 && self.wrong <= 3 {
                    2
                } else {
                    1
                };
                (passed, mean, stars)
            }
        };
        StageResult {
            passed,
            stars,
            hit_ratio,
            wrong: self.wrong,
            mean_abs_timing_ms,
            sections,
            threshold,
            suggest_practice: !passed && self.settings.failed_attempts >= 2,
        }
    }

    /// Audio-clock time (µs) when the stage is fully over (last window closed).
    pub fn end_us(&self) -> i64 {
        (t_end(&self.targets) * self.us_per_beat).round() as i64 + self.settings.input.window_us() + 1
    }
}

fn t_end(targets: &[Target]) -> f64 {
    targets.last().map_or(0.0, |t| t.beat + t.beats)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 2 bars of 4/4 at 60 bpm (1 beat = 1 s): C D E F | G-chord(C E G) half, rest half.
    fn song() -> Song {
        Song::from_json(
            r#"{"id":"t","title":"T","composer":"Trad.","arranger":"x","source":"original",
            "source_url":null,"license":"CC-BY-SA-4.0","composition_license":"public-domain",
            "bpm":60,"time":"4/4","key":"C",
            "bars":[{"RH":"C4:4 D4:4 E4:4 F4:4","LH":"C3:1"},{"RH":"C4E4G4:2 r:2","LH":"G2:1"}],
            "critical":[[0,1],[1,2]]}"#,
        )
        .unwrap()
    }

    fn press(s: &mut Session, pitch: u8, t_us: i64) {
        s.on_note(NoteEvent { pitch, on: true, t_us });
    }

    fn play_along(settings: Settings) -> Session {
        Session::new(&song(), Settings { mode: Mode::PlayAlong, ..settings })
    }

    #[test]
    fn perfect_play_along_gets_three_stars() {
        let mut s = play_along(Settings::default());
        for (i, p) in [60, 62, 64, 65].into_iter().enumerate() {
            press(&mut s, p, i as i64 * 1_000_000 + 10_000);
        }
        for p in [60, 64, 67] {
            press(&mut s, p, 4_020_000);
        }
        s.tick(s.end_us());
        let r = s.result();
        assert!(r.passed && r.stars == 3, "{r:?}");
        assert!(r.mean_abs_timing_ms.unwrap() < 20.0);
    }

    #[test]
    fn late_hits_within_window_count_but_lose_the_third_star() {
        let mut s = play_along(Settings::default());
        for (i, p) in [60, 62, 64, 65].into_iter().enumerate() {
            press(&mut s, p, i as i64 * 1_000_000 + 120_000); // 120 ms late, inside MIDI 150 ms
        }
        for p in [60, 64, 67] {
            press(&mut s, p, 4_120_000);
        }
        s.tick(s.end_us());
        let r = s.result();
        assert_eq!((r.passed, r.hit_ratio, r.stars), (true, 1.0, 2), "{r:?}");
    }

    #[test]
    fn outside_window_is_wrong_and_target_is_missed() {
        let mut s = play_along(Settings::default());
        press(&mut s, 60, 400_000); // 400 ms late for C at 0 s
        s.tick(1_000_000);
        assert_eq!(s.targets()[0].state, ChordState::Missed);
        assert_eq!(s.tick(1_000_000).wrong, 1);
    }

    #[test]
    fn chord_needs_every_note() {
        let mut s = play_along(Settings::default());
        press(&mut s, 60, 4_000_000);
        press(&mut s, 64, 4_010_000); // G missing
        s.tick(s.end_us());
        assert_eq!(s.targets()[4].state, ChordState::Missed);
    }

    #[test]
    fn failing_a_critical_section_fails_the_stage() {
        let mut s = play_along(Settings::default());
        press(&mut s, 60, 0); // only 1 of 4 in section 0
        for p in [60, 64, 67] {
            press(&mut s, p, 4_000_000);
        }
        s.tick(s.end_us());
        let r = s.result();
        assert_eq!(r.sections, vec![0.25, 1.0]);
        assert!(!r.passed && r.stars == 0);
    }

    #[test]
    fn threshold_adapts_after_failures() {
        assert_eq!(effective_threshold(0.7, 0), 0.7);
        assert_eq!(effective_threshold(0.7, 1), 0.7);
        assert!((effective_threshold(0.7, 2) - 0.6).abs() < 1e-9);
        assert_eq!(effective_threshold(0.7, 20), 0.4);
        // 3 of 4 hit (0.75) passes at the base threshold; 2 of 4 passes only after 4 failures.
        let mut s = play_along(Settings { failed_attempts: 4, ..Settings::default() });
        press(&mut s, 60, 0);
        press(&mut s, 62, 1_000_000);
        for p in [60, 64, 67] {
            press(&mut s, p, 4_000_000);
        }
        s.tick(s.end_us());
        let r = s.result();
        assert!(r.passed && (r.threshold - 0.5).abs() < 1e-9, "{r:?}");
    }

    #[test]
    fn practice_mode_is_suggested_after_repeated_failures() {
        let mut s = play_along(Settings { failed_attempts: 2, ..Settings::default() });
        s.tick(s.end_us());
        assert!(s.result().suggest_practice);
    }

    #[test]
    fn tempo_scales_target_times() {
        let mut s = play_along(Settings { tempo: 0.5, ..Settings::default() }); // 1 beat = 2 s
        press(&mut s, 60, 0);
        press(&mut s, 62, 2_000_000);
        assert!(matches!(s.targets()[1].state, ChordState::Hit { .. }));
    }

    #[test]
    fn wait_mode_holds_playhead_until_correct_note() {
        let mut s = Session::new(&song(), Settings { mode: Mode::Wait, ..Settings::default() });
        assert_eq!(s.tick(5_000_000).playhead_beat, 0.0);
        press(&mut s, 61, 5_000_000); // wrong
        press(&mut s, 60, 6_000_000);
        let f = s.tick(9_000_000);
        assert_eq!((f.playhead_beat, f.wrong, f.cursor), (1.0, 1, 1));
        for p in [62, 64, 65, 60, 64, 67] {
            press(&mut s, p, 10_000_000);
        }
        let r = s.result();
        assert!(r.passed && r.stars == 3 && r.mean_abs_timing_ms.is_none(), "{r:?}");
    }

    #[test]
    fn hand_filter_selects_left_hand_targets() {
        let s = Session::new(&song(), Settings { hand: HandFilter::Left, ..Settings::default() });
        let pitches: Vec<u8> = s.targets().iter().flat_map(|t| t.pitches.iter().copied()).collect();
        assert_eq!(pitches, vec![48, 43]);
        let both = Session::new(&song(), Settings { hand: HandFilter::Both, ..Settings::default() });
        assert_eq!(both.targets()[0].pitches, BTreeSet::from([48, 60]));
    }
}
