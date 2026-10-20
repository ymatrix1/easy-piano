//! `content similar`: flags songs whose melody is close to a corpus melody.
//! Corpus files: our song JSON, MIDI (.mid/.midi), ABC (.abc) and uncompressed MusicXML
//! (.musicxml/.xml). The reference corpus lives in git-ignored `references/melody-corpus/`.
//! See docs/research/melody-similarity.md.

use easy_piano_core::similarity::{melody_from_song, skyline, tokens, top_matches, MelodyNote, Token};
use easy_piano_core::song::Song;
use std::fs;
use std::path::{Path, PathBuf};

/// Calibrated on content/songs vs each other (docs/research/melody-similarity.md).
pub const DEFAULT_THRESHOLD: f64 = 0.6;
const USAGE: &str = "usage: content similar <song.json|dir> [--corpus <dir>]... [--threshold x] [--top n]";

fn files(path: &Path, out: &mut Vec<PathBuf>) {
    if path.is_dir() {
        let mut entries: Vec<_> = fs::read_dir(path).into_iter().flatten().flatten().map(|e| e.path()).collect();
        entries.sort();
        for p in entries {
            files(&p, out);
        }
    } else {
        out.push(path.to_path_buf());
    }
}

fn ext(path: &Path) -> String {
    path.extension().and_then(|e| e.to_str()).unwrap_or("").to_ascii_lowercase()
}

/// Every melody in a file, named `file` or `file#tune` for multi-tune ABC.
fn load(path: &Path) -> Result<Vec<(String, Vec<MelodyNote>)>, String> {
    let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("?").to_string();
    match ext(path).as_str() {
        "json" => {
            let text = fs::read_to_string(path).map_err(|e| e.to_string())?;
            let song = Song::from_json(&text)?;
            Ok(vec![(song.id.clone(), melody_from_song(&song))])
        }
        "mid" | "midi" => Ok(vec![(name, midi(&fs::read(path).map_err(|e| e.to_string())?)?)]),
        "abc" => {
            let text = fs::read_to_string(path).map_err(|e| e.to_string())?;
            Ok(abc_tunes(&text).into_iter().map(|(t, m)| (format!("{name}#{t}"), m)).collect())
        }
        "musicxml" | "xml" => Ok(vec![(name, musicxml(&fs::read_to_string(path).map_err(|e| e.to_string())?))]),
        _ => Ok(Vec::new()),
    }
}

// --- MIDI (SMF type 0/1): note-ons on every channel but drums (10), then skyline.

fn vlq(d: &[u8], i: &mut usize) -> Result<u32, String> {
    let mut v = 0u32;
    loop {
        let b = *d.get(*i).ok_or("midi: truncated")?;
        *i += 1;
        v = (v << 7) | (b & 0x7f) as u32;
        if b & 0x80 == 0 {
            return Ok(v);
        }
    }
}

pub fn midi(d: &[u8]) -> Result<Vec<MelodyNote>, String> {
    if d.len() < 14 || &d[0..4] != b"MThd" {
        return Err("midi: no MThd header".into());
    }
    let division = u16::from_be_bytes([d[12], d[13]]);
    if division & 0x8000 != 0 || division == 0 {
        return Err("midi: SMPTE timing not supported".into());
    }
    let mut notes = Vec::new();
    let mut pos = 8 + u32::from_be_bytes([d[4], d[5], d[6], d[7]]) as usize;
    while pos + 8 <= d.len() {
        let len = u32::from_be_bytes([d[pos + 4], d[pos + 5], d[pos + 6], d[pos + 7]]) as usize;
        let (start, end) = (pos + 8, (pos + 8 + len).min(d.len()));
        if &d[pos..pos + 4] == b"MTrk" {
            let (mut i, mut tick, mut status) = (start, 0u64, 0u8);
            while i < end {
                tick += vlq(d, &mut i)? as u64;
                let mut b = *d.get(i).ok_or("midi: truncated")?;
                if b & 0x80 != 0 {
                    status = b;
                    i += 1;
                    b = *d.get(i).unwrap_or(&0);
                } else if status == 0 {
                    return Err("midi: running status without status".into());
                }
                match status {
                    0xff => {
                        i += 1;
                        let l = vlq(d, &mut i)? as usize;
                        i += l;
                        status = 0;
                    }
                    0xf0 | 0xf7 => {
                        let l = vlq(d, &mut i)? as usize;
                        i += l;
                        status = 0;
                    }
                    s => {
                        let two = !matches!(s & 0xf0, 0xc0 | 0xd0);
                        let vel = if two { *d.get(i + 1).unwrap_or(&0) } else { 0 };
                        if s & 0xf0 == 0x90 && vel > 0 && s & 0x0f != 9 {
                            notes.push(MelodyNote { pitch: b, onset: tick as f64 / division as f64 });
                        }
                        i += if two { 2 } else { 1 };
                    }
                }
            }
        }
        pos = start + len;
    }
    Ok(skyline(notes))
}

