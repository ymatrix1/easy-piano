//! LilyPond subset (`.ly`) for piano scores.
//!
//! Supported: `\header { title composer }`, `\score`, `\new Staff` / `\new PianoStaff`
//! (other `\new` contexts are dropped; `\new Lyrics` and `\new ChordNames` are
//! skipped with their content), `<< >>` simultaneous music (each branch starts at the
//! same time, so `\\` voices work), `{ }` blocks, `\relative`, absolute pitches,
//! pitch names with `is`/`es` accidentals and `'`/`,` marks, durations with dots,
//! rests `r`/`R`, spacers `s`, chords `< >`, ties `~`, `\clef`, `\key`, `\time`,
//! `\tempo`, `\repeat unfold`, `\times`. Anything else is ignored.
//!
//! Hands: a staff with an explicit `\clef bass` is the left hand; otherwise the first
//! staff is the right hand and later staves the left hand.

use std::collections::HashMap;

use super::{
    build_measures, key_alter_for, letter_semitone, major_tonic_fifths, merge_ties, midi_pitch,
    sort_notes, Change, Clef, Hand, ImportedNote, ImportedScore, TieNote,
};

#[derive(Debug, Clone, PartialEq)]
enum Tok {
    Open,
    Close,
    SimOpen,
    SimClose,
    ChordOpen,
    ChordClose,
    Tie,
    Eq,
    Sep,
    Word(String),
    Cmd(String),
    Str(String),
}

fn is_sep(ch: char) -> bool {
    ch.is_whitespace()
        || matches!(
            ch,
            '{' | '}' | '<' | '>' | '~' | '=' | '"' | '\\' | '%' | '(' | ')' | '[' | ']' | '|'
        )
}

fn lex(src: &str) -> Vec<Tok> {
    let c: Vec<char> = src.chars().collect();
    let mut toks = Vec::new();
    let mut i = 0;
    while i < c.len() {
        let ch = c[i];
        match ch {
            '%' => {
                if c.get(i + 1) == Some(&'{') {
                    i += 2;
                    while i + 1 < c.len() && !(c[i] == '%' && c[i + 1] == '}') {
                        i += 1;
                    }
                    i += 2;
                } else {
                    while i < c.len() && c[i] != '\n' {
                        i += 1;
                    }
                }
            }
            '{' => {
                toks.push(Tok::Open);
                i += 1;
            }
            '}' => {
                toks.push(Tok::Close);
                i += 1;
            }
            '<' => {
                if c.get(i + 1) == Some(&'<') {
                    toks.push(Tok::SimOpen);
                    i += 2;
                } else {
                    toks.push(Tok::ChordOpen);
                    i += 1;
                }
            }
            '>' => {
                if c.get(i + 1) == Some(&'>') {
                    toks.push(Tok::SimClose);
                    i += 2;
                } else {
                    toks.push(Tok::ChordClose);
                    i += 1;
                }
            }
            '~' => {
                toks.push(Tok::Tie);
                i += 1;
            }
            '=' => {
                toks.push(Tok::Eq);
                i += 1;
            }
            '"' => {
                i += 1;
                let s = i;
                while i < c.len() && c[i] != '"' {
                    i += 1;
                }
                toks.push(Tok::Str(c[s..i].iter().collect()));
                i += 1;
            }
            '\\' => {
                if c.get(i + 1) == Some(&'\\') {
                    toks.push(Tok::Sep);
                    i += 2;
                } else {
                    i += 1;
                    let s = i;
                    while i < c.len() && c[i].is_ascii_alphabetic() {
                        i += 1;
                    }
                    toks.push(Tok::Cmd(c[s..i].iter().collect()));
                }
            }
            _ if is_sep(ch) => i += 1,
            _ => {
                let s = i;
                while i < c.len() && !is_sep(c[i]) {
                    i += 1;
                }
                let w: String = c[s..i].iter().collect();
                // Articulations and scheme/markup fragments are not music we use.
                if !w.starts_with(['-', '^', '_', '#', '$', '.']) {
                    toks.push(Tok::Word(w));
                }
            }
        }
    }
    toks
}

#[derive(Debug, Clone, Copy, PartialEq)]
struct Dur {
    n: u32,
    dots: u32,
}

