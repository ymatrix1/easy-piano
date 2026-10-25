//! Score import (docs/specs/score-import-and-page-view.md §2.1).
//!
//! Each format parser turns its bytes into an [`ImportedScore`]: piano notes with
//! absolute start and length in quarter-note beats, a hand per note, and the
//! measure grid with time and key signatures. Pure functions, no I/O.

pub mod abc;
pub mod lilypond;
pub mod midi;
pub mod musicxml;
pub mod song;

/// Which hand a note is played by.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Hand {
    Right,
    Left,
}

/// Clef of a staff.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Clef {
    Treble,
    Bass,
}

/// One sounding piano note.
#[derive(Debug, Clone, PartialEq)]
pub struct ImportedNote {
    /// MIDI note number, 60 = middle C.
    pub midi: u8,
    /// Start in quarter-note beats from the beginning of the score.
    pub start: f64,
    /// Length in quarter-note beats.
    pub beats: f64,
    pub hand: Hand,
    /// Articulations attached to this note in the source score.
    pub articulations: Vec<Articulation>,
}

/// Note-level articulation preserved by score import.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Articulation {
    Staccato,
    Accent,
    Tenuto,
    Fermata,
}

/// Expression marks positioned on the imported score's quarter-note timeline.
#[derive(Debug, Clone, PartialEq)]
pub enum ExpressionMark {
    Dynamic {
        beat: f64,
        value: String,
    },
    Hairpin {
        start: f64,
        end: f64,
        crescendo: bool,
    },
    Slur {
        start: f64,
        end: f64,
    },
    Pedal {
        start: f64,
        end: f64,
    },
}

/// One bar of the score.
#[derive(Debug, Clone, PartialEq)]
pub struct ImportedMeasure {
    /// Bar number as written in the source (1-based for generated grids).
    pub number: u32,
    /// Start in quarter-note beats.
    pub start: f64,
    /// Length in quarter-note beats.
    pub beats: f64,
    /// (beats per bar, beat unit), e.g. (3, 4).
    pub time: (u32, u32),
    /// Key signature as sharps (positive) or flats (negative).
    pub key_fifths: i8,
}

/// A parsed score, format independent.
#[derive(Debug, Clone, PartialEq)]
pub struct ImportedScore {
    pub title: String,
    pub composer: String,
    pub tempo_bpm: Option<f64>,
    /// Clef of the right-hand staff at the start of the score.
    pub right_clef: Clef,
    /// Clef of the left-hand staff at the start of the score.
    pub left_clef: Clef,
    pub measures: Vec<ImportedMeasure>,
    /// Sorted by start, then pitch.
    pub notes: Vec<ImportedNote>,
    /// Expression marks retained by parsers that support them (currently MusicXML).
    pub expression: Vec<ExpressionMark>,
}

/// Recognised input formats, chosen by file extension.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Format {
    MusicXml,
    CompressedMusicXml,
    Midi,
    Abc,
    LilyPond,
}

/// Maps a file name to its import format, or `None` if unsupported.
pub fn detect_format(file_name: &str) -> Option<Format> {
    let ext = file_name.rsplit_once('.')?.1.to_ascii_lowercase();
    match ext.as_str() {
        "xml" | "musicxml" => Some(Format::MusicXml),
        "mxl" => Some(Format::CompressedMusicXml),
        "mid" | "midi" => Some(Format::Midi),
        "abc" => Some(Format::Abc),
        "ly" => Some(Format::LilyPond),
        _ => None,
    }
}

/// Parses `data` according to the extension of `file_name`.
pub fn import(file_name: &str, data: &[u8]) -> Result<ImportedScore, String> {
    match detect_format(file_name).ok_or_else(|| format!("unsupported file: {file_name}"))? {
        Format::MusicXml => musicxml::parse(data),
        Format::CompressedMusicXml => musicxml::parse_compressed(data),
        Format::Midi => midi::parse(data),
        Format::Abc => {
            abc::parse(std::str::from_utf8(data).map_err(|e| format!("abc utf-8: {e}"))?)
        }
        Format::LilyPond => {
            lilypond::parse(std::str::from_utf8(data).map_err(|e| format!("ly utf-8: {e}"))?)
        }
    }
}

/// Length of a bar in quarter-note beats.
pub fn measure_beats(time: (u32, u32)) -> f64 {
    time.0 as f64 * 4.0 / time.1 as f64
}

/// A time or key change at a given beat.
#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) struct Change {
    pub start: f64,
    pub time: (u32, u32),
    pub key_fifths: i8,
}

/// Lays out consecutive bars from beat 0 until `end` is covered. `changes` must be
/// sorted by start and begin at 0.
pub(crate) fn build_measures(changes: &[Change], end: f64) -> Vec<ImportedMeasure> {
    let mut out = Vec::new();
    let mut cur = 0.0;
    let mut idx = 0;
    while cur < end - 1e-9 || out.is_empty() {
        while idx + 1 < changes.len() && changes[idx + 1].start <= cur + 1e-9 {
            idx += 1;
        }
        let c = changes.get(idx).copied().unwrap_or(Change {
            start: 0.0,
            time: (4, 4),
            key_fifths: 0,
        });
        let beats = measure_beats(c.time);
        out.push(ImportedMeasure {
            number: out.len() as u32 + 1,
            start: cur,
            beats,
            time: c.time,
            key_fifths: c.key_fifths,
        });
        cur += beats;
    }
    out
}

/// A note as read from the source, plus its tie flags.
pub(crate) struct TieNote {
    pub note: ImportedNote,
    pub tie_start: bool,
    pub tie_stop: bool,
}

