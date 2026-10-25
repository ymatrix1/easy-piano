//! ABC notation (`.abc`), one tune per file.
//!
//! Supported: header fields `X T C M L Q K V`; voices with `clef=bass` or `bass`
//! (bass voices are the left hand, all others the right); pitches with `^ _ =`
//! accidentals and `' ,` octave marks; note lengths; rests `z x Z`; chords `[...]`;
//! ties `-`; tuplets `(p`; key-signature accidentals reset at bar lines. Grace notes,
//! decorations, chord symbols and lyrics are skipped. Mid-tune M/L/Q/K changes are
//! ignored (only the header values apply).

use super::{
    build_measures, key_alter_for, letter_semitone, measure_beats, merge_ties, midi_pitch,
    sort_notes, Change, Clef, Hand, ImportedNote, ImportedScore, TieNote,
};
use std::collections::HashMap;

/// Per-voice state while reading music.
struct Voice {
    hand: Hand,
    /// Current position in quarter-note beats.
    cursor: f64,
    /// Accidentals written earlier in this bar, keyed by (letter, octave).
    accidentals: HashMap<(char, i32), i32>,
    /// Notes emitted by the last note or chord, for `-` ties.
    last_notes: Vec<usize>,
    /// The next emitted note closes a tie.
    pending_stop: bool,
    /// Active tuplet: (duration factor, notes left).
    tuplet: Option<(f64, u32)>,
}

impl Voice {
    fn new(clef: Clef) -> Voice {
        Voice {
            hand: match clef {
                Clef::Bass => Hand::Left,
                Clef::Treble => Hand::Right,
            },
            cursor: 0.0,
            accidentals: HashMap::new(),
            last_notes: Vec::new(),
            pending_stop: false,
            tuplet: None,
        }
    }
}

struct Parser {
    meter: (u32, u32),
    /// Meter in force at the start of the tune (from `K:`).
    first_meter: (u32, u32),
    /// Meter changes in the body (`M:` lines or `[M:...]`), in order.
    meter_changes: Vec<Change>,
    unit: (u32, u32),
    fifths: i8,
    default_clef: Clef,
    voice_clefs: HashMap<String, Clef>,
    voices: HashMap<String, Voice>,
    current: String,
    raws: Vec<TieNote>,
}

impl Parser {
    fn new() -> Parser {
        Parser {
            meter: (4, 4),
            first_meter: (4, 4),
            meter_changes: Vec::new(),
            unit: (1, 8),
            fifths: 0,
            default_clef: Clef::Treble,
            voice_clefs: HashMap::new(),
            voices: HashMap::new(),
            current: "1".to_string(),
            raws: Vec::new(),
        }
    }

    /// A meter change in the body. Voices are read one after another, so the change
    /// is placed at the furthest voice cursor.
    fn set_meter(&mut self, meter: (u32, u32)) {
        if meter == self.meter {
            return;
        }
        let at = self
            .voices
            .values()
            .map(|v| v.cursor)
            .fold(0.0f64, f64::max);
        self.meter = meter;
        self.meter_changes.push(Change {
            start: at,
            time: meter,
            key_fifths: self.fifths,
        });
    }

    fn clef_for(&self, id: &str) -> Clef {
        self.voice_clefs.get(id).copied().unwrap_or(if id == "1" {
            self.default_clef
        } else {
            Clef::Treble
        })
    }

    fn cur(&mut self) -> &mut Voice {
        let id = self.current.clone();
        let clef = self.clef_for(&id);
        self.voices.entry(id).or_insert_with(|| Voice::new(clef))
    }

    fn define_voice(&mut self, rest: &str) {
        let id = rest.split_whitespace().next().unwrap_or("1").to_string();
        let clef = if rest.to_ascii_lowercase().contains("bass") {
            Clef::Bass
        } else {
            Clef::Treble
        };
        self.voice_clefs.insert(id, clef);
    }

    fn switch_voice(&mut self, rest: &str) {
        self.current = rest.split_whitespace().next().unwrap_or("1").to_string();
        self.cur();
    }