/// Pitch of a note name in semitones, for `\transpose`: `c` is C3 (=36), `c'` is C4.
fn pitch_value(n: &NoteTok) -> i32 {
    36 + 12 * n.marks + letter_semitone(LETTERS[n.letter]).unwrap_or(0) + n.alter.unwrap_or(0)
}

fn dur_beats(d: Dur) -> f64 {
    4.0 / d.n as f64 * (2.0 - 0.5f64.powi(d.dots as i32))
}

#[derive(Debug, Clone, PartialEq)]
struct NoteTok {
    /// Index into "cdefgab".
    letter: usize,
    /// Explicit accidental, `None` when the name has none (key applies).
    alter: Option<i32>,
    /// Octave marks: +1 per `'`, -1 per `,`.
    marks: i32,
    dur: Option<Dur>,
}

#[derive(Debug, Clone, PartialEq)]
enum Expr {
    Block(Vec<Expr>),
    Simul(Vec<Expr>),
    Staff(Box<Expr>),
    /// Reference (letter index, scientific octave) and body.
    Relative(Option<(usize, i32)>, Box<Expr>),
    Times(f64, Box<Expr>),
    Repeat(u32, Box<Expr>),
    Note(NoteTok),
    Chord(Vec<NoteTok>, Option<Dur>),
    Rest {
        dur: Option<Dur>,
        spacer: bool,
    },
    Tie,
    /// `\transpose from to { }`: shift by this many semitones.
    Transpose(i32, Box<Expr>),
    Clef(Clef),
    Key(i8),
    Time((u32, u32)),
    Tempo(f64),
}

fn parse_dur_word(w: &str) -> Option<Dur> {
    let digits: String = w.chars().take_while(|c| c.is_ascii_digit()).collect();
    let rest = &w[digits.len()..];
    if digits.is_empty() || !rest.chars().all(|c| c == '.') {
        return None;
    }
    let n: u32 = digits.parse().ok().filter(|n| *n > 0)?;
    Some(Dur {
        n,
        dots: rest.len() as u32,
    })
}

/// Parses a pitch name such as `c`, `fis'`, `bes,8.`.
fn parse_note_word(w: &str) -> Option<NoteTok> {
    let letter_char = w.chars().next()?;
    let letter = "cdefgab".find(letter_char)?;
    let mut rest = &w[1..];
    let mut alter = None;
    let suffixes: [(&str, i32); 6] = [
        ("isis", 2),
        ("eses", -2),
        ("ses", -2),
        ("is", 1),
        ("es", -1),
        ("s", -1),
    ];
    for (suf, val) in suffixes {
        if rest.starts_with(suf) {
            if suf == "s" && !"ae".contains(letter_char) {
                continue;
            }
            if suf == "ses" && !"ae".contains(letter_char) {
                continue;
            }
            alter = Some(val);
            rest = &rest[suf.len()..];
            break;
        }
    }
    // Cautionary (`!`) and optional (`?`) accidentals do not change the pitch.
    rest = rest.trim_start_matches(['!', '?']);
    let mut marks = 0;
    loop {
        match rest.chars().next() {
            Some('\'') => marks += 1,
            Some(',') => marks -= 1,
            _ => break,
        }
        rest = &rest[1..];
    }
    let dur = if rest.is_empty() {
        None
    } else {
        Some(parse_dur_word(rest)?)
    };
    Some(NoteTok {
        letter,
        alter,
        marks,
        dur,
    })
}

fn parse_fraction(w: &str) -> Option<(u32, u32)> {
    let (n, d) = w.split_once('/')?;
    let (n, d): (u32, u32) = (n.parse().ok()?, d.parse().ok()?);
    (n > 0 && d > 0).then_some((n, d))
}

