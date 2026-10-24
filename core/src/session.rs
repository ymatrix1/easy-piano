//! Exercise engine (docs/specs/exercise-engine.md): grades a stage while the
//! student plays. Pure and deterministic: the caller feeds note events and
//! audio-clock ticks in microseconds; the engine never reads a clock itself.

use crate::dynamics::{self, Grade, Layout, Onset};
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
    /// How early a press may come before its note (µs). Reference: the note
    /// opens 0.3 s ahead (0.15 s for the microphone, which lags).
    pub fn early_us(self) -> i64 {
        match self {
            Input::Midi | Input::Touch => 300_000,
            Input::Mic => 150_000,
        }
    }

    /// How late a press may come after its note (µs). Reference: 0.43 s.
    pub fn window_us(self) -> i64 {
        430_000
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
    /// Wait mode: how long a note waits before the hint (beam, key colours)
    /// shows. Reference: 4 s for note sequences, 1 s for one-note drills.
    pub hint_after_us: i64,
    /// `one_note` drill: passes on notes completed ("N correct of M"), hinted
    /// or not; the hint only costs stars.
    pub drill: bool,
    /// Play-along training: grade each critical section as it ends and
    /// replay failed ones, slowing down after repeated failures.
    pub training: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Settings {
            mode: Mode::PlayAlong,
            input: Input::Midi,
            tempo: 1.0,
            pass_ratio: 0.7,
            failed_attempts: 0,
            hand: HandFilter::Right,
            hint_after_us: WAIT_HINT_AFTER_US,
            drill: false,
            training: false,
        }
    }
}

fn hit_count(targets: &[Target]) -> usize {
    targets
        .iter()
        .filter(|t| matches!(t.state, ChordState::Hit { .. }))
        .count()
}

/// Wait mode: time before the hint shows (reference default).
pub const WAIT_HINT_AFTER_US: i64 = 4_000_000;
/// Wait mode: chord notes must start within this spread before the hint.
pub const CHORD_SPREAD_US: i64 = 400_000;
/// Wait mode: a stage passes when more than this share of chords was played
/// before its hint appeared (wrong keys do not count against it).
pub const WAIT_PASS_RATIO: f64 = 0.8;

