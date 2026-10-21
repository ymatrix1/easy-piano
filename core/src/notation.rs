//! Our note notation (D3, docs/specs/content-format.md).
//!
//! A bar string holds space-separated tokens:
//! - note or chord: `C4:4`, `C4E4G4:2@135`, `F#4:8.`, `E4:4@3(accent)`
//! - rest: `r:4`
//! - duration: a denominator with optional dots (`4` quarter, `2.` dotted half)
//!   or an explicit fraction of a whole note (`3/8`)
//! - fingering: `@` then one digit 1–5 per pitch, in chord order
//! - directive (zero length): `{chord:"C"}`, `{tie}`

use crate::pitch::{parse_pitch, PitchError};
use std::fmt;

/// Exact fraction of a whole note.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct Dur {
    pub num: u32,
    pub den: u32,
}

fn gcd(a: u32, b: u32) -> u32 {
    if b == 0 { a } else { gcd(b, a % b) }
}

impl Dur {
    pub const ZERO: Dur = Dur { num: 0, den: 1 };

    pub fn new(num: u32, den: u32) -> Dur {
        let g = gcd(num, den).max(1);
        Dur { num: num / g, den: den / g }
    }

    pub fn add(self, o: Dur) -> Dur {
        Dur::new(self.num * o.den + o.num * self.den, self.den * o.den)
    }

    pub fn as_f64(self) -> f64 {
        self.num as f64 / self.den as f64
    }

    /// Length in beats, where one beat is the time signature's denominator note.
    pub fn beats(self, beat_unit: u32) -> f64 {
        self.as_f64() * beat_unit as f64
    }
}

impl fmt::Display for Dur {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}/{}", self.num, self.den)
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum Event {
    Note { pitches: Vec<u8>, dur: Dur, fingers: Vec<u8>, annotation: Option<String> },
    Rest { dur: Dur },
    Directive { name: String, arg: Option<String> },
}

impl Event {
    pub fn dur(&self) -> Dur {
        match self {
            Event::Note { dur, .. } | Event::Rest { dur } => *dur,
            Event::Directive { .. } => Dur::ZERO,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum NotationError {
    MissingDuration(String),
    BadDuration(String),
    BadPitch(String, PitchError),
    BadFinger(String),
    FingerCount { token: String, pitches: usize, fingers: usize },
    UnclosedDirective(String),
}

impl fmt::Display for NotationError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            NotationError::MissingDuration(t) => write!(f, "`{t}`: missing `:duration`"),
            NotationError::BadDuration(t) => write!(f, "`{t}`: bad duration"),
            NotationError::BadPitch(t, e) => write!(f, "`{t}`: bad pitch ({e:?})"),
            NotationError::BadFinger(t) => write!(f, "`{t}`: fingers must be digits 1-5"),
            NotationError::FingerCount { token, pitches, fingers } => {
                write!(f, "`{token}`: {fingers} finger(s) for {pitches} pitch(es)")
            }
            NotationError::UnclosedDirective(t) => write!(f, "`{t}`: unclosed `{{`"),
        }
    }
}

fn parse_dur(s: &str, token: &str) -> Result<Dur, NotationError> {
    let bad = || NotationError::BadDuration(token.to_string());
    if let Some((n, d)) = s.split_once('/') {
        let (n, d): (u32, u32) = (n.parse().map_err(|_| bad())?, d.parse().map_err(|_| bad())?);
        if n == 0 || d == 0 {
            return Err(bad());
        }
        return Ok(Dur::new(n, d));
    }
    let dots = s.chars().rev().take_while(|&c| c == '.').count();
    let den: u32 = s[..s.len() - dots].parse().map_err(|_| bad())?;
    if den == 0 || !den.is_power_of_two() || den > 64 {
        return Err(bad());
    }
    // Each dot adds half of the previous value: total = (2^(d+1) - 1) / (den * 2^d).
    let num = (1u32 << (dots + 1)) - 1;
    Ok(Dur::new(num, den << dots))
}

/// Splits a run of concatenated pitches like `C4E4G4` or `F#4Bb4`.
fn split_pitches(s: &str, token: &str) -> Result<Vec<u8>, NotationError> {
    let mut out = Vec::new();
    let mut rest = s;
    while !rest.is_empty() {
        let mut end = 1;
        let bytes = rest.as_bytes();
        if end < bytes.len() && matches!(bytes[end], b'#' | b'b' | b'n') {
            end += 1;
        }
        while end < bytes.len() && bytes[end].is_ascii_digit() {
            end += 1;
        }
        let p = &rest[..end];
        out.push(parse_pitch(p).map_err(|e| NotationError::BadPitch(token.to_string(), e))?);
        rest = &rest[end..];
    }
    Ok(out)
}