/// Key signature fifths for a tonic word such as `g`, `bes`, `fis` and a mode.
fn key_fifths(tonic: &str, minor: bool) -> i8 {
    let mut chars = tonic.chars();
    let Some(letter) = chars.next() else {
        return 0;
    };
    if !"cdefgab".contains(letter) {
        return 0;
    }
    let mut name = letter.to_ascii_uppercase().to_string();
    let mut rest = chars.as_str();
    loop {
        if rest.starts_with("isis") {
            name.push_str("##");
            rest = &rest[4..];
        } else if rest.starts_with("is") {
            name.push('#');
            rest = &rest[2..];
        } else if rest.starts_with("eses") {
            name.push_str("bb");
            rest = &rest[4..];
        } else if rest.starts_with("es") {
            name.push('b');
            rest = &rest[2..];
        } else if rest == "s" && "ae".contains(letter) {
            name.push('b');
            rest = "";
        } else {
            break;
        }
    }
    if !rest.is_empty() {
        return 0;
    }
    let major = major_tonic_fifths(&name).unwrap_or(0);
    let f = if minor { major - 3 } else { major };
    match f {
        f if f < -7 => f + 12,
        f if f > 7 => f - 12,
        f => f,
    }
}

struct Parser<'a> {
    t: &'a [Tok],
    pos: usize,
    title: String,
    composer: String,
    /// Music variables (`right = { ... }`), used as `\right`.
    vars: HashMap<String, Expr>,
}

