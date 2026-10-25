//! MusicXML 3.x partwise scores (`.xml`, `.musicxml`) and compressed `.mxl` archives.
//!
//! Supported: divisions, key and time signatures, clefs per staff, notes, rests,
//! chords, backup/forward, ties, tempo from `<sound>`. Each `<part>` contributes
//! notes; its staves decide the hand (clef sign F = left, G = right, otherwise
//! staff 2 = left). Measures come from the first part.

use super::{
    letter_semitone, measure_beats, merge_ties, midi_pitch, sort_notes, Articulation, Clef,
    ExpressionMark, Hand, ImportedMeasure, ImportedNote, ImportedScore, TieNote,
};
use quick_xml::events::{BytesStart, Event};
use quick_xml::Reader;
use std::collections::HashMap;
use std::io::{Cursor, Read};

/// Minimal element tree: enough for lookups by name, no namespaces.
#[derive(Debug, Default)]
struct Node {
    name: String,
    attrs: Vec<(String, String)>,
    text: String,
    children: Vec<Node>,
}

impl Node {
    fn child(&self, name: &str) -> Option<&Node> {
        self.children.iter().find(|c| c.name == name)
    }

    fn child_text(&self, name: &str) -> Option<&str> {
        self.child(name).map(|c| c.text.trim())
    }

    fn attr(&self, key: &str) -> Option<&str> {
        self.attrs
            .iter()
            .find(|(k, _)| k == key)
            .map(|(_, v)| v.as_str())
    }

    fn child_i64(&self, name: &str) -> Option<i64> {
        self.child_text(name)?.parse().ok()
    }

    /// First descendant (depth-first) with the given name.
    fn descendant(&self, name: &str) -> Option<&Node> {
        for c in &self.children {
            if c.name == name {
                return Some(c);
            }
            if let Some(found) = c.descendant(name) {
                return Some(found);
            }
        }
        None
    }
}

fn node_from(e: &BytesStart) -> Result<Node, String> {
    let mut node = Node {
        name: String::from_utf8_lossy(e.name().as_ref()).into_owned(),
        ..Node::default()
    };
    for a in e.attributes() {
        let a = a.map_err(|e| format!("xml attribute: {e}"))?;
        let key = String::from_utf8_lossy(a.key.as_ref()).into_owned();
        let value = a
            .unescape_value()
            .map_err(|e| format!("xml attribute value: {e}"))?
            .into_owned();
        node.attrs.push((key, value));
    }
    Ok(node)
}

fn parse_tree(xml: &str) -> Result<Node, String> {
    let mut reader = Reader::from_str(xml);
    reader.config_mut().trim_text(true);
    let mut stack = vec![Node::default()];
    loop {
        match reader.read_event().map_err(|e| format!("xml: {e}"))? {
            Event::Start(e) => stack.push(node_from(&e)?),
            Event::Empty(e) => {
                let n = node_from(&e)?;
                stack.last_mut().ok_or("xml: unbalanced")?.children.push(n);
            }
            Event::End(_) => {
                let n = stack.pop().ok_or("xml: unbalanced")?;
                stack.last_mut().ok_or("xml: unbalanced")?.children.push(n);
            }
            Event::Text(t) => {
                let s = t.unescape().map_err(|e| format!("xml text: {e}"))?;
                stack.last_mut().ok_or("xml: unbalanced")?.text.push_str(&s);
            }
            Event::CData(t) => {
                let s = String::from_utf8_lossy(&t.into_inner()).into_owned();
                stack.last_mut().ok_or("xml: unbalanced")?.text.push_str(&s);
            }
            Event::Eof => break,
            _ => {}
        }
    }
    if stack.len() != 1 {
        return Err("xml: unclosed element".into());
    }
    let doc = stack.pop().ok_or("xml: empty document")?;
    doc.children
        .into_iter()
        .next()
        .ok_or_else(|| "xml: no root element".into())
}

/// Per-part notation state carried from one measure to the next.
struct PartState {
    divisions: i64,
    time: (u32, u32),
    key_fifths: i8,
    /// Clef sign per staff number (1-based).
    clefs: HashMap<i64, Clef>,
}

