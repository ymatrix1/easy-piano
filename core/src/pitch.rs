//! Pitch tokens like `C4`, `F#3`, `Bb5` <-> MIDI note numbers (C4 = 60).

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PitchError {
    Empty,
    BadLetter(char),
    BadOctave(String),
    OutOfRange(i32),
}

/// Parses a pitch token (`[A-G][#|b|n]?octave`) into a MIDI note number.
pub fn parse_pitch(token: &str) -> Result<u8, PitchError> {
    let mut chars = token.chars();
    let letter = chars.next().ok_or(PitchError::Empty)?;
    let base: i32 = match letter {
        'C' => 0,
        'D' => 2,
        'E' => 4,
        'F' => 5,
        'G' => 7,
        'A' => 9,
        'B' => 11,
        other => return Err(PitchError::BadLetter(other)),
    };
    let rest = chars.as_str();
    let (shift, octave_str) = match rest.chars().next() {
        Some('#') => (1, &rest[1..]),
        Some('b') => (-1, &rest[1..]),
        Some('n') => (0, &rest[1..]),
        _ => (0, rest),
    };
    let octave: i32 = octave_str
        .parse()
        .map_err(|_| PitchError::BadOctave(octave_str.to_string()))?;
    let midi = (octave + 1) * 12 + base + shift;
    if !(0..=127).contains(&midi) {
        return Err(PitchError::OutOfRange(midi));
    }
    Ok(midi as u8)
}

/// Spells a MIDI note with sharps (`C#4`).
pub fn pitch_name(midi: u8) -> String {
    const NAMES: [&str; 12] = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
    format!("{}{}", NAMES[(midi % 12) as usize], midi as i32 / 12 - 1)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn middle_c_is_60() {
        assert_eq!(parse_pitch("C4"), Ok(60));
    }

    #[test]
    fn accidentals() {
        assert_eq!(parse_pitch("F#3"), Ok(54));
        assert_eq!(parse_pitch("Bb5"), Ok(82));
        assert_eq!(parse_pitch("En4"), Ok(64));
        assert_eq!(parse_pitch("Cb4"), Ok(59));
    }

    #[test]
    fn piano_range() {
        assert_eq!(parse_pitch("A0"), Ok(21));
        assert_eq!(parse_pitch("C8"), Ok(108));
        assert_eq!(parse_pitch("G9"), Ok(127));
    }

    #[test]
    fn errors() {
        assert_eq!(parse_pitch(""), Err(PitchError::Empty));
        assert_eq!(parse_pitch("H4"), Err(PitchError::BadLetter('H')));
        assert!(matches!(parse_pitch("C"), Err(PitchError::BadOctave(_))));
        assert!(matches!(parse_pitch("G#9"), Err(PitchError::OutOfRange(128))));
    }

    #[test]
    fn round_trip_names() {
        for m in 21..=108u8 {
            assert_eq!(parse_pitch(&pitch_name(m)), Ok(m));
        }
    }
}