// --- ABC: notes, accidentals, octave marks, lengths, key signature, chords (top note via skyline).

fn key_sharps(k: &str) -> i32 {
    let k = k.split_whitespace().next().unwrap_or("C");
    let minor = k.len() > 1 && k[1..].trim_start_matches(['#', 'b']).to_ascii_lowercase().starts_with('m')
        && !k[1..].to_ascii_lowercase().contains("maj")
        && !k[1..].to_ascii_lowercase().contains("mix");
    let tonic: String = k.chars().take(1).chain(k.chars().skip(1).take_while(|c| *c == '#' || *c == 'b')).collect();
    let majors = ["Cb", "Gb", "Db", "Ab", "Eb", "Bb", "F", "C", "G", "D", "A", "E", "B", "F#", "C#"];
    let minors = ["Ab", "Eb", "Bb", "F", "C", "G", "D", "A", "E", "B", "F#", "C#", "G#", "D#", "A#"];
    let list = if minor { minors } else { majors };
    list.iter().position(|t| *t == tonic).map(|p| p as i32 - 7).unwrap_or(0)
}

fn sig_alter(sharps: i32, step: char) -> i32 {
    const SHARP_ORDER: [char; 7] = ['F', 'C', 'G', 'D', 'A', 'E', 'B'];
    let idx = SHARP_ORDER.iter().position(|c| *c == step).unwrap() as i32;
    if sharps > 0 && idx < sharps {
        1
    } else if sharps < 0 && 6 - idx < -sharps {
        -1
    } else {
        0
    }
}

fn abc_len(s: &[char], i: &mut usize) -> f64 {
    let num = |i: &mut usize| {
        let st = *i;
        while *i < s.len() && s[*i].is_ascii_digit() {
            *i += 1;
        }
        s[st..*i].iter().collect::<String>().parse::<f64>().ok()
    };
    let mut v = num(i).unwrap_or(1.0);
    while *i < s.len() && s[*i] == '/' {
        *i += 1;
        v /= num(i).unwrap_or(2.0);
    }
    v
}

/// Tunes in an ABC file as (title or X number, melody). Onsets in quarter-note beats.
pub fn abc_tunes(text: &str) -> Vec<(String, Vec<MelodyNote>)> {
    let mut tunes = Vec::new();
    let (mut name, mut notes, mut t) = (String::new(), Vec::new(), 0.0);
    let (mut unit, mut sharps) = (0.5, 0);
    let mut flush = |name: &mut String, notes: &mut Vec<MelodyNote>| {
        if !notes.is_empty() {
            tunes.push((std::mem::take(name), skyline(std::mem::take(notes))));
        }
    };
    for line in text.lines() {
        let l = line.trim();
        let field = l.len() > 1 && l.as_bytes()[1] == b':' && l.as_bytes()[0].is_ascii_alphabetic();
        if field {
            let v = l[2..].trim();
            match &l[..1] {
                "X" => {
                    flush(&mut name, &mut notes);
                    (name, t, unit, sharps) = (v.to_string(), 0.0, 0.5, 0);
                }
                "T" if !name.contains(' ') => name = format!("{name} {v}").trim().to_string(),
                "L" => {
                    if let Some((a, b)) = v.split_once('/') {
                        if let (Ok(a), Ok(b)) = (a.trim().parse::<f64>(), b.trim().parse::<f64>()) {
                            unit = 4.0 * a / b;
                        }
                    }
                }
                "K" => sharps = key_sharps(v),
                _ => {}
            }
            continue;
        }
        let s: Vec<char> = l.split('%').next().unwrap_or("").chars().collect();
        let (mut i, mut chord, mut chord_len) = (0, false, 0.0f64);
        let mut acc: Option<i32> = None;
        while i < s.len() {
            let c = s[i];
            match c {
                '"' | '!' | '+' => {
                    i += 1;
                    while i < s.len() && s[i] != c {
                        i += 1;
                    }
                    i += 1;
                }
                '{' => {
                    while i < s.len() && s[i] != '}' {
                        i += 1;
                    }
                    i += 1;
                }
                '[' if s.get(i + 2) == Some(&':') => {
                    while i < s.len() && s[i] != ']' {
                        i += 1;
                    }
                    i += 1;
                }
                '[' if s.get(i + 1).is_some_and(|c| c.is_ascii_digit()) => i += 2,
                '[' => {
                    chord = true;
                    chord_len = 0.0;
                    i += 1;
                }
                ']' => {
                    chord = false;
                    i += 1;
                    t += chord_len * abc_len(&s, &mut i);
                }
                '^' | '_' | '=' => {
                    let a = acc.unwrap_or(0);
                    acc = Some(match c { '^' => a + 1, '_' => a - 1, _ => 0 });
                    i += 1;
                }
                'z' | 'x' | 'Z' => {
                    i += 1;
                    t += abc_len(&s, &mut i) * unit;
                }
                'A'..='G' | 'a'..='g' => {
                    let step = c.to_ascii_uppercase();
                    let base = [0, 2, 4, 5, 7, 9, 11]["CDEFGAB".find(step).unwrap()];
                    let mut oct = if c.is_ascii_lowercase() { 5 } else { 4 };
                    i += 1;
                    while i < s.len() && (s[i] == '\'' || s[i] == ',') {
                        oct += if s[i] == '\'' { 1 } else { -1 };
                        i += 1;
                    }
                    let alter = acc.take().unwrap_or_else(|| sig_alter(sharps, step));
                    let pitch = (12 * (oct + 1) + base + alter).clamp(0, 127) as u8;
                    let d = abc_len(&s, &mut i) * unit;
                    notes.push(MelodyNote { pitch, onset: t });
                    if chord {
                        chord_len = chord_len.max(d);
                    } else {
                        t += d;
                    }
                }
                _ => i += 1,
            }
        }
    }
    flush(&mut name, &mut notes);
    tunes
}