/// Joins tied notes (same hand and pitch, end meets start) into single notes.
pub(crate) fn merge_ties(mut raws: Vec<TieNote>) -> Vec<ImportedNote> {
    raws.sort_by(|a, b| {
        a.note
            .start
            .partial_cmp(&b.note.start)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    let mut out: Vec<ImportedNote> = Vec::new();
    let mut open: std::collections::HashMap<(Hand, u8), usize> = std::collections::HashMap::new();
    for r in raws {
        let key = (r.note.hand, r.note.midi);
        if r.tie_stop {
            if let Some(&i) = open.get(&key) {
                if (out[i].start + out[i].beats - r.note.start).abs() < 1e-6 {
                    out[i].beats += r.note.beats;
                    if !r.tie_start {
                        open.remove(&key);
                    }
                    continue;
                }
            }
        }
        let idx = out.len();
        out.push(r.note);
        if r.tie_start {
            open.insert(key, idx);
        } else {
            open.remove(&key);
        }
    }
    out
}

/// Sorts notes into the canonical order.
pub(crate) fn sort_notes(notes: &mut [ImportedNote]) {
    notes.sort_by(|a, b| {
        a.start
            .partial_cmp(&b.start)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then(a.midi.cmp(&b.midi))
    });
}

/// Semitone of a diatonic letter `a`..`g` within the octave, C = 0.
pub(crate) fn letter_semitone(letter: char) -> Option<i32> {
    Some(match letter.to_ascii_lowercase() {
        'c' => 0,
        'd' => 2,
        'e' => 4,
        'f' => 5,
        'g' => 7,
        'a' => 9,
        'b' => 11,
        _ => return None,
    })
}

/// Number of sharps (positive) or flats (negative) for a major key tonic
/// (`C`, `G`, `F#`, `Bb`, ...). Returns `None` for unknown tonics.
pub(crate) fn major_tonic_fifths(tonic: &str) -> Option<i8> {
    let mut chars = tonic.chars();
    let letter = chars.next()?;
    let base = match letter.to_ascii_uppercase() {
        'C' => 0,
        'G' => 1,
        'D' => 2,
        'A' => 3,
        'E' => 4,
        'B' => 5,
        'F' => -1,
        _ => return None,
    };
    let mut acc = 0i8;
    for c in chars {
        match c {
            '#' | '♯' => acc += 1,
            'b' | '♭' => acc -= 1,
            _ => return None,
        }
    }
    // Each sharp adds 7 fifths, each flat subtracts 7.
    let fifths = base + acc * 7;
    // Keep within the usual range by folding the circle of fifths.
    Some(match fifths {
        f if f > 7 => f - 12,
        f if f < -7 => f + 12,
        f => f,
    })
}

/// Alteration (+1 sharp, -1 flat, 0) that a key signature applies to `letter` (A-G).
pub(crate) fn key_alter_for(fifths: i8, letter: char) -> i32 {
    const SHARPS: &str = "FCGDAEB";
    const FLATS: &str = "BEADGCF";
    if fifths > 0 {
        if let Some(pos) = SHARPS.find(letter) {
            if pos < fifths as usize {
                return 1;
            }
        }
    }
    if fifths < 0 {
        if let Some(pos) = FLATS.find(letter) {
            if pos < fifths.unsigned_abs() as usize {
                return -1;
            }
        }
    }
    0
}

/// MIDI pitch for a letter, octave (scientific notation, C4 = 60) and accidental offset.
pub(crate) fn midi_pitch(letter_semi: i32, octave: i32, alter: i32) -> Option<u8> {
    let v = (octave + 1) * 12 + letter_semi + alter;
    u8::try_from(v).ok().filter(|p| *p <= 127)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_formats_by_extension() {
        assert_eq!(detect_format("a.musicxml"), Some(Format::MusicXml));
        assert_eq!(detect_format("a.MXL"), Some(Format::CompressedMusicXml));
        assert_eq!(detect_format("a.midi"), Some(Format::Midi));
        assert_eq!(detect_format("a.abc"), Some(Format::Abc));
        assert_eq!(detect_format("a.ly"), Some(Format::LilyPond));
        assert_eq!(detect_format("a.pdf"), None);
        assert_eq!(detect_format("noext"), None);
    }

    #[test]
    fn major_tonic_key_signatures() {
        assert_eq!(major_tonic_fifths("C"), Some(0));
        assert_eq!(major_tonic_fifths("G"), Some(1));
        assert_eq!(major_tonic_fifths("F#"), Some(6));
        assert_eq!(major_tonic_fifths("C#"), Some(7));
        assert_eq!(major_tonic_fifths("G#"), Some(-4)); // 8 sharps folded to 4 flats (Ab)
        assert_eq!(major_tonic_fifths("F"), Some(-1));
        assert_eq!(major_tonic_fifths("Bb"), Some(-2));
        assert_eq!(major_tonic_fifths("Eb"), Some(-3));
        assert_eq!(major_tonic_fifths("Xb"), None);
    }

    #[test]
    fn midi_pitch_uses_c4_60() {
        assert_eq!(midi_pitch(0, 4, 0), Some(60));
        assert_eq!(midi_pitch(9, 3, 0), Some(57));
        assert_eq!(midi_pitch(0, 4, 1), Some(61));
    }

    #[test]
    fn build_measures_follows_changes() {
        let changes = [
            Change {
                start: 0.0,
                time: (4, 4),
                key_fifths: 0,
            },
            Change {
                start: 8.0,
                time: (3, 4),
                key_fifths: 1,
            },
        ];
        let m = build_measures(&changes, 14.0);
        assert_eq!(m.len(), 4);
        assert_eq!(m[0].time, (4, 4));
        assert_eq!(m[2].time, (3, 4));
        assert_eq!(m[2].key_fifths, 1);
        assert_eq!(m[3].start, 11.0);
    }
}