impl PartState {
    fn new() -> Self {
        PartState {
            divisions: 1,
            time: (4, 4),
            key_fifths: 0,
            clefs: HashMap::new(),
        }
    }

    fn clef(&self, staff: i64) -> Clef {
        self.clefs.get(&staff).copied().unwrap_or(if staff >= 2 {
            Clef::Bass
        } else {
            Clef::Treble
        })
    }

    fn hand(&self, staff: i64) -> Hand {
        match self.clef(staff) {
            Clef::Treble => Hand::Right,
            Clef::Bass => Hand::Left,
        }
    }

    fn apply_attributes(&mut self, attrs: &Node) {
        if let Some(d) = attrs.child_i64("divisions").filter(|d| *d > 0) {
            self.divisions = d;
        }
        if let Some(f) = attrs
            .child("key")
            .and_then(|k| k.child_text("fifths"))
            .and_then(|f| f.parse::<i8>().ok())
        {
            self.key_fifths = f;
        }
        if let Some(time) = attrs.child("time") {
            if let (Some(b), Some(u)) = (
                time.child_text("beats").and_then(|b| b.parse::<u32>().ok()),
                time.child_text("beat-type")
                    .and_then(|u| u.parse::<u32>().ok()),
            ) {
                if b > 0 && u > 0 {
                    self.time = (b, u);
                }
            }
        }
        for clef in attrs.children.iter().filter(|c| c.name == "clef") {
            let number = clef
                .attr("number")
                .and_then(|n| n.parse::<i64>().ok())
                .unwrap_or(1);
            let sign = clef.child_text("sign").unwrap_or("G");
            let c = if sign == "F" {
                Clef::Bass
            } else {
                Clef::Treble
            };
            self.clefs.insert(number, c);
        }
    }
}

/// MIDI pitch of a `<note>`'s `<pitch>`, if it has one.
fn pitch_midi(note: &Node) -> Option<u8> {
    let pitch = note.child("pitch")?;
    let step = pitch.child_text("step")?.chars().next()?;
    let octave: i32 = pitch.child_text("octave")?.parse().ok()?;
    let alter = pitch
        .child_text("alter")
        .and_then(|a| a.parse::<f64>().ok())
        .unwrap_or(0.0)
        .round() as i32;
    midi_pitch(letter_semitone(step)?, octave, alter)
}

fn has_tie(note: &Node, kind: &str) -> bool {
    note.children
        .iter()
        .any(|t| t.name == "tie" && t.attr("type") == Some(kind))
}

/// True if a part has a grand staff (two or more staves in its attributes).
fn has_grand_staff(part: &Node) -> bool {
    part.children
        .iter()
        .filter(|c| c.name == "measure")
        .flat_map(|m| m.children.iter())
        .filter(|c| c.name == "attributes")
        .any(|a| a.child_i64("staves").is_some_and(|s| s >= 2))
}

fn find_tempo(node: &Node) -> Option<f64> {
    if node.name == "sound" {
        if let Some(t) = node.attr("tempo").and_then(|t| t.parse::<f64>().ok()) {
            return Some(t);
        }
    }
    node.children.iter().find_map(find_tempo)
}

fn title_of(root: &Node) -> String {
    root.descendant("work")
        .and_then(|w| w.child_text("work-title"))
        .or_else(|| root.child("movement-title").map(|t| t.text.trim()))
        .unwrap_or("")
        .to_string()
}

fn composer_of(root: &Node) -> String {
    root.child("identification")
        .and_then(|id| {
            id.children
                .iter()
                .find(|c| c.name == "creator" && c.attr("type") == Some("composer"))
        })
        .map(|c| c.text.trim().to_string())
        .unwrap_or_default()
}

/// Parses an uncompressed MusicXML document.
pub fn parse(data: &[u8]) -> Result<ImportedScore, String> {
    let text = std::str::from_utf8(data).map_err(|e| format!("musicxml utf-8: {e}"))?;
    parse_str(text.trim_start_matches('\u{feff}'))
}