/// Threshold drops 0.1 for every 2 failed attempts, floor 0.4 (spec).
pub fn effective_threshold(pass_ratio: f64, failed_attempts: u32) -> f64 {
    (pass_ratio - 0.1 * (failed_attempts / 2) as f64).max(0.4)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct NoteEvent {
    pub pitch: u8,
    pub on: bool,
    /// MIDI note-on velocity (0-127). Ignored by mic and touch input.
    pub velocity: u8,
    /// Audio-clock time in microseconds since the stage started.
    pub t_us: i64,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ChordState {
    Pending,
    Hit { delta_us: i64 },
    Missed,
}

/// Training: consecutive failures of one section before it is practised slowly.
pub const FAILS_BEFORE_PRACTICE: u32 = 2;
/// Training: tempo factor of practice runs (applied on top of the stage tempo).
pub const PRACTICE_TEMPO: f64 = 0.75;

/// Training outcome of one critical-section run (play-along with `training`).
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum SectionEvent {
    /// Passed at full tempo: the song continues into the next section.
    Passed { section: usize },
    /// Failed or practised: the engine rewound to `beat` (song beats) and the
    /// caller must restart its clock there at `tempo`. `practice` is true
    /// for slow practice runs; `intro` when practice mode just started.
    Replay {
        section: usize,
        beat: f64,
        tempo: f64,
        practice: bool,
        intro: bool,
        passed: bool,
    },
}

/// Play-along: a hit within this distance of its note counts as on time;
/// further out it is tagged early or late (still a hit).
pub const ON_TIME_US: i64 = 120_000;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Timing {
    Early,
    OnTime,
    Late,
}

impl Timing {
    pub fn of(delta_us: i64) -> Timing {
        if delta_us < -ON_TIME_US {
            Timing::Early
        } else if delta_us > ON_TIME_US {
            Timing::Late
        } else {
            Timing::OnTime
        }
    }
}

/// Play-along feedback the UI animates, in the order it happened.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Feedback {
    /// A chord was completed; `delta_us` is its first note's timing error.
    Hit {
        target: usize,
        delta_us: i64,
        timing: Timing,
    },
    /// A key that matched no open note.
    Wrong { pitch: u8, t_us: i64 },
    /// A note's window closed before it was completed.
    Missed { target: usize },
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
    /// Play-along: timing error (played − expected) of each matched note, µs.
    deltas_us: Vec<i64>,
    /// Wait mode: onset time of each chord pitch pressed so far.
    played_us: std::collections::BTreeMap<u8, i64>,
    /// Wait mode: the hint was shown before this target was completed.
    pub hinted: bool,
    pub state: ChordState,
    pub stem_downs: Vec<bool>,
    pub two_stems: Vec<bool>,
    pub left_hands: Vec<bool>,
    pub note_beats: Vec<f64>,
    pub ties: Vec<bool>,
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
    /// Wait mode: the current target has waited long enough to show the hint.
    pub hint_active: bool,
    /// Play-along: chords hit in a row; a miss or wrong key resets it.
    pub streak: usize,
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
    /// Notes matched / notes expected; every chord note counts on its own.
    pub notes_hit: usize,
    pub notes_total: usize,
    /// Song score parts (reference results screen), each 0–1.
    pub timing: f64,
    pub assists: f64,
    /// assists × notes × (0.75 + 0.25 × timing).
    pub score: f64,
    /// Continuous 0–3 stars from `score` (play-along); equals `stars` in wait mode.
    pub stars_exact: f64,
    /// Dynamics and hairpins graded from note velocity (MIDI only). Not part
    /// of the stars yet.
    pub dynamics: Grade,
}

/// Reference timing score: 0.8 × spread score + 0.2 × mean score, where an
/// error of 40 ms or less scores 1 and 300 ms or more scores 0. Microphone
/// input gets +0.1. No hits → 0.
pub fn timing_score(deltas_s: &[f64], midi: bool) -> f64 {
    if deltas_s.is_empty() {
        return 0.0;
    }
    let n = deltas_s.len() as f64;
    let mean = deltas_s.iter().sum::<f64>() / n;
    let var = deltas_s.iter().map(|d| (d - mean).powi(2)).sum::<f64>() / n;
    let part = |err: f64| ((0.3 - err) / 0.26).clamp(0.0, 1.0);
    let t = 0.8 * part(var.sqrt()) + 0.2 * part(mean.abs());
    if midi {
        t
    } else {
        (t + 0.1).min(1.0)
    }
}

/// Reference song score: assists × notes ratio × (0.75 + 0.25 × timing).
pub fn song_score(notes_ratio: f64, timing: f64, assists: f64) -> f64 {
    assists * notes_ratio * (0.75 + 0.25 * timing)
}

/// Reference star mapping: linear between 0→0, 0.5→1, 0.7→2, 0.9→3.
pub fn stars_from_score(score: f64) -> f64 {
    if score <= 0.5 {
        (score / 0.5).max(0.0)
    } else if score <= 0.7 {
        1.0 + (score - 0.5) / 0.2
    } else if score <= 0.9 {
        2.0 + (score - 0.7) / 0.2
    } else {
        3.0
    }
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
    /// Wait mode: when the current target became current.
    current_since_us: i64,
    /// Play-along: events not yet taken by the UI.
    feedback: Vec<Feedback>,
    streak: usize,
    /// Training: section being played, its consecutive failures, whether the
    /// current run is a slow practice run, and the lowest tempo used.
    section: usize,
    section_fails: u32,
    /// Training: wrong-key presses made during each section's current run.
    section_wrong: Vec<usize>,
    practicing: bool,
    min_tempo: f64,
    section_event: Option<SectionEvent>,
    /// Dynamics and hairpins of the song, on the beat line.
    layout: Layout,
    song_beats: f64,
    /// Matched MIDI onsets with their velocity, for dynamics grading.
    onsets: Vec<Onset>,
}

/// Whether the student plays this (non-accompaniment) note under [hand].
fn plays(hand: HandFilter, n: &TimedNote) -> bool {
    match hand {
        HandFilter::Right => !n.left_hand,
        HandFilter::Left => n.left_hand,
        HandFilter::Both => true,
    }
}

/// Notes the app plays along with the student in play-along: the hand that is
/// not being practised plus the backing parts (`ACC`, `DRUMS`, `BASS`, `PAD`, `CHOIR`).
pub fn companion_notes(song: &Song, hand: HandFilter) -> Vec<TimedNote> {
    song.timeline()
        .into_iter()
        .filter(|n| n.accomp || !plays(hand, n))
        .collect()
}

fn group_targets(notes: &[TimedNote], hand: HandFilter) -> Vec<Target> {
    let active: Vec<&TimedNote> = notes
        .iter()
        .filter(|n| !n.accomp && plays(hand, n))
        .collect();
    let mut out: Vec<Target> = Vec::new();
    let mut i = 0;
    while i < active.len() {
        let start_beat = active[i].start_beat;
        let mut j = i;
        while j < active.len() && (active[j].start_beat - start_beat).abs() < 1e-9 {
            j += 1;
        }
        let group = &active[i..j];
        let bar = group[0].bar;
        let beats = group.iter().map(|n| n.beats).fold(f64::INFINITY, f64::min);
        let pitches: BTreeSet<u8> = group.iter().map(|n| n.pitch).collect();

        let mut fingers = Vec::new();
        let mut stem_downs = Vec::new();
        let mut two_stems = Vec::new();
        let mut left_hands = Vec::new();
        let mut note_beats = Vec::new();
        let mut ties = Vec::new();

        for &p in &pitches {
            let p_notes: Vec<&&TimedNote> = group.iter().filter(|n| n.pitch == p).collect();
            let finger = p_notes.iter().find_map(|n| n.finger);
            fingers.push(finger);
            left_hands.push(p_notes[0].left_hand);
            note_beats.push(p_notes[0].beats);
            ties.push(p_notes.iter().any(|n| n.tie));

            let is_unison =
                p_notes.iter().any(|n| n.voice == 1) && p_notes.iter().any(|n| n.voice == 2);
            if is_unison {
                two_stems.push(true);
                stem_downs.push(false);
            } else {
                two_stems.push(false);
                let n = p_notes[0];
                if !n.left_hand {
                    stem_downs.push(n.voice == 2);
                } else {
                    let bar_has_lh2 = notes
                        .iter()
                        .any(|m| m.bar == n.bar && m.left_hand && m.voice == 2);
                    if n.voice == 2 {
                        stem_downs.push(false);
                    } else if bar_has_lh2 {
                        stem_downs.push(true);
                    } else {
                        stem_downs.push(false);
                    }
                }
            }
        }

        out.push(Target {
            beat: start_beat,
            beats,
            bar,
            pitches,
            fingers,
            played: BTreeSet::new(),
            first_us: None,
            played_us: Default::default(),
            deltas_us: Vec::new(),
            hinted: false,
            state: ChordState::Pending,
            stem_downs,
            two_stems,
            left_hands,
            note_beats,
            ties,
        });

        i = j;
    }
    out
}

impl Session {
    pub fn new(song: &Song, settings: Settings) -> Session {
        let targets = group_targets(&song.timeline(), settings.hand);
        let critical = if song.critical.is_empty() {
            vec![[0, song.bars.len()]]
        } else {
            song.critical.clone()
        };
        let section_count = critical.len();
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
            current_since_us: 0,
            feedback: Vec::new(),
            streak: 0,
            section: 0,
            section_fails: 0,
            section_wrong: vec![0; section_count],
            practicing: false,
            min_tempo: settings.tempo,
            section_event: None,
            layout: dynamics::layout(&song.marks(), song.total_beats()),
            song_beats: song.total_beats(),
            onsets: Vec::new(),
        }
    }

    pub fn targets(&self) -> &[Target] {
        &self.targets
    }

    /// Streaming practice (docs/specs/practice-mode.md): `song` is the session's
    /// song with bars appended. Targets already in the session keep their state;
    /// the new ones are added after them. Returns how many were added, or an
    /// error when `song` does not start with the session's targets.
    pub fn extend(&mut self, song: &Song) -> Result<usize, String> {
        let all = group_targets(&song.timeline(), self.settings.hand);
        let n = self.targets.len();
        if all.len() < n
            || self
                .targets
                .iter()
                .zip(&all)
                .any(|(a, b)| (a.beat - b.beat).abs() > 1e-9 || a.pitches != b.pitches)
        {
            return Err("extended song does not start with the current targets".into());
        }
        let added = all.len() - n;
        self.targets.extend(all.into_iter().skip(n));
        self.critical = vec![[0, song.bars.len()]];
        self.layout = dynamics::layout(&song.marks(), song.total_beats());
        self.song_beats = song.total_beats();
        if self.settings.mode == Mode::Wait && n > 0 && self.cursor == n && added > 0 {
            // The learner finished the old part: the next note is current from now.
            self.wait_beat = self.targets[n].beat;
            self.current_since_us = self.now_us;
        }
        Ok(added)
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

    /// Reference behaviour: the cursor moves on as soon as the chord is
    /// complete. Before the hint, all chord notes must start within
    /// `CHORD_SPREAD_US` (re-striking a note refreshes its time); after the
    /// hint any order and timing completes it. Wrong keys never block.
    fn on_note_wait(&mut self, e: NoteEvent) {
        let Some(t) = self.targets.get_mut(self.cursor) else {
            return;
        };
        if !t.pitches.contains(&e.pitch) {
            self.wrong += 1;
            return;
        }
        let beat = t.beat;
        if self.settings.input == Input::Midi {
            self.onsets.push(Onset {
                beat,
                velocity: e.velocity,
            });
        }
        let Some(t) = self.targets.get_mut(self.cursor) else {
            return;
        };
        t.played_us.insert(e.pitch, e.t_us);
        if t.played_us.len() < t.pitches.len() {
            return;
        }
        if !t.hinted {
            let lo = t.played_us.values().min().copied().unwrap_or(e.t_us);
            let hi = t.played_us.values().max().copied().unwrap_or(e.t_us);
            if hi - lo >= CHORD_SPREAD_US {
                return;
            }
        }
        t.state = ChordState::Hit { delta_us: 0 };
        self.cursor += 1;
        self.current_since_us = e.t_us;
        self.wait_beat = match self.targets.get(self.cursor) {
            Some(next) => next.beat,
            None => t_end(&self.targets),
        };
    }

    fn on_note_play_along(&mut self, e: NoteEvent) {
        self.expire(e.t_us);
        let (early, late) = (
            self.settings.input.early_us(),
            self.settings.input.window_us(),
        );
        // Nearest pending target containing this pitch, within the window.
        let best = (self.cursor..self.targets.len())
            .filter(|&i| {
                let t = &self.targets[i];
                t.state == ChordState::Pending
                    && t.pitches.contains(&e.pitch)
                    && !t.played.contains(&e.pitch)
            })
            .map(|i| (i, e.t_us - self.target_us(&self.targets[i])))
            .filter(|&(_, d)| -early <= d && d <= late)
            .map(|(i, d)| (i, d.abs()))
            .min_by_key(|&(_, d)| d);
        let Some((i, _)) = best else {
            self.wrong += 1;
            if self.settings.training && self.section < self.section_wrong.len() {
                self.section_wrong[self.section] += 1;
            }
            self.streak = 0;
            self.feedback.push(Feedback::Wrong {
                pitch: e.pitch,
                t_us: e.t_us,
            });
            return;
        };
        let target_us = self.target_us(&self.targets[i]);
        if self.settings.input == Input::Midi {
            self.onsets.push(Onset {
                beat: self.targets[i].beat,
                velocity: e.velocity,
            });
        }
        let t = &mut self.targets[i];
        t.played.insert(e.pitch);
        t.deltas_us.push(e.t_us - target_us);
        t.first_us.get_or_insert(e.t_us);
        if t.played.len() == t.pitches.len() {
            let delta_us = t.first_us.unwrap_or(e.t_us) - target_us;
            t.state = ChordState::Hit { delta_us };
            self.streak += 1;
            self.feedback.push(Feedback::Hit {
                target: i,
                delta_us,
                timing: Timing::of(delta_us),
            });
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
                self.streak = 0;
                self.feedback.push(Feedback::Missed { target: i });
            }
        }
        self.advance_cursor();
    }

    fn advance_cursor(&mut self) {
        while self.cursor < self.targets.len()
            && self.targets[self.cursor].state != ChordState::Pending
        {
            self.cursor += 1;
        }
    }

    /// Advances the audio clock and returns what the UI should draw.
    pub fn tick(&mut self, t_us: i64) -> Frame {
        self.now_us = self.now_us.max(t_us);
        // Wait mode: after waiting long enough the hint shows; from then on the
        // earlier presses of the chord are forgotten and any order completes it.
        if self.settings.mode == Mode::Wait {
            let since = self.current_since_us;
            let after = self.settings.hint_after_us;
            if let Some(t) = self.targets.get_mut(self.cursor) {
                if !t.hinted && self.now_us - since >= after {
                    t.hinted = true;
                    t.played_us.clear();
                }
            }
        }
        let playhead_beat = match self.settings.mode {
            Mode::Wait => self.wait_beat,
            Mode::PlayAlong => {
                self.expire(self.now_us);
                self.now_us as f64 / self.us_per_beat
            }
        };
        let hits = self
            .targets
            .iter()
            .filter(|t| matches!(t.state, ChordState::Hit { .. }))
            .count();
        let misses = self
            .targets
            .iter()
            .filter(|t| t.state == ChordState::Missed)
            .count();
        if self.settings.training && self.settings.mode == Mode::PlayAlong {
            self.check_section();
        }
        let hint_active = self.settings.mode == Mode::Wait
            && self.targets.get(self.cursor).is_some_and(|t| t.hinted);
        Frame {
            playhead_beat,
            cursor: self.cursor,
            hits,
            misses,
            wrong: self.wrong,
            done: self.cursor >= self.targets.len(),
            hint_active,
            streak: self.streak,
        }
    }

    /// Training: the section outcome decided by the last `tick`, if any.
    pub fn take_section_event(&mut self) -> Option<SectionEvent> {
        self.section_event.take()
    }

    /// Training: whether the current run is a slow practice run.
    pub fn practicing(&self) -> bool {
        self.practicing
    }

    /// Training: threshold for the current section run. Reference: every
    /// failure, and every passed practice run, lowers it like a failed attempt.
    fn section_threshold(&self) -> f64 {
        effective_threshold(
            self.settings.pass_ratio,
            self.settings.failed_attempts + self.section_fails,
        )
    }

    fn section_targets(&self, section: usize) -> std::ops::Range<usize> {
        let [a, b] = self.critical[section];
        let lo = self.targets.iter().position(|t| t.bar >= a);
        let hi = self.targets.iter().position(|t| t.bar >= b);
        match lo {
            Some(lo) => lo..hi.unwrap_or(self.targets.len()).max(lo),
            None => 0..0,
        }
    }

    /// Reference: a section passes when every note is judged and hits / notes
    /// ≥ threshold, and fails early once misses exceed (1 − threshold) × notes.
    fn check_section(&mut self) {
        if self.section >= self.critical.len() {
            return;
        }
        let range = self.section_targets(self.section);
        let total = range.len();
        if total == 0 {
            self.section += 1;
            return;
        }
        let thr = self.section_threshold();
        let ts = &self.targets[range.clone()];
        let hits = ts
            .iter()
            .filter(|t| matches!(t.state, ChordState::Hit { .. }))
            .count();
        let misses = ts.iter().filter(|t| t.state == ChordState::Missed).count();
        let errors = misses + self.section_wrong[self.section];
        let judged = hits + misses == total;
        let early_fail = errors as f64 > (1.0 - thr) * total as f64;
        if !judged && !early_fail {
            return;
        }
        let passed = !early_fail && hits as f64 >= thr * total as f64;
        let section = self.section;
        if passed && !self.practicing {
            self.section += 1;
            self.section_fails = 0;
            self.section_event = Some(SectionEvent::Passed { section });
            return;
        }
        // Practice passed → back to full tempo (counts as a failure for the
        // threshold); failed at full tempo → replay, slowly every Nth time;
        // practice failed → practise again.
        let (practice, intro) = if self.practicing {
            self.section_fails += 1;
            (!passed, false)
        } else {
            self.section_fails += 1;
            let slow = self.section_fails.is_multiple_of(FAILS_BEFORE_PRACTICE);
            (slow, slow)
        };
        let tempo = if practice {
            self.settings.tempo * PRACTICE_TEMPO
        } else {
            self.settings.tempo
        };
        let beat = self.targets[range.start].beat;
        self.rewind(range.start, tempo);
        self.practicing = practice;
        self.section_event = Some(SectionEvent::Replay {
            section,
            beat,
            tempo,
            practice,
            intro,
            passed,
        });
    }

    /// Resets targets from `from` on and switches to `tempo`. The clock
    /// restarts: the caller's next times are song time at the new tempo.
    fn rewind(&mut self, from: usize, tempo: f64) {
        let bpm = 60e6 / (self.us_per_beat * self.current_tempo());
        for t in &mut self.targets[from..] {
            t.state = ChordState::Pending;
            t.played.clear();
            t.first_us = None;
            t.deltas_us.clear();
        }
        self.us_per_beat = 60e6 / (bpm * tempo);
        self.min_tempo = self.min_tempo.min(tempo);
        self.cursor = from;
        if let Some(errors) = self.section_wrong.get_mut(self.section) {
            *errors = 0;
        }
        self.streak = 0;
        self.feedback.clear();
        self.now_us = i64::MIN / 2;
    }

    fn current_tempo(&self) -> f64 {
        if self.practicing {
            self.settings.tempo * PRACTICE_TEMPO
        } else {
            self.settings.tempo
        }
    }

    /// Drains the play-along feedback queued since the last call.
    pub fn take_feedback(&mut self) -> Vec<Feedback> {
        std::mem::take(&mut self.feedback)
    }

    /// Final grade. Call when `Frame::done` (PlayAlong: after the last window closes).
    pub fn result(&self) -> StageResult {
        let threshold =
            effective_threshold(self.settings.pass_ratio, self.settings.failed_attempts);
        let total = self.targets.len().max(1);
        let hits: Vec<i64> = self
            .targets
            .iter()
            .filter_map(|t| match t.state {
                ChordState::Hit { delta_us } => Some(delta_us),
                _ => None,
            })
            .collect();
        let hit_ratio = match self.settings.mode {
            Mode::Wait => {
                self.targets
                    .iter()
                    .filter(|t| matches!(t.state, ChordState::Hit { .. }) && !t.hinted)
                    .count() as f64
                    / total as f64
            }
            Mode::PlayAlong => hits.len() as f64 / total as f64,
        };
        let sections: Vec<f64> = self
            .critical
            .iter()
            .map(|&[a, b]| {
                let in_sec: Vec<&Target> = self
                    .targets
                    .iter()
                    .filter(|t| t.bar >= a && t.bar < b)
                    .collect();
                if in_sec.is_empty() {
                    1.0
                } else {
                    in_sec
                        .iter()
                        .filter(|t| matches!(t.state, ChordState::Hit { .. }))
                        .count() as f64
                        / in_sec.len() as f64
                }
            })
            .collect();
        let (passed, mean_abs_timing_ms, stars) = match self.settings.mode {
            Mode::Wait => {
                // Reference: share of chords completed before their hint.
                let clean = self
                    .targets
                    .iter()
                    .filter(|t| matches!(t.state, ChordState::Hit { .. }) && !t.hinted)
                    .count();
                let ratio = clean as f64 / total as f64;
                let done = self.cursor >= self.targets.len();
                let passed = if self.settings.drill {
                    done && hit_count(&self.targets) as f64 / total as f64 > WAIT_PASS_RATIO
                } else {
                    done && ratio > WAIT_PASS_RATIO
                };
                let stars = if !passed {
                    0
                } else if clean == self.targets.len() {
                    3
                } else if ratio >= 0.9 {
                    2
                } else {
                    1
                };
                (passed, None, stars)
            }
            Mode::PlayAlong => {
                let passed = sections.iter().all(|&r| r >= threshold);
                let mean = (!hits.is_empty()).then(|| {
                    hits.iter().map(|d| d.abs() as f64).sum::<f64>() / hits.len() as f64 / 1000.0
                });
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
        let notes_total: usize = self.targets.iter().map(|t| t.pitches.len()).sum();
        let (notes_hit, timing, assists, score, stars_exact) = match self.settings.mode {
            Mode::Wait => {
                let hit: usize = self
                    .targets
                    .iter()
                    .filter(|t| matches!(t.state, ChordState::Hit { .. }))
                    .map(|t| t.pitches.len())
                    .sum();
                (hit, 1.0, 1.0, hit_ratio, stars as f64)
            }
            Mode::PlayAlong => {
                let deltas: Vec<f64> = self
                    .targets
                    .iter()
                    .flat_map(|t| t.deltas_us.iter().map(|d| *d as f64 / 1e6))
                    .collect();
                let hit = deltas.len().min(notes_total);
                let ratio = if notes_total == 0 {
                    0.0
                } else {
                    hit as f64 / notes_total as f64
                };
                let timing = timing_score(&deltas, self.settings.input == Input::Midi);
                // Assists: playing slower than full tempo counts as help.
                let assists = self.min_tempo.clamp(0.0, 1.0);
                let score = song_score(ratio, timing, assists);
                (hit, timing, assists, score, stars_from_score(score))
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
            notes_hit,
            notes_total,
            timing,
            assists,
            score,
            stars_exact,
            dynamics: dynamics::grade(&self.layout, &self.onsets, self.song_beats),
        }
    }

    /// Audio-clock time (µs) when the stage is fully over (last window closed).
    pub fn end_us(&self) -> i64 {
        (t_end(&self.targets) * self.us_per_beat).round() as i64
            + self.settings.input.window_us()
            + 1
    }
}

fn t_end(targets: &[Target]) -> f64 {
    targets.last().map_or(0.0, |t| t.beat + t.beats)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::song::Part;

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
        s.on_note(NoteEvent {
            pitch,
            on: true,
            velocity: 80,
            t_us,
        });
    }

    fn play_along(settings: Settings) -> Session {
        Session::new(
            &song(),
            Settings {
                mode: Mode::PlayAlong,
                ..settings
            },
        )
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
    fn early_press_up_to_300ms_counts_for_midi() {
        let mut s = play_along(Settings::default());
        press(&mut s, 62, 750_000); // D at 1 s, 250 ms early
        press(&mut s, 64, 1_650_000); // E at 2 s, 350 ms early: too early
        let t = s.targets();
        assert!(matches!(t[1].state, ChordState::Hit { .. }));
        assert_eq!(t[2].state, ChordState::Pending);
    }

    #[test]
    fn outside_window_is_wrong_and_target_is_missed() {
        let mut s = play_along(Settings::default());
        press(&mut s, 60, 500_000); // 500 ms late for C at 0 s
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
        let mut s = play_along(Settings {
            failed_attempts: 4,
            ..Settings::default()
        });
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
        let mut s = play_along(Settings {
            failed_attempts: 2,
            ..Settings::default()
        });
        s.tick(s.end_us());
        assert!(s.result().suggest_practice);
    }

    #[test]
    fn tempo_scales_target_times() {
        let mut s = play_along(Settings {
            tempo: 0.5,
            ..Settings::default()
        }); // 1 beat = 2 s
        press(&mut s, 60, 0);
        press(&mut s, 62, 2_000_000);
        assert!(matches!(s.targets()[1].state, ChordState::Hit { .. }));
    }

    #[test]
    fn wait_mode_holds_playhead_until_correct_note() {
        let mut s = Session::new(
            &song(),
            Settings {
                mode: Mode::Wait,
                ..Settings::default()
            },
        );
        // Song time does not move while waiting (well before the 4 s hint).
        assert_eq!(s.tick(2_000_000).playhead_beat, 0.0);
        press(&mut s, 61, 2_000_000); // wrong
        press(&mut s, 60, 3_000_000);
        let f = s.tick(3_500_000);
        assert_eq!((f.playhead_beat, f.wrong, f.cursor), (1.0, 1, 1));
        for p in [62, 64, 65, 60, 64, 67] {
            press(&mut s, p, 4_000_000);
        }
        let r = s.result();
        assert!(
            r.passed && r.stars == 3 && r.mean_abs_timing_ms.is_none(),
            "{r:?}"
        );
    }

    fn wait() -> Session {
        Session::new(
            &song(),
            Settings {
                mode: Mode::Wait,
                ..Settings::default()
            },
        )
    }

    #[test]
    fn wait_hint_appears_after_four_seconds_and_resets_partial_chord() {
        let mut s = wait();
        assert!(!s.tick(3_900_000).hint_active);
        assert!(s.tick(4_000_000).hint_active);
        // A correct press moves on at once and restarts the hint timer.
        press(&mut s, 60, 4_100_000);
        let f = s.tick(4_200_000);
        assert_eq!((f.cursor, f.hint_active), (1, false));
        assert!(s.tick(8_100_000).hint_active);
    }

    #[test]
    fn wait_chord_needs_onsets_within_400ms_before_hint() {
        let mut s = wait();
        for (i, p) in [60, 62, 64, 65].into_iter().enumerate() {
            press(&mut s, p, i as i64 * 1_000_000);
        }
        // Chord C E G: G pressed 500 ms after the others does not complete it.
        press(&mut s, 60, 4_000_000);
        press(&mut s, 64, 4_000_000);
        press(&mut s, 67, 4_500_000);
        assert_eq!(s.tick(4_600_000).cursor, 4);
        // Re-striking C and E close to G closes the window.
        press(&mut s, 60, 4_700_000);
        press(&mut s, 64, 4_750_000);
        assert!(s.tick(4_800_000).done);
    }

    #[test]
    fn drill_passes_on_completed_notes_even_when_hinted() {
        let mut s = wait();
        s.settings.drill = true;
        s.settings.hint_after_us = 1_000_000;
        // Every note takes 2 s, so each one shows the hint first.
        let mut t = 0;
        for p in [60, 62, 64, 65] {
            t += 2_000_000;
            s.tick(t);
            press(&mut s, p, t + 10_000);
        }
        t += 2_000_000;
        s.tick(t);
        for p in [60, 64, 67] {
            press(&mut s, p, t + 10_000);
        }
        let r = s.result();
        assert!(r.passed && r.stars == 1, "{r:?}");
    }

    #[test]
    fn wait_hinted_target_completes_but_is_not_clean() {
        let mut s = wait();
        s.tick(5_000_000); // hint on the first note
        press(&mut s, 60, 5_100_000);
        for (i, p) in [62, 64, 65].into_iter().enumerate() {
            press(&mut s, p, 5_200_000 + i as i64 * 100_000);
        }
        for p in [60, 64, 67] {
            press(&mut s, p, 6_000_000);
        }
        let r = s.result();
        // 4 of 5 targets clean = 0.8, not > 0.8: fails like the reference.
        assert!((r.hit_ratio - 0.8).abs() < 1e-9 && !r.passed, "{r:?}");
    }

    #[test]
    fn wait_wrong_keys_do_not_lower_the_grade() {
        let mut s = wait();
        for p in [61, 63, 66, 68, 70, 72] {
            press(&mut s, p, 100_000);
        }
        for (i, p) in [60, 62, 64, 65].into_iter().enumerate() {
            press(&mut s, p, 200_000 + i as i64 * 300_000);
        }
        for p in [60, 64, 67] {
            press(&mut s, p, 2_000_000);
        }
        let r = s.result();
        assert!(r.passed && r.stars == 3 && r.wrong == 6, "{r:?}");
    }

    #[test]
    fn timing_score_follows_reference_bounds() {
        assert_eq!(timing_score(&[], true), 0.0);
        assert!((timing_score(&[0.02, 0.02, 0.02], true) - 1.0).abs() < 1e-9);
        // spread 0.3 s → 0, mean 0 → 1
        assert!((timing_score(&[0.3, -0.3], true) - 0.2).abs() < 1e-9);
        // mean 0.17 s → 0.5, no spread → 1; microphone bonus +0.1, capped at 1
        assert!((timing_score(&[0.17], true) - 0.9).abs() < 1e-9);
        assert!((timing_score(&[0.17], false) - 1.0).abs() < 1e-9);
    }

    #[test]
    fn stars_interpolate_between_reference_thresholds() {
        assert_eq!(stars_from_score(0.25), 0.5);
        assert!((stars_from_score(0.6) - 1.5).abs() < 1e-9);
        assert!((stars_from_score(0.8) - 2.5).abs() < 1e-9);
        assert_eq!(stars_from_score(0.95), 3.0);
        assert!((song_score(1.0, 1.0, 1.0) - 1.0).abs() < 1e-9);
        assert!((song_score(0.5, 0.0, 1.0) - 0.375).abs() < 1e-9);
    }

    #[test]
    fn play_along_result_counts_chord_notes_and_tempo_assist() {
        let mut s = play_along(Settings {
            tempo: 0.5,
            ..Settings::default()
        });
        // 1 beat = 2 s at half tempo; hit C and the chord, skip D E F.
        press(&mut s, 60, 10_000);
        for p in [60, 64, 67] {
            press(&mut s, p, 8_010_000);
        }
        s.tick(s.end_us());
        let r = s.result();
        assert_eq!((r.notes_hit, r.notes_total), (4, 7));
        assert!(
            (r.assists - 0.5).abs() < 1e-9 && (r.timing - 1.0).abs() < 1e-9,
            "{r:?}"
        );
        assert!((r.score - song_score(4.0 / 7.0, 1.0, 0.5)).abs() < 1e-9);
    }

    #[test]
    fn accompaniment_is_never_a_target_and_companion_has_other_hand() {
        let json = r#"{"id":"t","title":"T","composer":"Trad.","arranger":"x","source":"original",
            "source_url":null,"license":"CC-BY-SA-4.0","composition_license":"public-domain",
            "bpm":60,"time":"4/4","key":"C",
            "bars":[{"RH":"C4:1","LH":"C3:1","ACC":"E3G3:2 E3G3:2"}]}"#;
        let song = Song::from_json(json).unwrap();
        assert!(song.validate().is_empty(), "{:?}", song.validate());
        let s = Session::new(
            &song,
            Settings {
                hand: HandFilter::Both,
                ..Settings::default()
            },
        );
        let pitches: Vec<u8> = s
            .targets()
            .iter()
            .flat_map(|t| t.pitches.iter().copied())
            .collect();
        assert_eq!(pitches, vec![48, 60]);
        let comp: Vec<u8> = companion_notes(&song, HandFilter::Right)
            .iter()
            .map(|n| n.pitch)
            .collect();
        assert_eq!(comp, vec![48, 52, 55, 52, 55]); // beat 0: LH C3 + ACC E3 G3; beat 2: ACC again
        assert_eq!(companion_notes(&song, HandFilter::Both).len(), 4);
    }

    #[test]
    fn drums_and_bass_join_the_companion_never_the_targets() {
        let song = Song::from_json(r#"{"id":"t","title":"T","composer":"Trad.","arranger":"x","source":"original",
            "license":"CC0-1.0","composition_license":"public-domain","bpm":60,"time":"4/4","key":"C",
            "bars":[{"RH":"C4:1","DRUMS":"C2:2 D2:2","BASS":"C2:1","PAD":"G3:1"}]}"#).unwrap();
        let s = Session::new(
            &song,
            Settings {
                hand: HandFilter::Both,
                ..Settings::default()
            },
        );
        assert_eq!(s.targets().len(), 1);
        let comp: Vec<(u8, Part)> = companion_notes(&song, HandFilter::Both)
            .iter()
            .map(|n| (n.pitch, n.part))
            .collect();
        assert_eq!(
            comp,
            vec![
                (36, Part::Bass),
                (36, Part::Drums),
                (55, Part::Pad),
                (38, Part::Drums)
            ]
        );
    }

    #[test]
    fn hand_filter_selects_left_hand_targets() {
        let s = Session::new(
            &song(),
            Settings {
                hand: HandFilter::Left,
                ..Settings::default()
            },
        );
        let pitches: Vec<u8> = s
            .targets()
            .iter()
            .flat_map(|t| t.pitches.iter().copied())
            .collect();
        assert_eq!(pitches, vec![48, 43]);
        let both = Session::new(
            &song(),
            Settings {
                hand: HandFilter::Both,
                ..Settings::default()
            },
        );
        assert_eq!(both.targets()[0].pitches, BTreeSet::from([48, 60]));
    }

    #[test]
    fn extend_appends_targets_and_keeps_state() {
        let mut s = wait();
        let first = s.targets().len();
        for (i, t) in s.targets().to_vec().iter().enumerate() {
            for &p in &t.pitches {
                press(&mut s, p, 1_000_000 * (i as i64 + 1));
            }
        }
        assert!(s.tick(9_000_000).done);
        let mut longer = song();
        longer.bars.push(longer.bars[0].clone());
        assert_eq!(s.extend(&longer).unwrap(), 4);
        assert_eq!(s.targets().len(), first + 4);
        assert!(s.targets()[..first]
            .iter()
            .all(|t| matches!(t.state, ChordState::Hit { .. })));
        let f = s.tick(9_100_000);
        assert!(!f.done && f.cursor == first);
        assert_eq!(f.playhead_beat, s.targets()[first].beat);
        let mut other = song();
        other.bars[0] = longer.bars[1].clone();
        assert!(s.extend(&other).is_err());
    }

    fn training() -> Session {
        play_along(Settings {
            training: true,
            ..Settings::default()
        })
    }

    /// Plays section 0 (C D E F at 0..3 s on the current clock) hitting `n` notes.
    fn run_section0(s: &mut Session, n: usize, us_per_beat: i64) {
        for (i, p) in [60, 62, 64, 65].into_iter().enumerate().take(n) {
            press(s, p, i as i64 * us_per_beat);
        }
        s.tick(3 * us_per_beat + 500_000);
    }

    #[test]
    fn feedback_reports_timing_wrong_and_missed() {
        let mut s = play_along(Settings::default());
        press(&mut s, 60, -200_000); // C 200 ms early
        press(&mut s, 62, 1_050_000); // D on time
        press(&mut s, 70, 1_500_000); // wrong key
        s.tick(2_500_000); // E window closed
        let f = s.take_feedback();
        assert_eq!(
            f,
            vec![
                Feedback::Hit {
                    target: 0,
                    delta_us: -200_000,
                    timing: Timing::Early
                },
                Feedback::Hit {
                    target: 1,
                    delta_us: 50_000,
                    timing: Timing::OnTime
                },
                Feedback::Wrong {
                    pitch: 70,
                    t_us: 1_500_000
                },
                Feedback::Missed { target: 2 },
            ]
        );
        assert!(s.take_feedback().is_empty());
        assert_eq!(s.tick(2_500_000).streak, 0);
    }

    #[test]
    fn streak_counts_hits_in_a_row() {
        let mut s = play_along(Settings::default());
        press(&mut s, 60, 0);
        press(&mut s, 62, 1_000_000);
        assert_eq!(s.tick(1_100_000).streak, 2);
        press(&mut s, 71, 1_200_000);
        assert_eq!(s.tick(1_300_000).streak, 0);
    }

    #[test]
    fn training_passes_section_and_moves_on() {
        let mut s = training();
        run_section0(&mut s, 3, 1_000_000); // 3/4 = 0.75 >= 0.7
        assert_eq!(
            s.take_section_event(),
            Some(SectionEvent::Passed { section: 0 })
        );
    }

    #[test]
    fn training_fails_early_and_replays_then_slows_on_second_fail() {
        let mut s = training();
        // Two misses > (1 - 0.7) × 4 = 1.2 → early fail before the section ends.
        s.tick(1_500_000);
        assert_eq!(
            s.take_section_event(),
            Some(SectionEvent::Replay {
                section: 0,
                beat: 0.0,
                tempo: 1.0,
                practice: false,
                intro: false,
                passed: false
            })
        );
        assert_eq!(s.targets()[0].state, ChordState::Pending);
        // Second consecutive failure (threshold now 0.6): practice at 75%.
        s.tick(1_500_000);
        assert_eq!(
            s.take_section_event(),
            Some(SectionEvent::Replay {
                section: 0,
                beat: 0.0,
                tempo: 0.75,
                practice: true,
                intro: true,
                passed: false
            })
        );
        assert!(s.practicing());
        // Practice run at 75% (1 beat = 1.333 s), all hit → back to full tempo.
        run_section0(&mut s, 4, 1_333_333);
        assert_eq!(
            s.take_section_event(),
            Some(SectionEvent::Replay {
                section: 0,
                beat: 0.0,
                tempo: 1.0,
                practice: false,
                intro: false,
                passed: true
            })
        );
        assert!(!s.practicing());
        // Threshold dropped to 0.6 after 3 counted failures: 3/4 passes at full speed.
        run_section0(&mut s, 3, 1_000_000);
        assert_eq!(
            s.take_section_event(),
            Some(SectionEvent::Passed { section: 0 })
        );
        // Slow runs count as an assist in the score.
        assert_eq!(s.result().assists, 0.75);
    }

    #[test]
    fn training_counts_wrong_keys_toward_replay_and_slow_practice() {
        let mut s = training();
        press(&mut s, 70, 0);
        s.tick(0);
        assert_eq!(s.take_section_event(), None);
        press(&mut s, 70, 0);
        s.tick(0);
        assert_eq!(
            s.take_section_event(),
            Some(SectionEvent::Replay {
                section: 0,
                beat: 0.0,
                tempo: 1.0,
                practice: false,
                intro: false,
                passed: false
            })
        );

        press(&mut s, 70, 0);
        s.tick(0);
        assert_eq!(s.take_section_event(), None);
        press(&mut s, 70, 0);
        s.tick(0);
        assert_eq!(
            s.take_section_event(),
            Some(SectionEvent::Replay {
                section: 0,
                beat: 0.0,
                tempo: 0.75,
                practice: true,
                intro: true,
                passed: false
            })
        );
        assert!(s.practicing());
    }

    #[test]
    fn training_off_never_rewinds() {
        let mut s = play_along(Settings::default());
        s.tick(3_500_000);
        assert_eq!(s.take_section_event(), None);
        assert_eq!(s.targets()[0].state, ChordState::Missed);
    }

    #[test]
    fn two_voices_merged_targets_and_wait_mode() {
        let s = Song::from_json(
            r#"{"id":"t","title":"T","composer":"Trad.","arranger":"x","source":"original",
            "source_url":null,"license":"CC-BY-SA-4.0","composition_license":"public-domain",
            "bpm":60,"time":"4/4","key":"C",
            "bars":[{"RH":"E4:4 F4:4 G4:4 A4:4","RH2":"C4:1","LH":"C3:1"}],
            "critical":[[0,1]]}"#,
        )
        .unwrap();

        // Right hand session: targets should merge RH and RH2
        let mut session = Session::new(
            &s,
            Settings {
                mode: Mode::Wait,
                hand: HandFilter::Right,
                ..Default::default()
            },
        );

        // 4 targets at beats 0, 1, 2, 3
        let ts = session.targets();
        assert_eq!(ts.len(), 4);
        // At beat 0: C4 (voice 2) and E4 (voice 1) are a chord target
        assert_eq!(ts[0].beat, 0.0);
        assert_eq!(ts[0].pitches, BTreeSet::from([60, 64]));
        // C4 has stem down (voice 2), E4 has stem up (voice 1)
        assert_eq!(ts[0].stem_downs, vec![true, false]);
        assert_eq!(ts[0].two_stems, vec![false, false]);

        // At beat 1: F4 (voice 1)
        assert_eq!(ts[1].beat, 1.0);
        assert_eq!(ts[1].pitches, BTreeSet::from([65]));
        assert_eq!(ts[1].stem_downs, vec![false]);

        // Press C4 and E4 within spread to hit target 0
        press(&mut session, 60, 0);
        press(&mut session, 64, 50_000);
        assert_eq!(session.tick(50_000).cursor, 1);
        assert_eq!(session.targets()[0].state, ChordState::Hit { delta_us: 0 });

        // Companion notes for Right hand should include LH (left hand)
        let companion = companion_notes(&s, HandFilter::Right);
        assert_eq!(companion.len(), 1);
        assert_eq!(companion[0].pitch, 48); // C3
    }

    #[test]
    fn unison_forms_two_stems_target() {
        let s = Song::from_json(
            r#"{"id":"t","title":"T","composer":"Trad.","arranger":"x","source":"original",
            "source_url":null,"license":"CC-BY-SA-4.0","composition_license":"public-domain",
            "bpm":60,"time":"4/4","key":"C",
            "bars":[{"RH":"C4:4 D4:4 E4:4 F4:4","RH2":"C4:1","LH":"C3:1"}],
            "critical":[[0,1]]}"#,
        )
        .unwrap();

        let session = Session::new(
            &s,
            Settings {
                mode: Mode::PlayAlong,
                hand: HandFilter::Right,
                ..Default::default()
            },
        );

        let ts = session.targets();
        assert_eq!(ts.len(), 4);
        // Target 0 has unison C4: graded once, two_stems is true
        assert_eq!(ts[0].pitches, BTreeSet::from([60]));
        assert_eq!(ts[0].two_stems, vec![true]);
    }

    #[test]
    fn ties_are_preserved_in_targets() {
        let s = Song::from_json(
            r#"{"id":"t","title":"T","composer":"Trad.","arranger":"x","source":"original",
            "source_url":null,"license":"CC-BY-SA-4.0","composition_license":"public-domain",
            "bpm":60,"time":"4/4","key":"C",
            "bars":[{"RH":"C4:2 D4:2 {tie}"},{"RH":"D4:2 E4:2"}],
            "critical":[[0,2]]}"#,
        )
        .unwrap();

        let session = Session::new(
            &s,
            Settings {
                mode: Mode::PlayAlong,
                hand: HandFilter::Right,
                ..Default::default()
            },
        );

        let ts = session.targets();
        assert_eq!(ts.len(), 4);
        assert_eq!(ts[0].ties, vec![false]);
        assert_eq!(ts[1].ties, vec![true]);
        assert_eq!(ts[2].ties, vec![false]);
        assert_eq!(ts[3].ties, vec![false]);
    }

    fn marked_song() -> Song {
        Song::from_json(
            r#"{"id":"t","title":"T","composer":"Trad.","arranger":"x","source":"original",
            "source_url":null,"license":"CC-BY-SA-4.0","composition_license":"public-domain",
            "bpm":60,"time":"4/4","key":"C",
            "bars":[{"RH":"{dyn:\"p\"} C4:4 D4:4 E4:4 F4:4"}]}"#,
        )
        .unwrap()
    }

    fn play_marked(input: Input, velocity: u8) -> StageResult {
        let mut s = Session::new(
            &marked_song(),
            Settings {
                mode: Mode::PlayAlong,
                input,
                ..Settings::default()
            },
        );
        for (i, p) in [60, 62, 64, 65].into_iter().enumerate() {
            s.on_note(NoteEvent {
                pitch: p,
                on: true,
                velocity,
                t_us: i as i64 * 1_000_000 + 10_000,
            });
        }
        s.tick(s.end_us());
        s.result()
    }

    #[test]
    fn midi_velocity_grades_the_dynamic() {
        let soft = play_marked(Input::Midi, 50);
        assert_eq!(soft.dynamics.dynamics_total, 1);
        assert_eq!(soft.dynamics.dynamics_passed, 1);
        let loud = play_marked(Input::Midi, 110);
        assert_eq!(loud.dynamics.dynamics_passed, 0);
    }

    #[test]
    fn mic_input_is_not_graded_for_dynamics() {
        let r = play_marked(Input::Mic, 110);
        assert_eq!(r.dynamics, crate::dynamics::Grade::default());
    }
}