impl Parser<'_> {
    fn next_word(&mut self) -> Option<String> {
        match self.t.get(self.pos) {
            Some(Tok::Word(w)) => {
                self.pos += 1;
                Some(w.clone())
            }
            _ => None,
        }
    }

    /// Parses expressions until `close` (consumed) or end of input.
    fn until(&mut self, close: &Tok) -> Vec<Expr> {
        let mut out = Vec::new();
        loop {
            match self.t.get(self.pos) {
                None => break,
                Some(t) if t == close => {
                    self.pos += 1;
                    break;
                }
                _ => {
                    let before = self.pos;
                    if let Some(e) = self.expr() {
                        out.push(e);
                    }
                    if self.pos == before {
                        self.pos += 1;
                    }
                }
            }
        }
        out
    }

    fn header(&mut self) {
        // Current token is `{` of \header.
        self.pos += 1;
        while let Some(t) = self.t.get(self.pos).cloned() {
            match t {
                Tok::Close => {
                    self.pos += 1;
                    break;
                }
                Tok::Word(k) if self.t.get(self.pos + 1) == Some(&Tok::Eq) => {
                    if let Some(Tok::Str(v)) = self.t.get(self.pos + 2) {
                        match k.as_str() {
                            "title" => self.title = v.clone(),
                            "composer" => self.composer = v.clone(),
                            _ => {}
                        }
                        self.pos += 3;
                    } else {
                        self.pos += 1;
                    }
                }
                _ => self.pos += 1,
            }
        }
    }

    fn command(&mut self, name: &str) -> Option<Expr> {
        match name {
            "relative" => {
                let reference = match self.t.get(self.pos) {
                    Some(Tok::Word(w)) => match parse_note_word(w) {
                        Some(n) => {
                            self.pos += 1;
                            Some((n.letter, 3 + n.marks))
                        }
                        None => None,
                    },
                    _ => None,
                };
                let inner = self.expr()?;
                Some(Expr::Relative(reference, Box::new(inner)))
            }
            "transpose" => {
                // `\transpose from to expr`: the two pitches give the interval.
                let from = self.next_word().and_then(|w| parse_note_word(&w));
                let to = self.next_word().and_then(|w| parse_note_word(&w));
                let inner = self.expr()?;
                match (from, to) {
                    (Some(a), Some(b)) => Some(Expr::Transpose(
                        pitch_value(&b) - pitch_value(&a),
                        Box::new(inner),
                    )),
                    _ => Some(inner),
                }
            }
            "new" | "context" => {
                let kind = self.next_word()?;
                if self.t.get(self.pos) == Some(&Tok::Eq) {
                    self.pos += 1;
                    if matches!(self.t.get(self.pos), Some(Tok::Word(_)) | Some(Tok::Str(_))) {
                        self.pos += 1;
                    }
                }
                // `\with { ... }` sets context properties; its block is not music.
                if matches!(self.t.get(self.pos), Some(Tok::Cmd(c)) if c == "with") {
                    self.pos += 1;
                    let _ = self.expr();
                }
                match kind.as_str() {
                    "Staff" => Some(Expr::Staff(Box::new(self.expr()?))),
                    "Lyrics" | "ChordNames" | "FiguredBass" => {
                        let _ = self.expr();
                        None
                    }
                    // PianoStaff, Voice and other containers play in the current staff.
                    _ => self.expr(),
                }
            }
            "clef" => {
                let w = match self.t.get(self.pos)? {
                    Tok::Word(w) | Tok::Str(w) => w.clone(),
                    _ => return None,
                };
                self.pos += 1;
                Some(Expr::Clef(if w.starts_with("bass") {
                    Clef::Bass
                } else {
                    Clef::Treble
                }))
            }
            "key" => {
                let tonic = self.next_word()?;
                let minor = matches!(self.t.get(self.pos), Some(Tok::Cmd(m)) if m == "minor");
                if matches!(self.t.get(self.pos), Some(Tok::Cmd(m)) if m == "major" || m == "minor")
                {
                    self.pos += 1;
                }
                Some(Expr::Key(key_fifths(&tonic, minor)))
            }
            "time" => {
                let w = self.next_word()?;
                Some(Expr::Time(parse_fraction(&w).unwrap_or((4, 4))))
            }
            "tempo" => {
                if matches!(self.t.get(self.pos), Some(Tok::Str(_))) {
                    self.pos += 1;
                }
                let d = parse_dur_word(&self.next_word()?)?;
                if self.t.get(self.pos) != Some(&Tok::Eq) {
                    return None;
                }
                self.pos += 1;
                let bpm: f64 = self.next_word()?.parse().ok()?;
                Some(Expr::Tempo(bpm * dur_beats(d)))
            }
            "repeat" => {
                let kind = self.next_word()?;
                let count: u32 = self.next_word()?.parse().unwrap_or(1);
                let inner = self.expr()?;
                let times = if kind == "unfold" { count.min(64) } else { 1 };
                Some(Expr::Repeat(times, Box::new(inner)))
            }
            "times" => {
                let f = parse_fraction(&self.next_word()?)?;
                let inner = self.expr()?;
                Some(Expr::Times(f.0 as f64 / f.1 as f64, Box::new(inner)))
            }
            "alternative" => {
                let _ = self.expr();
                None
            }
            // Text and lyrics: the argument is not music. Without this, words such as
            // `a` in a markup block become notes (docs/specs/score-import-and-page-view.md 5.2).
            "markup" | "lyricmode" | "lyrics" | "addlyrics" | "chordmode" | "figuremode"
            | "layout" | "midi" | "paper" => {
                let _ = self.expr();
                None
            }
            // Grace notes take no time in the bar; their pitches are not imported.
            "grace" | "acciaccatura" | "appoggiatura" => {
                let _ = self.expr();
                None
            }
            // `\afterGrace main { grace }`: the main note counts, the grace block does not.
            "afterGrace" => {
                let main = self.expr();
                let _ = self.expr();
                main
            }
            "override" | "revert" | "set" => {
                // Context property path and `=`; the value is a scheme word (dropped by
                // the lexer) or a string, which `until` skips.
                if matches!(self.t.get(self.pos), Some(Tok::Word(_))) {
                    self.pos += 1;
                }
                if self.t.get(self.pos) == Some(&Tok::Eq) {
                    self.pos += 1;
                }
                None
            }
            "header" => {
                if self.t.get(self.pos) == Some(&Tok::Open) {
                    self.header();
                }
                None
            }
            "score" => self.expr(),
            // A music variable such as `\right`.
            _ => self.vars.get(name).cloned(),
        }
    }

    fn expr(&mut self) -> Option<Expr> {
        let tok = self.t.get(self.pos)?.clone();
        match tok {
            Tok::Open => {
                self.pos += 1;
                Some(Expr::Block(self.until(&Tok::Close)))
            }
            Tok::SimOpen => {
                self.pos += 1;
                Some(Expr::Simul(self.until(&Tok::SimClose)))
            }
            Tok::ChordOpen => {
                self.pos += 1;
                let mut notes = Vec::new();
                while let Some(t) = self.t.get(self.pos).cloned() {
                    self.pos += 1;
                    match t {
                        Tok::ChordClose => break,
                        Tok::Word(w) => {
                            if let Some(n) = parse_note_word(&w) {
                                notes.push(n);
                            }
                        }
                        _ => {}
                    }
                }
                let dur = match self.t.get(self.pos) {
                    Some(Tok::Word(w)) => parse_dur_word(w).inspect(|_| self.pos += 1),
                    _ => None,
                };
                Some(Expr::Chord(notes, dur))
            }
            Tok::Tie => {
                self.pos += 1;
                Some(Expr::Tie)
            }
            Tok::Word(w) => {
                self.pos += 1;
                // `name = { ... }` defines a music variable (names are letters only).
                if self.t.get(self.pos) == Some(&Tok::Eq)
                    && w.chars().all(|c| c.is_ascii_alphabetic())
                    && w.len() > 1
                {
                    self.pos += 1;
                    if let Some(e) = self.expr() {
                        self.vars.insert(w, e);
                    }
                    return None;
                }
                if let Some(n) = parse_note_word(&w) {
                    return Some(Expr::Note(n));
                }
                if w.starts_with('r') || w.starts_with('R') || w.starts_with('s') {
                    let spacer = w.starts_with('s');
                    let dur = if w.len() == 1 {
                        None
                    } else {
                        Some(parse_dur_word(&w[1..])?)
                    };
                    return Some(Expr::Rest { dur, spacer });
                }
                None
            }
            Tok::Cmd(name) => {
                self.pos += 1;
                self.command(&name)
            }
            _ => None,
        }
    }
}