// --- MusicXML (uncompressed): first <part> only, honours <chord/>, <backup>, <forward>.

fn tag<'a>(s: &'a str, name: &str) -> Option<&'a str> {
    let open = format!("<{name}>");
    let a = s.find(&open)? + open.len();
    let b = s[a..].find(&format!("</{name}>"))? + a;
    Some(s[a..b].trim())
}

pub fn musicxml(text: &str) -> Vec<MelodyNote> {
    let part = text.find("<part ").map(|a| &text[a..]).unwrap_or(text);
    let part = part.find("</part>").map(|b| &part[..b]).unwrap_or(part);
    let (mut divisions, mut t, mut last_onset) = (1.0, 0.0, 0.0);
    let mut notes = Vec::new();
    let mut rest = part;
    loop {
        let next = ["<note", "<backup", "<forward", "<divisions>"]
            .iter()
            .filter_map(|k| rest.find(k).map(|p| (p, *k)))
            .min();
        let Some((p, kind)) = next else { break };
        let body_end = match kind {
            "<divisions>" => rest[p..].find("</divisions>").map(|e| p + e + 12),
            "<note" => rest[p..].find("</note>").map(|e| p + e + 7),
            "<backup" => rest[p..].find("</backup>").map(|e| p + e + 9),
            _ => rest[p..].find("</forward>").map(|e| p + e + 10),
        };
        let Some(e) = body_end else { break };
        let body = &rest[p..e];
        let dur = tag(body, "duration").and_then(|v| v.parse::<f64>().ok()).unwrap_or(0.0) / divisions;
        match kind {
            "<divisions>" => divisions = tag(body, "divisions").and_then(|v| v.parse().ok()).unwrap_or(1.0),
            "<backup" => t -= dur,
            "<forward" => t += dur,
            _ if body.contains("<grace") => {}
            _ => {
                let chord = body.contains("<chord");
                let onset = if chord { last_onset } else { t };
                if let (Some(step), Some(oct)) = (tag(body, "step"), tag(body, "octave").and_then(|o| o.parse::<i32>().ok())) {
                    if let Some(base) = "C D EF G A B".find(step) {
                        let alter = tag(body, "alter").and_then(|a| a.parse::<f64>().ok()).unwrap_or(0.0).round() as i32;
                        let pitch = (12 * (oct + 1) + base as i32 + alter).clamp(0, 127) as u8;
                        notes.push(MelodyNote { pitch, onset });
                    }
                }
                if !chord {
                    last_onset = t;
                    t += dur;
                }
            }
        }
        rest = &rest[e..];
    }
    skyline(notes)
}

// --- command

fn default_corpora() -> Vec<PathBuf> {
    let mut dir = std::env::current_dir().unwrap_or_default();
    loop {
        if dir.join("content/songs").is_dir() {
            return vec![dir.join("content/songs"), dir.join("references/melody-corpus")];
        }
        if !dir.pop() {
            return Vec::new();
        }
    }
}