    /// Length of one unit of `n/d` note value, times the tuplet factor for this note.
    fn duration(&mut self, n: u32, d: u32) -> f64 {
        let base = n as f64 / d as f64 * self.unit.0 as f64 / self.unit.1 as f64 * 4.0;
        base * self.take_tuplet()
    }

    fn take_tuplet(&mut self) -> f64 {
        let v = self.cur();
        match v.tuplet {
            Some((factor, left)) if left > 1 => {
                v.tuplet = Some((factor, left - 1));
                factor
            }
            Some((factor, _)) => {
                v.tuplet = None;
                factor
            }
            None => 1.0,
        }
    }

    /// Adds notes at the voice cursor and advances it by `beats`. Empty `midis` is a rest.
    fn emit(&mut self, midis: &[u8], beats: f64) {
        let (hand, start, pending) = {
            let v = self.cur();
            let r = (v.hand, v.cursor, v.pending_stop);
            v.cursor += beats;
            v.pending_stop = false;
            r
        };
        let mut idxs = Vec::new();
        for &midi in midis {
            self.raws.push(TieNote {
                note: ImportedNote {
                    midi,
                    start,
                    beats,
                    hand,
                    articulations: Vec::new(),
                },
                tie_start: false,
                tie_stop: pending,
            });
            idxs.push(self.raws.len() - 1);
        }
        if !midis.is_empty() {
            self.cur().last_notes = idxs;
        } else {
            self.cur().last_notes.clear();
        }
    }

    /// Reads `n/d` after a note or rest; both parts optional.
    fn ratio(c: &[char], i: &mut usize) -> (u32, u32) {
        let num = digits(c, i);
        if c.get(*i) == Some(&'/') {
            let mut slashes = 0u32;
            while c.get(*i) == Some(&'/') {
                slashes += 1;
                *i += 1;
            }
            let den = digits(c, i).unwrap_or(1 << slashes.min(20));
            (num.unwrap_or(1), den)
        } else {
            (num.unwrap_or(1), 1)
        }
    }

    /// Reads an accidental (optional) and a note letter with octave marks.
    fn read_pitch(&mut self, c: &[char], i: &mut usize) -> Option<u8> {
        let mut explicit: Option<i32> = None;
        match c.get(*i) {
            Some('^') => {
                let mut n = 0;
                while c.get(*i) == Some(&'^') {
                    n += 1;
                    *i += 1;
                }
                explicit = Some(n);
            }
            Some('_') => {
                let mut n = 0;
                while c.get(*i) == Some(&'_') {
                    n += 1;
                    *i += 1;
                }
                explicit = Some(-n);
            }
            Some('=') => {
                *i += 1;
                explicit = Some(0);
            }
            _ => {}
        }
        let letter = *c.get(*i)?;
        if !letter.is_ascii_alphabetic() || letter_semitone(letter).is_none() {
            return None;
        }
        *i += 1;
        let mut octave = if letter.is_ascii_uppercase() { 4 } else { 5 };
        loop {
            match c.get(*i) {
                Some('\'') => octave += 1,
                Some(',') => octave -= 1,
                _ => break,
            }
            *i += 1;
        }
        let upper = letter.to_ascii_uppercase();
        let fifths = self.fifths;
        let v = self.cur();
        let alter = match explicit {
            Some(a) => {
                v.accidentals.insert((upper, octave), a);
                a
            }
            None => v
                .accidentals
                .get(&(upper, octave))
                .copied()
                .unwrap_or_else(|| key_alter_for(fifths, upper)),
        };
        midi_pitch(letter_semitone(letter)?, octave, alter)
    }

    fn chord(&mut self, c: &[char], mut i: usize) -> usize {
        let mut midis = Vec::new();
        while i < c.len() && c[i] != ']' {
            if matches!(c[i], '^' | '_' | '=') || c[i].is_ascii_alphabetic() {
                if let Some(m) = self.read_pitch(c, &mut i) {
                    midis.push(m);
                }
            } else {
                i += 1;
            }
        }
        i += 1; // past ']'
        let (n, d) = Parser::ratio(c, &mut i);
        let beats = self.duration(n, d);
        self.emit(&midis, beats);
        i
    }