#[derive(Debug, Clone)]
struct StaffState {
    index: usize,
    clef: Clef,
    clef_set: bool,
    dur: Dur,
    fifths: i8,
    /// Note indices of the last note or chord, for ties.
    last: Vec<usize>,
    pending_stop: bool,
}

impl StaffState {
    fn new(index: usize) -> StaffState {
        StaffState {
            index,
            clef: Clef::Treble,
            clef_set: false,
            dur: Dur { n: 4, dots: 0 },
            fifths: 0,
            last: Vec::new(),
            pending_stop: false,
        }
    }

    fn hand(&self) -> Hand {
        if self.clef_set {
            match self.clef {
                Clef::Bass => Hand::Left,
                Clef::Treble => Hand::Right,
            }
        } else if self.index == 0 {
            Hand::Right
        } else {
            Hand::Left
        }
    }
}

/// Evaluation position: which staff, where in time, and the relative-pitch reference.
#[derive(Clone, Copy)]
struct Ctx {
    staff: usize,
    cursor: f64,
    rel: Option<(usize, i32)>,
    scale: f64,
    /// Semitones added by enclosing `\transpose`.
    shift: i32,
}

struct Eval {
    staves: Vec<StaffState>,
    /// True once the first `\new Staff` has claimed the default staff 0.
    named_first: bool,
    raws: Vec<TieNote>,
    changes: Vec<Change>,
    meter: (u32, u32),
    tempo: Option<f64>,
}

const LETTERS: [char; 7] = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];

impl Eval {
    fn record_change(&mut self, ctx: Ctx) {
        if ctx.staff == 0 {
            let key_fifths = self.staves[0].fifths;
            self.changes.push(Change {
                start: ctx.cursor,
                time: self.meter,
                key_fifths,
            });
        }
    }