/// Parses a compressed `.mxl` archive: the `META-INF/container.xml` rootfile, or
/// else the first XML entry outside `META-INF`.
pub fn parse_compressed(data: &[u8]) -> Result<ImportedScore, String> {
    let mut zip = zip::ZipArchive::new(Cursor::new(data)).map_err(|e| format!("mxl zip: {e}"))?;
    let container = read_entry(&mut zip, "META-INF/container.xml").ok();
    let root_name = container
        .as_deref()
        .and_then(|c| std::str::from_utf8(c).ok())
        .and_then(|c| parse_tree(c.trim_start_matches('\u{feff}')).ok())
        .and_then(|tree| {
            tree.descendant("rootfile")
                .and_then(|r| r.attr("full-path"))
                .map(str::to_string)
        });
    let name = match root_name {
        Some(n) => n,
        None => zip
            .file_names()
            .find(|n| {
                let lower = n.to_ascii_lowercase();
                !n.starts_with("META-INF")
                    && (lower.ends_with(".xml") || lower.ends_with(".musicxml"))
            })
            .map(str::to_string)
            .ok_or("mxl: no MusicXML entry")?,
    };
    let xml = read_entry(&mut zip, &name)?;
    parse(&xml)
}

fn read_entry(zip: &mut zip::ZipArchive<Cursor<&[u8]>>, name: &str) -> Result<Vec<u8>, String> {
    let mut file = zip
        .by_name(name)
        .map_err(|e| format!("mxl entry {name}: {e}"))?;
    let mut buf = Vec::new();
    file.read_to_end(&mut buf)
        .map_err(|e| format!("mxl read {name}: {e}"))?;
    Ok(buf)
}

