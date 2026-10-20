//! `content similar`: flags songs whose melody is close to a corpus melody.
//! Corpus files: our song JSON, MIDI (.mid/.midi), ABC (.abc) and uncompressed MusicXML
//! (.musicxml/.xml). The reference corpus lives in git-ignored `references/melody-corpus/`.
//! See docs/research/melody-similarity.md.

use easy_piano_core::similarity::{melody_from_song, skyline, tokens, top_matches, MelodyNote, Token};
use easy_piano_core::song::Song;
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

/// Calibrated in core/tests/similarity_calibration.rs (docs/research/melody-similarity.md).
pub const DEFAULT_THRESHOLD: f64 = 0.5;
const USAGE: &str = "usage: content similar <song.json|dir>... [--corpus <dir>]... [--threshold 0..1] [--top n]";
const CORPUS_EXT: [&str; 6] = ["json", "mid", "midi", "abc", "musicxml", "xml"];

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

/// Every melody in a file, named by song id, file name, or `file#tune` for multi-tune ABC.
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
        _ => Err("unsupported file type".into()),
    }
}

// --- MIDI (SMF type 0/1). Notes are grouped by (track, channel), drums (channel 10) dropped;
// the melody is the group that supplies the most notes of the overall skyline.

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
    let mut groups: BTreeMap<(usize, u8), Vec<MelodyNote>> = BTreeMap::new();
    let mut pos = 8 + u32::from_be_bytes([d[4], d[5], d[6], d[7]]) as usize;
    let mut track = 0;
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
                            let note = MelodyNote { pitch: b, onset: tick as f64 / division as f64 };
                            groups.entry((track, s & 0x0f)).or_default().push(note);
                        }
                        i += if two { 2 } else { 1 };
                    }
                }
            }
            track += 1;
        }
        pos = start + len;
    }
    Ok(melody_group(groups.into_values().collect()))
}

/// The group (voice/track) owning most notes of the combined skyline, as its own skyline.
fn melody_group(groups: Vec<Vec<MelodyNote>>) -> Vec<MelodyNote> {
    let top = skyline(groups.iter().flatten().copied().collect());
    let owns = |g: &Vec<MelodyNote>| {
        top.iter().filter(|t| g.iter().any(|n| n.pitch == t.pitch && (n.onset - t.onset).abs() < 1e-6)).count()
    };
    groups.into_iter().max_by_key(owns).map(skyline).unwrap_or_default()
}

// --- ABC: notes, accidentals (held to the bar line), octave marks, lengths, key signature,
// chords (top note via skyline).