    fn eval(&mut self, e: &Expr, ctx: &mut Ctx) {
        match e {
            Expr::Block(items) => {
                for x in items {
                    self.eval(x, ctx);
                }
            }
            Expr::Simul(items) => {
                let start = ctx.cursor;
                let mut end = start;
                for x in items {
                    let mut c2 = Ctx {
                        cursor: start,
                        ..*ctx
                    };
                    self.eval(x, &mut c2);
                    end = end.max(c2.cursor);
                }
                ctx.cursor = end;
            }
            Expr::Staff(inner) => {
                // The first \new Staff uses the default staff 0; later ones append.
                let idx = if self.named_first {
                    self.staves.push(StaffState::new(self.staves.len()));
                    self.staves.len() - 1
                } else {
                    self.named_first = true;
                    0
                };
                let mut c2 = Ctx {
                    staff: idx,
                    rel: None,
                    ..*ctx
                };
                self.eval(inner, &mut c2);
                ctx.cursor = c2.cursor;
            }
            Expr::Relative(reference, inner) => {
                let rel = reference.or(Some((0, 4)));
                let mut c2 = Ctx { rel, ..*ctx };
                self.eval(inner, &mut c2);
                ctx.cursor = c2.cursor;
            }
            Expr::Times(f, inner) => {
                let mut c2 = Ctx {
                    scale: ctx.scale * f,
                    ..*ctx
                };
                self.eval(inner, &mut c2);
                ctx.cursor = c2.cursor;
            }
            Expr::Transpose(semitones, inner) => {
                let mut c2 = Ctx {
                    shift: ctx.shift + semitones,
                    ..*ctx
                };
                self.eval(inner, &mut c2);
                ctx.cursor = c2.cursor;
            }
            Expr::Repeat(n, inner) => {
                for _ in 0..*n {
                    self.eval(inner, ctx);
                }
            }
            Expr::Note(n) => self.sound(ctx, std::slice::from_ref(n), n.dur),
            Expr::Chord(notes, dur) => self.sound(ctx, notes, *dur),
            Expr::Rest { dur, spacer } => {
                let beats = self.beats(ctx, *dur);
                if !spacer {
                    let st = &mut self.staves[ctx.staff];
                    st.last.clear();
                    st.pending_stop = false;
                }
                ctx.cursor += beats;
            }
            Expr::Tie => {
                let st = &mut self.staves[ctx.staff];
                if !st.last.is_empty() {
                    let idxs = st.last.clone();
                    st.pending_stop = true;
                    for idx in idxs {
                        self.raws[idx].tie_start = true;
                    }
                }
            }
            Expr::Clef(c) => {
                let st = &mut self.staves[ctx.staff];
                st.clef = *c;
                st.clef_set = true;
            }
            Expr::Key(f) => {
                self.staves[ctx.staff].fifths = *f;
                self.record_change(*ctx);
            }
            Expr::Time(m) => {
                self.meter = *m;
                self.record_change(*ctx);
            }
            Expr::Tempo(bpm) => {
                if self.tempo.is_none() {
                    self.tempo = Some(*bpm);
                }
            }
        }
    }

    /// Length in beats of a note value (or the staff default), scaled by `\times`.
    fn beats(&mut self, ctx: &Ctx, dur: Option<Dur>) -> f64 {
        let st = &mut self.staves[ctx.staff];
        if let Some(d) = dur {
            st.dur = d;
        }
        dur_beats(st.dur) * ctx.scale
    }

    /// Plays a note or chord at the cursor and advances it.
    fn sound(&mut self, ctx: &mut Ctx, notes: &[NoteTok], dur: Option<Dur>) {
        let beats = self.beats(ctx, dur);
        let fifths = self.staves[ctx.staff].fifths;
        let hand = self.staves[ctx.staff].hand();
        let mut midis = Vec::new();
        let mut first_ref: Option<(usize, i32)> = None;
        for (k, n) in notes.iter().enumerate() {
            let oct = match ctx.rel {
                Some(base) => {
                    // Nearest occurrence of the letter, at most a fourth (3 steps) away.
                    let base = if k == 0 {
                        base
                    } else {
                        first_ref.unwrap_or(base)
                    };
                    let mut diff = n.letter as i32 - base.0 as i32;
                    if diff > 3 {
                        diff -= 7;
                    } else if diff < -3 {
                        diff += 7;
                    }
                    let base_idx = base.0 as i32 + 7 * base.1;
                    let new_idx = base_idx + diff;
                    (new_idx - n.letter as i32).div_euclid(7) + n.marks
                }
                None => 3 + n.marks,
            };
            if k == 0 {
                first_ref = Some((n.letter, oct));
            }
            let letter = LETTERS[n.letter];
            let alter = n.alter.unwrap_or_else(|| key_alter_for(fifths, letter));
            if let Some(m) = midi_pitch(letter_semitone(letter).unwrap_or(0), oct, alter) {
                if let Ok(shifted) = u8::try_from(i32::from(m) + ctx.shift) {
                    if shifted <= 127 {
                        midis.push(shifted);
                    }
                }
            }
        }
        if ctx.rel.is_some() {
            ctx.rel = first_ref;
        }
        let start = ctx.cursor;
        let pending = self.staves[ctx.staff].pending_stop;
        let mut idxs = Vec::new();
        for midi in midis {
            self.raws.push(TieNote {
                note: ImportedNote {
                    midi,
                    start,
                    beats,
                    hand,
                },
                tie_start: false,
                tie_stop: pending,
            });
            idxs.push(self.raws.len() - 1);
        }
        let st = &mut self.staves[ctx.staff];
        st.pending_stop = false;
        st.last = idxs;
        ctx.cursor += beats;
    }
}