    fn inline_field(&mut self, content: &str) {
        if let Some(rest) = content.strip_prefix("V:") {
            self.switch_voice(rest);
        } else if let Some(rest) = content.strip_prefix("M:") {
            self.set_meter(parse_meter(rest));
        }
    }

    /// Reads one music line (body text, not a field).
    fn music(&mut self, line: &str) {
        let c: Vec<char> = line.chars().collect();
        let mut i = 0;
        while i < c.len() {
            let ch = c[i];
            match ch {
                '%' => break,
                '"' => {
                    i += 1;
                    while i < c.len() && c[i] != '"' {
                        i += 1;
                    }
                    i += 1;
                }
                '{' => {
                    while i < c.len() && c[i] != '}' {
                        i += 1;
                    }
                    i += 1;
                }
                '!' | '+' => {
                    i += 1;
                    while i < c.len() && c[i] != ch {
                        i += 1;
                    }
                    i += 1;
                }
                '|' | ':' => {
                    self.cur().accidentals.clear();
                    i += 1;
                }
                '[' => {
                    if c.get(i + 1).is_some_and(|x| x.is_ascii_alphabetic())
                        && c.get(i + 2) == Some(&':')
                    {
                        let end = c[i..]
                            .iter()
                            .position(|x| *x == ']')
                            .map_or(c.len(), |p| i + p);
                        let content: String = c[i + 1..end].iter().collect();
                        self.inline_field(&content);
                        i = end + 1;
                    } else {
                        i = self.chord(&c, i + 1);
                    }
                }
                '(' => {
                    i += 1;
                    if c.get(i).is_some_and(|x| x.is_ascii_digit()) {
                        let p = digits(&c, &mut i).unwrap_or(2);
                        let mut q = match p {
                            2 | 4 | 8 => 3,
                            _ => 2,
                        };
                        let mut r = p;
                        if c.get(i) == Some(&':') {
                            i += 1;
                            if let Some(v) = digits(&c, &mut i) {
                                q = v;
                            }
                            if c.get(i) == Some(&':') {
                                i += 1;
                                if let Some(v) = digits(&c, &mut i) {
                                    r = v;
                                }
                            }
                        }
                        if p > 0 {
                            self.cur().tuplet = Some((q as f64 / p as f64, r.max(1)));
                        }
                    }
                }
                '-' => {
                    i += 1;
                    let idxs = self.cur().last_notes.clone();
                    if !idxs.is_empty() {
                        for idx in idxs {
                            self.raws[idx].tie_start = true;
                        }
                        self.cur().pending_stop = true;
                    }
                }
                'z' | 'x' => {
                    i += 1;
                    let (n, d) = Parser::ratio(&c, &mut i);
                    let beats = self.duration(n, d);
                    self.emit(&[], beats);
                }
                'Z' => {
                    i += 1;
                    let count = digits(&c, &mut i).unwrap_or(1);
                    let beats = count as f64 * measure_beats(self.meter);
                    self.emit(&[], beats);
                }
                'y' => {
                    i += 1;
                    let (n, d) = Parser::ratio(&c, &mut i);
                    let beats = self.duration(n, d);
                    self.cur().cursor += beats;
                }
                '^' | '_' | '=' | 'A'..='G' | 'a'..='g' => {
                    if let Some(midi) = self.read_pitch(&c, &mut i) {
                        let (n, d) = Parser::ratio(&c, &mut i);
                        let beats = self.duration(n, d);
                        self.emit(&[midi], beats);
                    }
                }
                _ => i += 1,
            }
        }
    }
}

fn digits(c: &[char], i: &mut usize) -> Option<u32> {
    let start = *i;
    while c.get(*i).is_some_and(|x| x.is_ascii_digit()) {
        *i += 1;
    }
    if *i == start {
        return None;
    }
    c[start..*i].iter().collect::<String>().parse().ok()
}