fn key_sharps(k: &str) -> i32 {
    let k: Vec<char> = k.split_whitespace().next().unwrap_or("C").chars().collect();
    let tonic_len = 1 + k.iter().skip(1).take_while(|c| **c == '#' || **c == 'b').count();
    let tonic: String = k.iter().take(tonic_len).collect();
    let mode: String = k.iter().skip(tonic_len).collect::<String>().to_ascii_lowercase();
    let minor = mode.starts_with('m') && !mode.starts_with("maj") && !mode.starts_with("mix");
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

/// Tunes in an ABC file as (X number and title, melody). Onsets in quarter-note beats.
pub fn abc_tunes(text: &str) -> Vec<(String, Vec<MelodyNote>)> {
    let mut tunes = Vec::new();
    let (mut name, mut notes, mut t) = (String::new(), Vec::new(), 0.0);
    let (mut unit, mut sharps) = (0.5, 0);
    let mut flush = |name: &mut String, notes: &mut Vec<MelodyNote>| {
        if !notes.is_empty() {
            tunes.push((std::mem::take(name), skyline(std::mem::take(notes))));
        }
    };
    // Accidentals written in the current bar, by (step, octave).
    let mut bar_acc: BTreeMap<(char, i32), i32> = BTreeMap::new();
    for line in text.lines() {
        let l = line.trim();
        let b = l.as_bytes();
        if b.len() > 1 && b[1] == b':' && b[0].is_ascii_alphabetic() {
            let v = l[2..].trim();
            match &l[..1] {
                "X" => {
                    flush(&mut name, &mut notes);
                    (name, t, unit, sharps) = (v.to_string(), 0.0, 0.5, 0);
                    bar_acc.clear();
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
                '|' => {
                    bar_acc.clear();
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
                    let alter = match acc.take() {
                        Some(a) => {
                            bar_acc.insert((step, oct), a);
                            a
                        }
                        None => bar_acc.get(&(step, oct)).copied().unwrap_or_else(|| sig_alter(sharps, step)),
                    };
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
            let mut out = vec![dir.join("content/songs")];
            let refs = dir.join("references/melody-corpus");
            if refs.is_dir() {
                out.push(refs);
            }
            return out;
        }
        if !dir.pop() {
            return Vec::new();
        }
    }
}

struct Args {
    inputs: Vec<PathBuf>,
    corpora: Vec<PathBuf>,
    threshold: f64,
    top: usize,
}

fn parse_args(args: &[String]) -> Result<Args, String> {
    let mut a = Args { inputs: Vec::new(), corpora: Vec::new(), threshold: DEFAULT_THRESHOLD, top: 3 };
    let mut it = args.iter();
    while let Some(arg) = it.next() {
        if !arg.starts_with("--") {
            a.inputs.push(PathBuf::from(arg));
            continue;
        }
        if !matches!(arg.as_str(), "--corpus" | "--threshold" | "--top") {
            return Err(format!("unknown flag {arg}"));
        }
        let val = it.next().ok_or(format!("{arg} needs a value"))?;
        match arg.as_str() {
            "--corpus" => a.corpora.push(PathBuf::from(val)),
            "--threshold" => {
                a.threshold = val
                    .parse::<f64>()
                    .ok()
                    .filter(|x| (0.0..=1.0).contains(x))
                    .ok_or(format!("bad --threshold `{val}` (0..1)"))?
            }
            _ => a.top = val.parse::<usize>().ok().filter(|n| *n > 0).ok_or(format!("bad --top `{val}`"))?,
        }
    }
    if a.inputs.is_empty() {
        return Err("no input".into());
    }
    Ok(a)
}

fn joined(paths: &[PathBuf]) -> String {
    paths.iter().map(|p| p.display().to_string()).collect::<Vec<_>>().join(", ")
}

/// Exit code: 0 all clear, 1 a song at or above threshold, 2 usage or input error.
pub fn run(args: &[String]) -> i32 {
    let a = match parse_args(args) {
        Ok(a) => a,
        Err(e) => {
            eprintln!("error: {e}\n{USAGE}");
            return 2;
        }
    };
    let mut queries = Vec::new();
    for p in &a.inputs {
        if !p.exists() {
            eprintln!("error: {} does not exist", p.display());
            return 2;
        }
        if p.is_file() && ext(p) != "json" {
            eprintln!("error: {} is not a song .json", p.display());
            return 2;
        }
        files(p, &mut queries);
    }
    queries.retain(|q| ext(q) == "json");
    if queries.is_empty() {
        eprintln!("error: no song .json in {}", joined(&a.inputs));
        return 2;
    }
    let corpora = if a.corpora.is_empty() { default_corpora() } else { a.corpora };
    // (name, canonical path to skip self-matches, tokens), built once.
    let mut corpus: Vec<(String, Option<PathBuf>, Vec<Token>)> = Vec::new();
    for dir in &corpora {
        if !dir.is_dir() {
            eprintln!("error: corpus {} is not a directory", dir.display());
            return 2;
        }
        let mut fs_ = Vec::new();
        files(dir, &mut fs_);
        for f in fs_.iter().filter(|f| CORPUS_EXT.contains(&ext(f).as_str())) {
            match load(f) {
                Ok(ms) => corpus.extend(ms.into_iter().map(|(n, m)| (n, f.canonicalize().ok(), tokens(&m)))),
                Err(e) => eprintln!("warning: {}: {e}", f.display()),
            }
        }
    }
    if corpus.is_empty() {
        eprintln!("error: empty corpus ({})", joined(&corpora));
        return 2;
    }
    println!("corpus: {} melodies from {}", corpus.len(), joined(&corpora));
    let (mut over, mut errors) = (0, 0);
    for q in &queries {
        let song = fs::read_to_string(q).map_err(|e| e.to_string()).and_then(|t| Song::from_json(&t));
        let song = match song {
            Ok(s) => s,
            Err(e) => {
                eprintln!("error: {}: {e}", q.display());
                errors += 1;
                continue;
            }
        };
        let mel = melody_from_song(&song);
        let qpath = q.canonicalize().ok();
        let others: Vec<(&str, &[Token])> = corpus
            .iter()
            .filter(|(_, p, _)| p.is_none() || *p != qpath)
            .map(|(n, _, t)| (n.as_str(), t.as_slice()))
            .collect();
        let matches = top_matches(&tokens(&mel), &others, a.top);
        let flag = matches.first().is_some_and(|m| m.score >= a.threshold);
        println!("{} {} ({} notes)", if flag { "SIMILAR" } else { "ok" }, song.id, mel.len());
        for m in &matches {
            let (qs, qe) = m.alignment.query_span;
            let (cs, ce) = m.alignment.cand_span;
            println!(
                "  {:.2}  purity {:.2}  info {:.1}  ngram {:.2}  notes {}..{} ~ {}..{}  {}",
                m.score, m.alignment.purity, m.alignment.info, m.ngram, qs, qe + 1, cs, ce + 1, m.name
            );
        }
        over += flag as i32;
    }
    if over > 0 {
        eprintln!("{over} song(s) at or above threshold {}", a.threshold);
    }
    if errors > 0 {
        eprintln!("{errors} song(s) could not be read");
        return 2;
    }
    (over > 0) as i32
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pitches(m: &[MelodyNote]) -> Vec<u8> {
        m.iter().map(|n| n.pitch).collect()
    }

    fn s(v: &[&str]) -> Vec<String> {
        v.iter().map(|x| x.to_string()).collect()
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
    fn abc_accidentals_hold_to_the_bar_line() {
        // C major: ^F stays sharp for the rest of the bar (same octave only), then resets.
        let t = abc_tunes("X:2\nK:C\n^F F f | F\n");
        assert_eq!(pitches(&t[0].1), vec![66, 66, 77, 65]);
        assert_eq!(key_sharps("Ébm"), 0);
        assert_eq!(key_sharps("Am"), 0);
        assert_eq!(key_sharps("Bb"), -2);
        assert_eq!(key_sharps("Dmix"), 2);
    }

    #[test]
    fn midi_picks_the_melody_track_and_skips_drums() {
        fn track(events: &[u8]) -> Vec<u8> {
            let mut t = b"MTrk".to_vec();
            t.extend((events.len() as u32 + 4).to_be_bytes());
            t.extend(events);
            t.extend([0x00, 0xff, 0x2f, 0x00]);
            t
        }
        let mut d = b"MThd\0\0\0\x06\0\x01\0\x02\0\x60".to_vec();
        // Track 0: melody 72 74 76 on beats 0 1 2, plus drums.
        d.extend(track(&[0x00, 0x90, 72, 100, 0x00, 0x99, 81, 100, 0x60, 0x90, 74, 100, 0x60, 0x90, 76, 100]));
        // Track 1: a single high accompaniment note on beat 0.5.
        d.extend(track(&[0x30, 0x91, 84, 100]));
        let m = midi(&d).unwrap();
        assert_eq!(pitches(&m), vec![72, 74, 76]);
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

    #[test]
    fn bad_arguments_are_usage_errors() {
        for bad in [
            &["x.json", "--thresold", "0.5"][..],
            &["x.json", "--threshold", "abc"],
            &["x.json", "--threshold", "1.5"],
            &["x.json", "--top", "0"],
            &["x.json", "--corpus"],
            &[],
        ] {
            assert!(parse_args(&s(bad)).is_err(), "{bad:?}");
        }
        let a = parse_args(&s(&["a.json", "--threshold", "0.7", "--top", "5", "--corpus", "c"])).unwrap();
        assert_eq!((a.threshold, a.top, a.corpora.len()), (0.7, 5, 1));
    }

    #[test]
    fn run_rejects_missing_inputs_corpus_and_non_json() {
        let dir = std::env::temp_dir().join(format!("similar-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(dir.join("corp")).unwrap();
        fs::write(dir.join("corp/ref.abc"), "X:1\nK:C\nCDEF|\n").unwrap();
        fs::write(dir.join("tune.mid"), b"").unwrap();
        let p = |x: &str| dir.join(x).display().to_string();
        assert_eq!(run(&s(&[&p("nope.json")])), 2);
        assert_eq!(run(&s(&[&p("tune.mid"), "--corpus", &p("corp")])), 2);
        // A directory with no song JSON checks nothing: an error, not a silent pass.
        assert_eq!(run(&s(&[&p("corp"), "--corpus", &p("corp")])), 2);
        let song = r#"{"id":"t","title":"T","composer":"Trad.","arranger":"A","source":"original",
            "source_url":null,"license":"CC0-1.0","composition_license":"public-domain","bpm":90,
            "time":"4/4","key":"C","bars":[{"RH":"C4:4 D4:4 E4:4 F4:4"}]}"#;
        fs::write(dir.join("t.json"), song).unwrap();
        assert_eq!(run(&s(&[&p("t.json"), "--corpus", &p("missing")])), 2);
        fs::create_dir_all(dir.join("empty")).unwrap();
        assert_eq!(run(&s(&[&p("t.json"), "--corpus", &p("empty")])), 2);
        assert_eq!(run(&s(&[&p("t.json"), "--corpus", &p("corp"), "--threshold", "0.99"])), 0);
        // Ode to Joy up a tone vs an ABC reference holding its first four bars in C: flagged.
        let ode = r#"{"id":"o","title":"O","composer":"Trad.","arranger":"A","source":"original",
            "source_url":null,"license":"CC0-1.0","composition_license":"public-domain","bpm":90,
            "time":"4/4","key":"D","bars":[{"RH":"F#4:4 F#4:4 G4:4 A4:4"},{"RH":"A4:4 G4:4 F#4:4 E4:4"},
            {"RH":"D4:4 D4:4 E4:4 F#4:4"},{"RH":"F#4:4 E4:4 E4:2"}]}"#;
        fs::write(dir.join("o.json"), ode).unwrap();
        fs::write(dir.join("corp/ode.abc"), "X:2\nT:Ode\nL:1/4\nK:C\nEEFG|GFED|CCDE|E>DD2|\n").unwrap();
        assert_eq!(run(&s(&[&p("o.json"), "--corpus", &p("corp")])), 1);
        fs::write(dir.join("bad.json"), "{").unwrap();
        assert_eq!(run(&s(&[&p("bad.json"), "--corpus", &p("corp")])), 2);
        fs::remove_dir_all(&dir).unwrap();
    }
}