/// Parses one token (note, chord, rest or directive).
pub fn parse_token(token: &str) -> Result<Event, NotationError> {
    if let Some(inner) = token.strip_prefix('{') {
        let inner = inner.strip_suffix('}').ok_or_else(|| NotationError::UnclosedDirective(token.into()))?;
        let (name, arg) = match inner.split_once(':') {
            Some((n, a)) => (n.trim().to_string(), Some(a.trim().to_string())),
            None => (inner.trim().to_string(), None),
        };
        return Ok(Event::Directive { name, arg });
    }
    let (head, tail) = token.split_once(':').ok_or_else(|| NotationError::MissingDuration(token.into()))?;
    // tail = dur [@fingers] [(annotation)]
    let (tail, annotation) = match tail.split_once('(') {
        Some((t, a)) => (t, Some(a.trim_end_matches(')').to_string())),
        None => (tail, None),
    };
    let (dur_s, fingers_s) = match tail.split_once('@') {
        Some((d, f)) => (d, Some(f)),
        None => (tail, None),
    };
    let dur = parse_dur(dur_s, token)?;
    if head == "r" {
        return Ok(Event::Rest { dur });
    }
    let pitches = split_pitches(head, token)?;
    let fingers: Vec<u8> = match fingers_s {
        Some(f) => f
            .chars()
            .map(|c| c.to_digit(10).filter(|d| (1..=5).contains(d)).map(|d| d as u8))
            .collect::<Option<Vec<_>>>()
            .ok_or_else(|| NotationError::BadFinger(token.into()))?,
        None => Vec::new(),
    };
    if !fingers.is_empty() && fingers.len() != pitches.len() {
        return Err(NotationError::FingerCount { token: token.into(), pitches: pitches.len(), fingers: fingers.len() });
    }
    Ok(Event::Note { pitches, dur, fingers, annotation })
}

/// Splits a bar string into tokens; `{...}` directives may contain spaces.
fn tokens(bar: &str) -> Vec<&str> {
    let mut out = Vec::new();
    let (mut start, mut depth) = (None, 0);
    for (i, c) in bar.char_indices() {
        match c {
            '{' => {
                depth += 1;
                start.get_or_insert(i);
            }
            '}' => depth -= 1,
            c if c.is_whitespace() && depth == 0 => {
                if let Some(s) = start.take() {
                    out.push(&bar[s..i]);
                }
            }
            _ => {
                start.get_or_insert(i);
            }
        }
    }
    if let Some(s) = start {
        out.push(&bar[s..]);
    }
    out
}

/// Parses every token of a bar.
pub fn parse_bar(bar: &str) -> Result<Vec<Event>, NotationError> {
    tokens(bar).into_iter().map(parse_token).collect()
}

/// Total length of a bar's events.
pub fn bar_length(events: &[Event]) -> Dur {
    events.iter().fold(Dur::ZERO, |acc, e| acc.add(e.dur()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn durations() {
        assert_eq!(parse_dur("4", "t"), Ok(Dur::new(1, 4)));
        assert_eq!(parse_dur("2.", "t"), Ok(Dur::new(3, 4)));
        assert_eq!(parse_dur("8..", "t"), Ok(Dur::new(7, 32)));
        assert_eq!(parse_dur("3/8", "t"), Ok(Dur::new(3, 8)));
        assert!(parse_dur("3", "t").is_err());
        assert!(parse_dur("0/4", "t").is_err());
    }

    #[test]
    fn chord_with_fingers() {
        assert_eq!(
            parse_token("C4E4G4:2@135"),
            Ok(Event::Note { pitches: vec![60, 64, 67], dur: Dur::new(1, 2), fingers: vec![1, 3, 5], annotation: None })
        );
    }

    #[test]
    fn accidentals_rest_annotation() {
        assert!(matches!(parse_token("F#4Bb4:8"), Ok(Event::Note { ref pitches, .. }) if pitches == &vec![66, 70]));
        assert_eq!(parse_token("r:4"), Ok(Event::Rest { dur: Dur::new(1, 4) }));
        assert!(matches!(parse_token("E4:4@3(accent)"), Ok(Event::Note { annotation: Some(ref a), .. }) if a == "accent"));
    }

    #[test]
    fn tie_directive_is_accepted_and_has_zero_length() {
        // the melody-model converter writes `{tie}` after a note tied into the next one
        let bar = parse_bar("C4:2 D4:2 {tie}").unwrap();
        assert_eq!(bar.len(), 3);
        let total = bar.iter().fold(Dur::ZERO, |a, e| a.add(e.dur()));
        assert_eq!(total, Dur::new(1, 1));
    }

    #[test]
    fn directives_have_zero_length_and_may_hold_spaces() {
        let bar = parse_bar(r#"{chord: "C major"} C4:2 r:2"#).unwrap();
        assert_eq!(bar.len(), 3);
        assert_eq!(bar_length(&bar), Dur::new(1, 1));
    }

    #[test]
    fn errors_name_the_token() {
        assert!(matches!(parse_token("C4"), Err(NotationError::MissingDuration(_))));
        assert!(matches!(parse_token("H4:4"), Err(NotationError::BadPitch(..))));
        assert!(matches!(parse_token("C4E4:4@1"), Err(NotationError::FingerCount { pitches: 2, fingers: 1, .. })));
        assert!(matches!(parse_token("C4:4@6"), Err(NotationError::BadFinger(_))));
    }

    #[test]
    fn beats_follow_time_signature_unit() {
        assert_eq!(Dur::new(1, 4).beats(4), 1.0); // quarter in x/4
        assert_eq!(Dur::new(1, 8).beats(8), 1.0); // eighth in x/8
    }
}