/// `X:`-style header or voice field: (uppercase letter, value).
fn field_of(line: &str) -> Option<(char, &str)> {
    let mut it = line.chars();
    let k = it.next()?;
    if !k.is_ascii_alphabetic() || it.next() != Some(':') {
        return None;
    }
    Some((k.to_ascii_uppercase(), &line[2..]))
}

fn parse_fraction(s: &str) -> Option<(u32, u32)> {
    let (n, d) = s.trim().split_once('/')?;
    let (n, d) = (n.trim().parse().ok()?, d.trim().parse().ok()?);
    (n > 0 && d > 0).then_some((n, d))
}

fn parse_meter(v: &str) -> (u32, u32) {
    let v = v.trim();
    match v {
        "C" | "none" => (4, 4),
        "C|" => (2, 2),
        _ => parse_fraction(v).unwrap_or((4, 4)),
    }
}

/// Quarter-note tempo from `Q:` (`Q:1/4=120`, `Q:120`, `Q:"Allegro" 1/4=100`).
fn parse_tempo(v: &str) -> Option<f64> {
    let mut cleaned = String::new();
    let mut in_quote = false;
    for ch in v.chars() {
        match ch {
            '"' => in_quote = !in_quote,
            _ if !in_quote => cleaned.push(ch),
            _ => {}
        }
    }
    let cleaned = cleaned.trim();
    match cleaned.split_once('=') {
        Some((unit, bpm)) => {
            let bpm: f64 = bpm.trim().parse().ok()?;
            let (n, d) = unit
                .split_whitespace()
                .last()
                .and_then(parse_fraction)
                .unwrap_or((1, 4));
            Some(bpm * n as f64 / d as f64 * 4.0)
        }
        None => cleaned.parse().ok(),
    }
}

/// Key signature from `K:` text: returns (fifths, clef if given).
fn parse_key(v: &str) -> (i8, Option<Clef>) {
    let v = v.trim();
    let lower = v.to_ascii_lowercase();
    let clef = if lower.contains("bass") {
        Some(Clef::Bass)
    } else if lower.contains("treble") {
        Some(Clef::Treble)
    } else {
        None
    };
    if lower.starts_with("none") {
        return (0, clef);
    }
    let chars: Vec<char> = v.chars().collect();
    let Some(&letter) = chars.first() else {
        return (0, clef);
    };
    if !"ABCDEFGabcdefg".contains(letter) {
        return (0, clef);
    }
    let mut tonic = letter.to_ascii_uppercase().to_string();
    let mut i = 1;
    while matches!(chars.get(i), Some(&'#') | Some(&'b')) {
        tonic.push(chars[i]);
        i += 1;
    }
    let rest: String = chars[i..].iter().collect();
    let rest = rest.trim_start().to_ascii_lowercase();
    let minor = rest.starts_with('m') && !rest.starts_with("maj");
    let major = super::major_tonic_fifths(&tonic).unwrap_or(0);
    let fifths = if minor { major - 3 } else { major };
    let fifths = match fifths {
        f if f < -7 => f + 12,
        f if f > 7 => f - 12,
        f => f,
    };
    (fifths, clef)
}