/// Parses a LilyPond source file.
pub fn parse(src: &str) -> Result<ImportedScore, String> {
    let toks = lex(src);
    let mut p = Parser {
        t: &toks,
        pos: 0,
        title: String::new(),
        composer: String::new(),
        vars: HashMap::new(),
    };
    let mut top = Vec::new();
    while p.pos < toks.len() {
        let before = p.pos;
        if let Some(e) = p.expr() {
            top.push(e);
        }
        if p.pos == before {
            p.pos += 1;
        }
    }

    let mut ev = Eval {
        staves: vec![StaffState::new(0)],
        named_first: false,
        raws: Vec::new(),
        changes: vec![Change {
            start: 0.0,
            time: (4, 4),
            key_fifths: 0,
        }],
        meter: (4, 4),
        tempo: None,
    };
    let mut ctx = Ctx {
        staff: 0,
        cursor: 0.0,
        rel: None,
        scale: 1.0,
        shift: 0,
    };
    ev.eval(&Expr::Block(top), &mut ctx);

    if ev.raws.is_empty() {
        return Err("lilypond: no notes found".into());
    }
    let notes_end = ev
        .raws
        .iter()
        .map(|r| r.note.start + r.note.beats)
        .fold(0.0f64, f64::max);
    let end = notes_end.max(ctx.cursor);

    let mut changes = ev.changes;
    changes.sort_by(|a, b| {
        a.start
            .partial_cmp(&b.start)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    let measures = build_measures(&changes, end);

    let right_clef = ev.staves[0].clef;
    let left_clef = ev.staves.get(1).map_or(Clef::Bass, |s| s.clef);
    let mut notes = merge_ties(ev.raws);
    sort_notes(&mut notes);

    Ok(ImportedScore {
        title: p.title,
        composer: p.composer,
        tempo_bpm: ev.tempo,
        right_clef,
        left_clef,
        measures,
        notes,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const PIANO_SCORE: &str = r#"
\version "2.24.0"
\header { title = "Little Test" composer = "T. Composer" }
\score {
  \new PianoStaff <<
    \new Staff { \clef treble \key g \major \time 3/4 \tempo 4 = 100
      \relative c'' { g4 a b | c2. } }
    \new Staff { \clef bass \key g \major \time 3/4 c,,4 d e | }
  >>
}
"#;

    #[test]
    fn reads_header_and_tempo() {
        let s = parse(PIANO_SCORE).unwrap();
        assert_eq!(s.title, "Little Test");
        assert_eq!(s.composer, "T. Composer");
        assert_eq!(s.tempo_bpm, Some(100.0));
    }

    #[test]
    fn relative_mode_and_key_and_measures() {
        let s = parse(PIANO_SCORE).unwrap();
        assert_eq!(s.measures.len(), 2);
        assert_eq!(s.measures[0].time, (3, 4));
        assert_eq!(s.measures[0].key_fifths, 1);
        let rh: Vec<(u8, f64, f64)> = s
            .notes
            .iter()
            .filter(|n| n.hand == Hand::Right)
            .map(|n| (n.midi, n.start, n.beats))
            .collect();
        // \relative c'': g is a fourth below c'' (G4), then a, b, and c2. (3 beats).
        assert_eq!(
            rh,
            vec![
                (67, 0.0, 1.0),
                (69, 1.0, 1.0),
                (71, 2.0, 1.0),
                (72, 3.0, 3.0)
            ]
        );
    }

    #[test]
    fn bass_staff_by_clef_and_absolute_pitch() {
        let s = parse(PIANO_SCORE).unwrap();
        assert_eq!(s.left_clef, Clef::Bass);
        let lh: Vec<(u8, f64)> = s
            .notes
            .iter()
            .filter(|n| n.hand == Hand::Left)
            .map(|n| (n.midi, n.start))
            .collect();
        // Absolute names: c = C3, so c,, = C1 = 24; d = D3 = 50; e = E3 = 52.
        assert_eq!(lh, vec![(24, 0.0), (50, 1.0), (52, 2.0)]);
    }

    #[test]
    fn relative_chords_ties_rests_and_accidentals() {
        let src = r#"\relative c' { c4 <c e g>2 r4 fis8~ fis8 es'4 }"#;
        let s = parse(src).unwrap();
        assert_eq!(s.measures.len(), 2); // 6 beats under the default 4/4
        let got: Vec<(u8, f64, f64)> = s.notes.iter().map(|n| (n.midi, n.start, n.beats)).collect();
        assert_eq!(
            got,
            vec![
                (60, 0.0, 1.0),
                (55, 1.0, 2.0),
                (60, 1.0, 2.0),
                (64, 1.0, 2.0),
                (66, 4.0, 1.0), // fis8~ fis8 merged
                (75, 5.0, 1.0), // es'4: E4 is a second below F#4, then ' = Eb5
            ]
        );
    }

    #[test]
    fn key_signature_applies_to_plain_names() {
        let src = r#"\key d \major c'4 f' | "#;
        let s = parse(src).unwrap();
        // D major has F# and C#: plain c' is C#4 (61), and f' is F#4 (66).
        let midis: Vec<u8> = s.notes.iter().map(|n| n.midi).collect();
        assert_eq!(midis, vec![61, 66]);
    }

    #[test]
    fn meter_change_in_the_body_starts_a_new_bar_length() {
        let src = r#"\score { \new Staff { \time 3/4 c4 d e \time 4/4 c d e f } }"#;
        let s = parse(src).unwrap();
        assert_eq!(s.measures.len(), 2);
        assert_eq!(s.measures[0].time, (3, 4));
        assert_eq!(s.measures[1].time, (4, 4));
        assert_eq!(s.measures[1].start, 3.0);
        assert_eq!(s.measures[1].beats, 4.0);
    }

    #[test]
    fn variables_transpose_and_cautionary_accidentals() {
        // `\right` is a music variable; `\transpose c c'` raises it an octave;
        // `e!` is E with a cautionary accidental (no change of pitch).
        let src = r#"right = { \transpose c c' { c4 e!4 } }
            \score { \context PianoStaff << \context Staff = "a" { \right d4 } >> }"#;
        let s = parse(src).unwrap();
        let got: Vec<(u8, f64)> = s.notes.iter().map(|n| (n.midi, n.start)).collect();
        assert_eq!(got, vec![(60, 0.0), (64, 1.0), (50, 2.0)]); // d4 is D3: no transpose outside \transpose
    }

    #[test]
    fn markup_grace_and_settings_are_not_music() {
        // `a` and `e` in the markup are words, not notes; the grace block and the
        // grace part of \afterGrace take no time; \override and \layout add nothing.
        let src = r#"\score { \new Staff \with { instrumentName = "Piano" } {
            c4 ^\markup { a e } d4 \grace { f16 g16 } e4
            \override NoteHead.color = #red
            f4 \afterGrace g2 { a16 } g4 } }
            \layout { \context { \Score } }"#;
        let s = parse(src).unwrap();
        let got: Vec<(u8, f64, f64)> = s.notes.iter().map(|n| (n.midi, n.start, n.beats)).collect();
        assert_eq!(
            got,
            vec![
                (48, 0.0, 1.0),
                (50, 1.0, 1.0),
                (52, 2.0, 1.0),
                (53, 3.0, 1.0),
                (55, 4.0, 2.0),
                (55, 6.0, 1.0),
            ]
        );
    }

    #[test]
    fn rejects_documents_without_notes() {
        assert!(parse(r#"\header { title = "x" }"#).is_err());
    }

    #[test]
    fn lexes_and_parses_names() {
        assert_eq!(
            parse_note_word("bes,8.").unwrap(),
            NoteTok {
                letter: 6,
                alter: Some(-1),
                marks: -1,
                dur: Some(Dur { n: 8, dots: 1 }),
            }
        );
        assert!(parse_note_word("h").is_none());
    }
}