fn parse_str(text: &str) -> Result<ImportedScore, String> {
    let root = parse_tree(text)?;
    if root.name != "score-partwise" {
        return Err(format!(
            "unsupported MusicXML root `{}` (only score-partwise)",
            root.name
        ));
    }

    let mut raws: Vec<TieNote> = Vec::new();
    let mut measures: Vec<ImportedMeasure> = Vec::new();
    let mut expression = Vec::new();
    let mut slurs: HashMap<String, f64> = HashMap::new();
    let mut open_hairpin: Option<(f64, bool)> = None;
    let mut open_pedal: Option<f64> = None;
    let mut tempo = None;
    let mut right_clef = Clef::Treble;
    let mut left_clef = Clef::Bass;

    // A piano score is a part with two or more staves. When one exists, other parts
    // (a sung line, a second instrument) are left out; otherwise every part is read.
    let parts: Vec<&Node> = root.children.iter().filter(|c| c.name == "part").collect();
    let grand: Vec<bool> = parts.iter().map(|p| has_grand_staff(p)).collect();
    let keep: Vec<bool> = if grand.contains(&true) {
        grand
    } else {
        vec![true; parts.len()]
    };
    let first_kept = keep.iter().position(|&k| k);

    for (pi, part) in parts.iter().enumerate().filter(|(i, _)| keep[*i]) {
        let first = Some(pi) == first_kept;
        if first {
            tempo = find_tempo(part);
        }
        let mut st = PartState::new();
        let mut running = 0.0f64;
        for (mi, measure) in part
            .children
            .iter()
            .filter(|c| c.name == "measure")
            .enumerate()
        {
            let m_start = running;
            let mut cursor: i64 = 0;
            let mut last_start: i64 = 0;
            let mut max_end: i64 = 0;
            for c in &measure.children {
                match c.name.as_str() {
                    "attributes" => st.apply_attributes(c),
                    "direction" if pi == 0 => {
                        let beat = m_start + cursor as f64 / st.divisions as f64;
                        if let Some(dt) = c.child("direction-type") {
                            if let Some(dyns) = dt.child("dynamics") {
                                if let Some(mark) = dyns.children.first() {
                                    expression.push(ExpressionMark::Dynamic {
                                        beat,
                                        value: mark.name.clone(),
                                    });
                                }
                            }
                            if let Some(wedge) = dt.child("wedge") {
                                match wedge.attr("type") {
                                    Some("crescendo") => open_hairpin = Some((beat, true)),
                                    Some("diminuendo") => open_hairpin = Some((beat, false)),
                                    Some("stop") => {
                                        if let Some((start, crescendo)) = open_hairpin.take() {
                                            expression.push(ExpressionMark::Hairpin {
                                                start,
                                                end: beat,
                                                crescendo,
                                            });
                                        }
                                    }
                                    _ => {}
                                }
                            }
                            if let Some(pedal) = dt.child("pedal") {
                                match pedal.attr("type") {
                                    Some("start") => open_pedal = Some(beat),
                                    Some("stop") => {
                                        if let Some(start) = open_pedal.take() {
                                            expression
                                                .push(ExpressionMark::Pedal { start, end: beat });
                                        }
                                    }
                                    Some("change") => {
                                        if let Some(start) = open_pedal.replace(beat) {
                                            expression
                                                .push(ExpressionMark::Pedal { start, end: beat });
                                        }
                                    }
                                    _ => {}
                                }
                            }
                        }
                    }
                    "note" => {
                        if c.child("grace").is_some() {
                            continue;
                        }
                        let chord = c.child("chord").is_some();
                        let dur = c.child_i64("duration").unwrap_or(0);
                        let start = if chord { last_start } else { cursor };
                        let staff = c.child_i64("staff").unwrap_or(1);
                        let mut articulations = Vec::new();
                        if let Some(notations) = c.child("notations") {
                            if let Some(arts) = notations.child("articulations") {
                                for art in &arts.children {
                                    match art.name.as_str() {
                                        "staccato" => articulations.push(Articulation::Staccato),
                                        "accent" => articulations.push(Articulation::Accent),
                                        "tenuto" => articulations.push(Articulation::Tenuto),
                                        _ => {}
                                    }
                                }
                            }
                            if notations.child("fermata").is_some() {
                                articulations.push(Articulation::Fermata);
                            }
                            for slur in notations.children.iter().filter(|n| n.name == "slur") {
                                let key = slur.attr("number").unwrap_or("1").to_string();
                                match (pi == 0, slur.attr("type")) {
                                    (true, Some("start")) => {
                                        slurs.insert(
                                            key,
                                            m_start + start as f64 / st.divisions as f64,
                                        );
                                    }
                                    (true, Some("stop")) => {
                                        if let Some(begin) = slurs.remove(&key) {
                                            expression.push(ExpressionMark::Slur {
                                                start: begin,
                                                end: m_start + start as f64 / st.divisions as f64,
                                            });
                                        }
                                    }
                                    _ => {}
                                }
                            }
                        }
                        if c.child("rest").is_none() {
                            if let Some(midi) = pitch_midi(c) {
                                let div = st.divisions as f64;
                                raws.push(TieNote {
                                    note: ImportedNote {
                                        midi,
                                        start: m_start + start as f64 / div,
                                        beats: dur as f64 / div,
                                        hand: st.hand(staff),
                                        articulations,
                                    },
                                    tie_start: has_tie(c, "start"),
                                    tie_stop: has_tie(c, "stop"),
                                });
                            }
                        }
                        if !chord {
                            cursor += dur;
                        }
                        last_start = start;
                        max_end = max_end.max(start + dur);
                    }
                    "backup" => cursor -= c.child_i64("duration").unwrap_or(0),
                    "forward" => {
                        cursor += c.child_i64("duration").unwrap_or(0);
                        max_end = max_end.max(cursor);
                    }
                    _ => {}
                }
            }
            let max_beats = max_end as f64 / st.divisions as f64;
            // A regular bar has the length of its time signature, even if a voice
            // ends early; only an overfull bar is longer. A pickup (implicit="yes")
            // has the length of the notes it holds.
            let beats = if measure.attr("implicit") == Some("yes") && max_end > 0 {
                max_beats
            } else {
                measure_beats(st.time).max(max_beats)
            };
            if first {
                if mi == 0 {
                    right_clef = st.clef(1);
                    left_clef = st.clef(2);
                }
                measures.push(ImportedMeasure {
                    number: measure
                        .attr("number")
                        .and_then(|n| n.parse().ok())
                        .unwrap_or(mi as u32 + 1),
                    start: m_start,
                    beats,
                    time: st.time,
                    key_fifths: st.key_fifths,
                });
            }
            running += beats;
        }
    }

    if measures.is_empty() {
        return Err("musicxml: no measures".into());
    }
    let mut notes = merge_ties(raws);
    sort_notes(&mut notes);
    let end_beat = measures.last().map_or(0.0, |m| m.start + m.beats);
    if let Some((start, crescendo)) = open_hairpin {
        expression.push(ExpressionMark::Hairpin {
            start,
            end: end_beat,
            crescendo,
        });
    }
    if let Some(start) = open_pedal {
        expression.push(ExpressionMark::Pedal {
            start,
            end: end_beat,
        });
    }
    Ok(ImportedScore {
        title: title_of(&root),
        composer: composer_of(&root),
        tempo_bpm: tempo,
        right_clef,
        left_clef,
        measures,
        notes,
        expression,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE: &str = r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 3.1 Partwise//EN" "">
<score-partwise version="3.1">
  <work><work-title>Test Piece</work-title></work>
  <identification><creator type="composer">Test Composer</creator></identification>
  <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>2</divisions>
        <key><fifths>1</fifths></key>
        <time><beats>3</beats><beat-type>4</beat-type></time>
        <staves>2</staves>
        <clef number="1"><sign>G</sign><line>2</line></clef>
        <clef number="2"><sign>F</sign><line>4</line></clef>
      </attributes>
      <direction><direction-type><metronome><per-minute>96</per-minute></metronome></direction-type>
        <sound tempo="96"/></direction>
      <note><pitch><step>G</step><octave>4</octave></pitch><duration>2</duration><voice>1</voice><type>quarter</type><staff>1</staff></note>
      <note><pitch><step>B</step><octave>4</octave></pitch><duration>2</duration><voice>1</voice><type>quarter</type><staff>1</staff></note>
      <note><rest/><duration>2</duration><voice>1</voice><type>quarter</type><staff>1</staff></note>
      <backup><duration>6</duration></backup>
      <note><pitch><step>C</step><octave>3</octave></pitch><duration>6</duration><voice>5</voice><type>half</type><staff>2</staff></note>
    </measure>
    <measure number="2">
      <note><pitch><step>F</step><alter>1</alter><octave>4</octave></pitch><duration>2</duration><voice>1</voice><type>quarter</type><staff>1</staff></note>
      <note><chord/><pitch><step>A</step><octave>4</octave></pitch><duration>2</duration><voice>1</voice><type>quarter</type><staff>1</staff></note>
      <note><rest/><duration>4</duration><voice>1</voice><type>half</type><staff>1</staff></note>
      <backup><duration>6</duration></backup>
      <note><pitch><step>D</step><octave>2</octave></pitch><duration>2</duration><tie type="start"/><voice>5</voice><type>quarter</type><staff>2</staff></note>
      <note><pitch><step>D</step><octave>2</octave></pitch><duration>4</duration><tie type="stop"/><voice>5</voice><type>half</type><staff>2</staff></note>
    </measure>
  </part>
</score-partwise>"#;

    #[test]
    fn reads_title_composer_and_tempo() {
        let s = parse(SAMPLE.as_bytes()).unwrap();
        assert_eq!(s.title, "Test Piece");
        assert_eq!(s.composer, "Test Composer");
        assert_eq!(s.tempo_bpm, Some(96.0));
    }

    #[test]
    fn preserves_expression_marks_and_note_articulations() {
        let xml = SAMPLE
            .replace(
                "<direction><direction-type><metronome><per-minute>96</per-minute></metronome></direction-type>",
                "<direction><direction-type><dynamics><mf/></dynamics></direction-type></direction>\n      <direction><direction-type><wedge type=\"crescendo\"/></direction-type></direction>\n      <direction><direction-type><pedal type=\"start\"/></direction-type></direction>\n      <direction><direction-type><metronome><per-minute>96</per-minute></metronome></direction-type>",
            )
            .replace(
                "<staff>1</staff></note>\n      <note><pitch><step>B</step>",
                "<staff>1</staff><notations><slur type=\"start\"/><articulations><staccato/></articulations></notations></note>\n      <note><pitch><step>B</step>",
            )
            .replace(
                "<staff>1</staff></note>\n      <note><rest/>",
                "<staff>1</staff><notations><slur type=\"stop\"/><articulations><accent/><tenuto/></articulations></notations></note>\n      <note><rest/>",
            )
            .replace(
                "<note><pitch><step>F</step><alter>1</alter><octave>4</octave></pitch><duration>2</duration><voice>1</voice><type>quarter</type><staff>1</staff></note>",
                "<direction><direction-type><wedge type=\"stop\"/></direction-type></direction><direction><direction-type><pedal type=\"stop\"/></direction-type></direction><direction><direction-type><dynamics><f/></dynamics></direction-type></direction><note><pitch><step>F</step><alter>1</alter><octave>4</octave></pitch><duration>2</duration><voice>1</voice><type>quarter</type><staff>1</staff><notations><fermata/></notations></note>",
            );
        let score = parse(xml.as_bytes()).unwrap();
        assert_eq!(
            score
                .notes
                .iter()
                .find(|n| n.midi == 67)
                .unwrap()
                .articulations,
            vec![Articulation::Staccato]
        );
        assert_eq!(
            score
                .notes
                .iter()
                .find(|n| n.midi == 71)
                .unwrap()
                .articulations,
            vec![Articulation::Accent, Articulation::Tenuto]
        );
        assert!(score
            .notes
            .iter()
            .any(|n| n.articulations.contains(&Articulation::Fermata)));
        assert!(score.expression.contains(&ExpressionMark::Dynamic {
            beat: 0.0,
            value: "mf".into()
        }));
        assert!(score.expression.contains(&ExpressionMark::Dynamic {
            beat: 3.0,
            value: "f".into()
        }));
        assert!(score.expression.contains(&ExpressionMark::Slur {
            start: 0.0,
            end: 1.0
        }));
        assert!(score.expression.contains(&ExpressionMark::Hairpin {
            start: 0.0,
            end: 3.0,
            crescendo: true
        }));
        assert!(score.expression.contains(&ExpressionMark::Pedal {
            start: 0.0,
            end: 3.0
        }));
    }

    #[test]
    fn reads_measures_with_time_and_key() {
        let s = parse(SAMPLE.as_bytes()).unwrap();
        assert_eq!(s.measures.len(), 2);
        assert_eq!(s.measures[0].number, 1);
        assert_eq!(s.measures[0].time, (3, 4));
        assert_eq!(s.measures[0].key_fifths, 1);
        assert_eq!(s.measures[0].start, 0.0);
        assert_eq!(s.measures[0].beats, 3.0);
        assert_eq!(s.measures[1].start, 3.0);
    }

    #[test]
    fn reads_clefs() {
        let s = parse(SAMPLE.as_bytes()).unwrap();
        assert_eq!(s.right_clef, Clef::Treble);
        assert_eq!(s.left_clef, Clef::Bass);
    }

    #[test]
    fn assigns_hands_by_staff_and_times_notes() {
        let s = parse(SAMPLE.as_bytes()).unwrap();
        let rh: Vec<(u8, f64)> = s
            .notes
            .iter()
            .filter(|n| n.hand == Hand::Right)
            .map(|n| (n.midi, n.start))
            .collect();
        // G4=67, B4=71 at 0 and 1; F#4=66 and A4=69 chord at 2.
        assert_eq!(rh, vec![(67, 0.0), (71, 1.0), (66, 3.0), (69, 3.0)]);
        let lh: Vec<(u8, f64)> = s
            .notes
            .iter()
            .filter(|n| n.hand == Hand::Left)
            .map(|n| (n.midi, n.start))
            .collect();
        // C3=48 whole measure 1; D2=38 tied across the barline, merged into one note.
        assert_eq!(lh, vec![(48, 0.0), (38, 3.0)]);
    }

    #[test]
    fn merges_tied_notes_into_one_length() {
        let s = parse(SAMPLE.as_bytes()).unwrap();
        let d = s.notes.iter().find(|n| n.midi == 38).unwrap();
        assert_eq!(d.beats, 3.0); // quarter (1 beat) + half (2 beats)
        assert_eq!(s.notes.iter().filter(|n| n.midi == 38).count(), 1);
    }

    /// A one-part, partwise document with the given `<measure>` elements.
    fn one_part(measures: &str) -> String {
        format!(
            r#"<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="3.1">
  <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
  <part id="P1">{measures}</part>
</score-partwise>"#
        )
    }

    #[test]
    fn unfinished_voice_keeps_the_bar_length() {
        // Bar 1 is 4/4; the left hand ends after two beats. The bar still lasts four
        // beats, so bar 2 starts at beat 4 (before the fix it started at beat 3).
        let xml = one_part(
            r#"<measure number="1">
  <attributes><divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time>
    <staves>2</staves><clef number="1"><sign>G</sign></clef><clef number="2"><sign>F</sign></clef></attributes>
  <note><pitch><step>C</step><octave>5</octave></pitch><duration>3</duration><staff>1</staff></note>
  <backup><duration>3</duration></backup>
  <note><pitch><step>C</step><octave>3</octave></pitch><duration>2</duration><staff>2</staff></note>
</measure>
<measure number="2">
  <note><pitch><step>D</step><octave>5</octave></pitch><duration>4</duration><staff>1</staff></note>
</measure>"#,
        );
        let s = parse(xml.as_bytes()).unwrap();
        assert_eq!(s.measures[0].beats, 4.0);
        assert_eq!(s.measures[1].start, 4.0);
        let d = s.notes.iter().find(|n| n.midi == 74).unwrap(); // D5
        assert_eq!(d.start, 4.0);
    }

    #[test]
    fn pickup_measure_has_the_length_of_its_notes() {
        let xml = one_part(
            r#"<measure number="0" implicit="yes">
  <attributes><divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time></attributes>
  <note><pitch><step>G</step><octave>4</octave></pitch><duration>1</duration></note>
</measure>
<measure number="1">
  <note><pitch><step>C</step><octave>5</octave></pitch><duration>4</duration></note>
</measure>"#,
        );
        let s = parse(xml.as_bytes()).unwrap();
        assert_eq!(s.measures[0].number, 0);
        assert_eq!(s.measures[0].beats, 1.0);
        assert_eq!(s.measures[1].start, 1.0);
    }

    #[test]
    fn grace_notes_take_no_time_and_are_not_imported() {
        let xml = one_part(
            r#"<measure number="1">
  <attributes><divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time></attributes>
  <note><grace/><pitch><step>D</step><octave>5</octave></pitch><voice>1</voice><type>16th</type></note>
  <note><pitch><step>E</step><octave>5</octave></pitch><duration>4</duration></note>
</measure>"#,
        );
        let s = parse(xml.as_bytes()).unwrap();
        assert_eq!(s.notes.len(), 1);
        assert_eq!(s.notes[0].midi, 76); // E5 only
        assert_eq!(s.notes[0].start, 0.0);
        assert_eq!(s.measures[0].beats, 4.0);
    }

    #[test]
    fn a_sung_part_is_left_out_when_a_piano_part_exists() {
        let xml = r#"<?xml version="1.0"?>
<score-partwise version="3.1">
  <part-list><score-part id="P1"/><score-part id="P2"/></part-list>
  <part id="P1"><measure number="1">
    <attributes><divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time>
      <clef><sign>G</sign></clef></attributes>
    <note><pitch><step>A</step><octave>4</octave></pitch><duration>4</duration></note>
  </measure></part>
  <part id="P2"><measure number="1">
    <attributes><divisions>1</divisions><staves>2</staves>
      <clef number="1"><sign>G</sign></clef><clef number="2"><sign>F</sign></clef></attributes>
    <note><pitch><step>C</step><octave>5</octave></pitch><duration>4</duration><staff>1</staff></note>
    <backup><duration>4</duration></backup>
    <note><pitch><step>C</step><octave>3</octave></pitch><duration>4</duration><staff>2</staff></note>
  </measure></part>
</score-partwise>"#;
        let s = parse(xml.as_bytes()).unwrap();
        let midis: Vec<u8> = s.notes.iter().map(|n| n.midi).collect();
        assert_eq!(midis, vec![48, 72]); // the piano's C3 and C5; A4 (the voice) is dropped
    }

    #[test]
    fn rejects_timewise_documents() {
        let err = parse(b"<score-timewise></score-timewise>").unwrap_err();
        assert!(err.contains("score-timewise"));
    }
}
