//! Bridge over the core session engine for the practice screen.
//! Logic stays in `easy_piano_core::session`; this file only adapts types.

use easy_piano_core::session::{ChordState, HandFilter, Input, Mode, NoteEvent, Session, Settings, WAIT_HINT_AFTER_US};
use easy_piano_core::session::companion_notes;
use easy_piano_core::song::Song;
use flutter_rust_bridge::frb;

/// One note or chord to play, for drawing.
pub struct TargetView {
    pub beat: f64,
    pub beats: f64,
    pub bar: u32,
    pub pitches: Vec<u8>,
    pub fingers: Vec<u8>,
    /// 0 pending, 1 hit, 2 missed.
    pub state: u8,
}

pub struct FrameView {
    pub playhead_beat: f64,
    pub cursor: u32,
    pub hits: u32,
    pub misses: u32,
    pub wrong: u32,
    pub done: bool,
    /// Wait mode: the note has waited long enough to show the hint.
    pub hint_active: bool,
}

pub struct ResultView {
    pub passed: bool,
    pub stars: u8,
    pub hit_ratio: f64,
    pub wrong: u32,
    pub mean_abs_timing_ms: Option<f64>,
    pub sections: Vec<f64>,
    pub threshold: f64,
    pub suggest_practice: bool,
    /// Every chord note counts on its own.
    pub notes_hit: u32,
    pub notes_total: u32,
    /// Reference song score parts, 0–1.
    pub timing: f64,
    pub assists: f64,
    pub score: f64,
    /// Continuous 0–3 stars (fractional fill on screen).
    pub stars_exact: f64,
}

pub struct SongInfo {
    pub id: String,
    pub title: String,
    pub composer: String,
    pub bpm: f64,
    pub beats_per_bar: u32,
    pub bars: u32,
}

/// A note the app plays (companion hand, accompaniment, pre-listen).
pub struct NoteView {
    pub pitch: u8,
    pub beat: f64,
    pub beats: f64,
    /// Score part: "RH", "LH", "ACC", "DRUMS" (pitch is a General MIDI drum
    /// number), "BASS" or "PAD".
    pub part_name: String,
}

fn hand_filter(hand: &str) -> HandFilter {
    match hand {
        "LH" => HandFilter::Left,
        "both" => HandFilter::Both,
        _ => HandFilter::Right,
    }
}

/// Notes the app plays along in play-along: the hand not being practised plus
/// the song's backing parts (`ACC`, `DRUMS`, `BASS`, `PAD`).
#[frb(sync)]
pub fn companion(song_json: String, hand: String) -> Result<Vec<NoteView>, String> {
    let song = Song::from_json(&song_json)?;
    Ok(companion_notes(&song, hand_filter(&hand))
        .into_iter()
        .map(|n| NoteView { pitch: n.pitch, beat: n.start_beat, beats: n.beats, part_name: n.part.key().to_string() })
        .collect())
}

/// Validates a song file; returns its summary or the lint errors.
#[frb(sync)]
pub fn inspect_song(json: String) -> Result<SongInfo, String> {
    let song = Song::from_json(&json)?;
    let errs = song.validate();
    if !errs.is_empty() {
        return Err(errs.join("; "));
    }
    Ok(SongInfo {
        id: song.id.clone(),
        title: song.title.clone(),
        composer: song.composer.clone(),
        bpm: song.bpm,
        beats_per_bar: song.time_signature().map_or(4, |(n, _)| n),
        bars: song.bars.len() as u32,
    })
}

#[frb(opaque)]
pub struct PracticeSession {
    inner: Session,
}

impl PracticeSession {
    /// `mode`: "wait" | "play_along" | "one_note"; `input`: "midi" | "mic" | "touch";
    /// `hand`: "RH" | "LH" | "both".
    #[frb(sync)]
    pub fn create(
        song_json: String,
        mode: String,
        input: String,
        hand: String,
        tempo: f64,
        pass_ratio: f64,
        failed_attempts: u32,
    ) -> Result<PracticeSession, String> {
        let song = Song::from_json(&song_json)?;
        let errs = song.validate();
        if !errs.is_empty() {
            return Err(errs.join("; "));
        }
        let settings = Settings {
            // one_note drills run as wait mode until a dedicated flow exists (spec).
            mode: if mode == "play_along" { Mode::PlayAlong } else { Mode::Wait },
            input: match input.as_str() {
                "mic" => Input::Mic,
                "touch" => Input::Touch,
                _ => Input::Midi,
            },
            hand: hand_filter(&hand),
            tempo,
            pass_ratio,
            failed_attempts,
            // Reference: hint after 1 s in one-note drills, 4 s in note sequences.
            hint_after_us: if mode == "one_note" { 1_000_000 } else { WAIT_HINT_AFTER_US },
            drill: mode == "one_note",
        };
        Ok(PracticeSession { inner: Session::new(&song, settings) })
    }

    #[frb(sync)]
    pub fn targets(&self) -> Vec<TargetView> {
        self.inner
            .targets()
            .iter()
            .map(|t| TargetView {
                beat: t.beat,
                beats: t.beats,
                bar: t.bar as u32,
                pitches: t.pitches.iter().copied().collect(),
                fingers: t.fingers.iter().map(|f| f.unwrap_or(0)).collect(),
                state: match t.state {
                    ChordState::Pending => 0,
                    ChordState::Hit { .. } => 1,
                    ChordState::Missed => 2,
                },
            })
            .collect()
    }

    #[frb(sync)]
    pub fn on_note(&mut self, pitch: u8, on: bool, t_us: i64) {
        self.inner.on_note(NoteEvent { pitch, on, t_us });
    }

    #[frb(sync)]
    pub fn tick(&mut self, t_us: i64) -> FrameView {
        let f = self.inner.tick(t_us);
        FrameView {
            playhead_beat: f.playhead_beat,
            cursor: f.cursor as u32,
            hits: f.hits as u32,
            misses: f.misses as u32,
            wrong: f.wrong as u32,
            done: f.done,
            hint_active: f.hint_active,
        }
    }

    #[frb(sync)]
    pub fn end_us(&self) -> i64 {
        self.inner.end_us()
    }

    #[frb(sync)]
    pub fn result(&self) -> ResultView {
        let r = self.inner.result();
        ResultView {
            passed: r.passed,
            stars: r.stars,
            hit_ratio: r.hit_ratio,
            wrong: r.wrong as u32,
            mean_abs_timing_ms: r.mean_abs_timing_ms,
            sections: r.sections,
            threshold: r.threshold,
            suggest_practice: r.suggest_practice,
            notes_hit: r.notes_hit as u32,
            notes_total: r.notes_total as u32,
            timing: r.timing,
            assists: r.assists,
            score: r.score,
            stars_exact: r.stars_exact,
        }
    }
}