/// Parses one ABC tune from `text`.
pub fn parse(text: &str) -> Result<ImportedScore, String> {
    let mut p = Parser::new();
    let mut title = String::new();
    let mut composer = String::new();
    let mut tempo: Option<f64> = None;
    let mut meter: Option<(u32, u32)> = None;
    let mut unit: Option<(u32, u32)> = None;
    let mut in_body = false;
    let mut key_seen = false;
    let mut body_started = false;

    for raw in text.lines() {
        let line = raw.trim();
        if line.is_empty() {
            if body_started {
                break;
            }
            continue;
        }
        if line.starts_with('%') {
            continue;
        }
        let field = field_of(line);
        if !in_body {
            match field {
                Some(('T', v)) if title.is_empty() => title = v.trim().to_string(),
                Some(('C', v)) if composer.is_empty() => composer = v.trim().to_string(),
                Some(('M', v)) => meter = Some(parse_meter(v)),
                Some(('L', v)) => unit = parse_fraction(v),
                Some(('Q', v)) => tempo = parse_tempo(v),
                Some(('V', v)) => p.define_voice(v),
                Some(('K', v)) => {
                    let (fifths, clef) = parse_key(v);
                    p.fifths = fifths;
                    if let Some(c) = clef {
                        p.default_clef = c;
                    }
                    let m = meter.unwrap_or((4, 4));
                    p.meter = m;
                    p.first_meter = m;
                    // Default unit: 1/16 for slow meters (below 3/4), else 1/8.
                    p.unit = unit.unwrap_or(if (m.0 as f64 / m.1 as f64) < 0.75 {
                        (1, 16)
                    } else {
                        (1, 8)
                    });
                    key_seen = true;
                    in_body = true;
                }
                _ => {}
            }
        } else {
            match field {
                Some(('V', v)) => {
                    // Voices may also be defined with a clef inside the body.
                    let lower = v.to_ascii_lowercase();
                    if lower.contains("clef") || lower.contains("bass") || lower.contains("treble")
                    {
                        p.define_voice(v);
                    }
                    p.switch_voice(v);
                }
                Some(('X', _)) if body_started => break,
                Some(('M', v)) => p.set_meter(parse_meter(v)),
                Some(_) => {}
                None => {
                    body_started = true;
                    p.music(line);
                }
            }
        }
    }

    if !key_seen {
        return Err("abc: missing K: field".into());
    }
    if p.raws.is_empty() {
        return Err("abc: no notes found".into());
    }
    let end = p.voices.values().map(|v| v.cursor).fold(0.0f64, f64::max);
    let mut changes = vec![Change {
        start: 0.0,
        time: p.first_meter,
        key_fifths: p.fifths,
    }];
    changes.append(&mut p.meter_changes);
    let measures = build_measures(&changes, end);
    let mut notes = merge_ties(p.raws);
    sort_notes(&mut notes);

    Ok(ImportedScore {
        title,
        composer,
        tempo_bpm: tempo,
        right_clef: Clef::Treble,
        left_clef: Clef::Bass,
        measures,
        notes,
        expression: Vec::new(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn approx(a: f64, b: f64) -> bool {
        (a - b).abs() < 1e-6
    }

    #[test]
    fn reads_header_and_key_accidentals() {
        let abc =
            "X:1\nT:Test Tune\nC:Anon.\nM:3/4\nL:1/8\nQ:1/4=90\nK:G\n|: G2 F2 A2 | B2 z2 ^c2 :|\n";
        let s = parse(abc).unwrap();
        assert_eq!(s.title, "Test Tune");
        assert_eq!(s.composer, "Anon.");
        assert_eq!(s.tempo_bpm, Some(90.0));
        assert_eq!(s.measures.len(), 2);
        assert_eq!(s.measures[0].time, (3, 4));
        assert_eq!(s.measures[0].key_fifths, 1);
        assert_eq!(s.measures[1].start, 3.0);
    }

    #[test]
    fn pitches_timing_and_rests() {
        let abc = "M:3/4\nL:1/8\nK:G\nG2 F2 A2 | B2 z2 ^c2 |\n";
        let s = parse(abc).unwrap();
        let got: Vec<(u8, f64)> = s.notes.iter().map(|n| (n.midi, n.start)).collect();
        // G4, F#4 (key of G), A4, B4, C#5 (explicit sharp). The rest is at beat 4.
        assert_eq!(
            got,
            vec![(67, 0.0), (66, 1.0), (69, 2.0), (71, 3.0), (73, 5.0)]
        );
        assert!(s.notes.iter().all(|n| n.hand == Hand::Right));
        assert!(s.notes.iter().all(|n| approx(n.beats, 1.0) || n.midi == 73));
    }

    #[test]
    fn bass_voice_goes_to_left_hand() {
        let abc =
            "M:4/4\nL:1/4\nK:C\nV:1 clef=treble\nV:2 clef=bass\nV:1\nC D E F |\nV:2\nC,, G,, |\n";
        let s = parse(abc).unwrap();
        let rh: Vec<u8> = s
            .notes
            .iter()
            .filter(|n| n.hand == Hand::Right)
            .map(|n| n.midi)
            .collect();
        let lh: Vec<(u8, f64)> = s
            .notes
            .iter()
            .filter(|n| n.hand == Hand::Left)
            .map(|n| (n.midi, n.start))
            .collect();
        assert_eq!(rh, vec![60, 62, 64, 65]);
        // C,, = C2 = 36, G,, = G2 = 43.
        assert_eq!(lh, vec![(36, 0.0), (43, 1.0)]);
        assert_eq!(s.measures.len(), 1);
    }

    #[test]
    fn ties_merge_across_the_barline() {
        let abc = "M:4/4\nL:1/4\nK:C\nC4-C4 |\n";
        let s = parse(abc).unwrap();
        assert_eq!(s.notes.len(), 1);
        assert!(approx(s.notes[0].beats, 8.0));
        assert_eq!(s.measures.len(), 2);
    }

    #[test]
    fn triplet_applies_tuplet_factor() {
        let abc = "M:2/4\nL:1/8\nK:C\n(3abc |\n";
        let s = parse(abc).unwrap();
        assert_eq!(s.notes.len(), 3);
        assert!(approx(s.notes[1].start, 1.0 / 3.0));
        assert!(approx(s.notes[2].start, 2.0 / 3.0));
        assert!(s.notes.iter().all(|n| approx(n.beats, 1.0 / 3.0)));
    }

    #[test]
    fn key_signature_minor_and_flats() {
        assert_eq!(parse_key("Am"), (0, None));
        assert_eq!(parse_key("Bb"), (-2, None));
        assert_eq!(parse_key("D major"), (2, None));
        assert_eq!(parse_key("Em clef=bass"), (1, Some(Clef::Bass)));
        assert_eq!(parse_key("none"), (0, None));
    }

    #[test]
    fn flat_key_lowers_unmarked_notes() {
        let abc = "M:4/4\nL:1/4\nK:Bb\nB c |\n";
        let s = parse(abc).unwrap();
        assert_eq!(s.notes[0].midi, 70); // B4 flattened by the key
        assert_eq!(s.notes[1].midi, 72); // c5 not in Bb's flats
    }

    #[test]
    fn meter_change_in_the_body_starts_a_new_bar_length() {
        let abc = "M:3/4\nL:1/4\nK:C\nCDE|\nM:4/4\nCDEF|\n";
        let s = parse(abc).unwrap();
        assert_eq!(s.measures.len(), 2);
        assert_eq!(s.measures[0].time, (3, 4));
        assert_eq!(s.measures[1].time, (4, 4));
        assert!(approx(s.measures[1].start, 3.0));
        assert!(approx(s.measures[1].beats, 4.0));
    }

    #[test]
    fn inline_meter_change_counts_like_a_body_line() {
        let abc = "M:3/4\nL:1/4\nK:C\nCDE [M:4/4] CDEF|\n";
        let s = parse(abc).unwrap();
        assert_eq!(s.measures.len(), 2);
        assert_eq!(s.measures[1].time, (4, 4));
        assert!(approx(s.measures[1].start, 3.0));
    }

    #[test]
    fn grace_notes_take_no_time_and_are_not_imported() {
        let abc = "M:4/4\nL:1/4\nK:C\n{g}CDEF|\n";
        let s = parse(abc).unwrap();
        assert_eq!(s.notes.len(), 4);
        assert!(!s.notes.iter().any(|n| n.midi == 67)); // the grace G4 is dropped
        assert!(approx(s.notes[0].start, 0.0));
        assert!(approx(s.notes[3].start, 3.0));
        assert_eq!(s.measures.len(), 1);
    }

    #[test]
    fn requires_key_field_and_notes() {
        assert!(parse("M:4/4\nL:1/4\nC D |\n").is_err());
        assert!(parse("M:4/4\nL:1/4\nK:C\n|: |\n").is_err());
    }
}