pub fn run(args: &[String]) -> i32 {
    let (mut inputs, mut corpora, mut threshold, mut top) = (Vec::new(), Vec::new(), DEFAULT_THRESHOLD, 3usize);
    let mut it = args.iter();
    while let Some(a) = it.next() {
        let val = match a.as_str() {
            "--corpus" | "--threshold" | "--top" => match it.next() {
                Some(v) => v,
                None => {
                    eprintln!("{USAGE}");
                    return 2;
                }
            },
            _ => {
                inputs.push(PathBuf::from(a));
                continue;
            }
        };
        match a.as_str() {
            "--corpus" => corpora.push(PathBuf::from(val)),
            "--threshold" => threshold = val.parse().unwrap_or(threshold),
            _ => top = val.parse().unwrap_or(top),
        }
    }
    if inputs.is_empty() {
        eprintln!("{USAGE}");
        return 2;
    }
    if corpora.is_empty() {
        corpora = default_corpora();
    }
    let mut corpus: Vec<(String, PathBuf, Vec<Token>)> = Vec::new();
    for dir in &corpora {
        let mut fs_ = Vec::new();
        if dir.exists() {
            files(dir, &mut fs_);
        }
        for f in fs_ {
            match load(&f) {
                Ok(ms) => corpus.extend(ms.into_iter().map(|(n, m)| (n, f.clone(), tokens(&m)))),
                Err(e) => eprintln!("warning: {}: {e}", f.display()),
            }
        }
    }
    println!("corpus: {} melodies from {}", corpus.len(), corpora.iter().map(|p| p.display().to_string()).collect::<Vec<_>>().join(", "));
    let mut queries = Vec::new();
    for p in &inputs {
        files(p, &mut queries);
    }
    let mut over = 0;
    for q in queries.iter().filter(|q| ext(q) == "json") {
        let melodies = match load(q) {
            Ok(m) => m,
            Err(e) => {
                eprintln!("error: {}: {e}", q.display());
                over += 1;
                continue;
            }
        };
        for (name, mel) in melodies {
            let qt = tokens(&mel);
            let same = |p: &PathBuf| p.canonicalize().ok() == q.canonicalize().ok();
            let others: Vec<(String, Vec<Token>)> =
                corpus.iter().filter(|(_, p, _)| !same(p)).map(|(n, _, t)| (n.clone(), t.clone())).collect();
            let matches = top_matches(&qt, &others, top);
            let flag = matches.first().is_some_and(|m| m.score >= threshold);
            println!("{} {name} ({} notes)", if flag { "SIMILAR" } else { "ok" }, mel.len());
            for m in &matches {
                let (qs, qe) = m.alignment.query_span;
                let (cs, ce) = m.alignment.cand_span;
                println!(
                    "  {:.2}  ngram {:.2}  align {:.2}  notes {}..{} ~ {}..{}  {}",
                    m.score, m.ngram, m.alignment.score, qs, qe + 1, cs, ce + 1, m.name
                );
            }
            over += flag as i32;
        }
    }
    if over > 0 {
        eprintln!("{over} song(s) at or above threshold {threshold}");
        1
    } else {
        0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pitches(m: &[MelodyNote]) -> Vec<u8> {
        m.iter().map(|n| n.pitch).collect()
    }

    #[test]
    fn abc_reads_key_lengths_and_chords() {
        let t = abc_tunes("X:1\nT:Test\nL:1/8\nK:G\nG2 A B | [ce]2 f =f | c'/d'/ z2 A,|\n");
        assert_eq!(t.len(), 1);
        assert_eq!(t[0].0, "1 Test");
        assert_eq!(pitches(&t[0].1), vec![67, 69, 71, 76, 78, 77, 84, 86, 57]);
        assert_eq!(t[0].1[3].onset, 2.0);
        assert_eq!(t[0].1[4].onset, 3.0);
        assert_eq!(t[0].1[8].onset, 5.5);
    }

    #[test]
    fn midi_reads_note_ons_and_skips_drums() {
        let mut trk = vec![0x00, 0x90, 60, 100, 0x60, 0x80, 60, 0, 0x00, 0x99, 36, 100, 0x00, 0x90, 64, 90];
        trk.extend([0x60, 0x90, 64, 0, 0x00, 0xff, 0x2f, 0x00]);
        let mut d = b"MThd\0\0\0\x06\0\0\0\x01\0\x60MTrk".to_vec();
        d.extend((trk.len() as u32).to_be_bytes());
        d.extend(trk);
        let m = midi(&d).unwrap();
        assert_eq!(pitches(&m), vec![60, 64]);
        assert_eq!(m[1].onset, 1.0);
    }

    #[test]
    fn musicxml_reads_pitch_alter_and_chords() {
        let x = "<part id=\"P1\"><measure><attributes><divisions>2</divisions></attributes>\
            <note><pitch><step>C</step><octave>4</octave></pitch><duration>2</duration></note>\
            <note><chord/><pitch><step>E</step><octave>4</octave></pitch><duration>2</duration></note>\
            <note><rest/><duration>1</duration></note>\
            <note><pitch><step>F</step><alter>1</alter><octave>4</octave></pitch><duration>1</duration></note>\
            </measure></part>";
        let m = musicxml(x);
        assert_eq!(pitches(&m), vec![64, 66]);
        assert_eq!(m[1].onset, 1.5);
    }
}
