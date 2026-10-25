//! Score import on real exported files (docs/specs/score-import-and-page-view.md 5.3).
//! Fixtures and their sources: tests/fixtures/score_import/SOURCES.md.

use easy_piano_core::score_import::{import, lilypond, midi, Hand, ImportedNote, ImportedScore};

fn fixture(name: &str) -> Vec<u8> {
    let path = format!(
        "{}/tests/fixtures/score_import/{name}",
        env!("CARGO_MANIFEST_DIR")
    );
    std::fs::read(&path).unwrap_or_else(|e| panic!("{path}: {e}"))
}

/// Sounding notes as (MIDI pitch, start in 1/120 quarter), sorted, hands ignored.
fn sounding(notes: &[ImportedNote]) -> Vec<(u8, i64)> {
    let mut v: Vec<(u8, i64)> = notes
        .iter()
        .map(|n| (n.midi, (n.start * 120.0).round() as i64))
        .collect();
    v.sort();
    v
}

/// Compares two note lists and reports the first differences.
fn assert_same_notes(what: &str, got: &[(u8, i64)], want: &[(u8, i64)]) {
    assert!(!want.is_empty(), "{what}: the reference has no notes");
    let diffs: Vec<String> = got
        .iter()
        .zip(want)
        .filter(|(a, b)| a != b)
        .take(5)
        .map(|(a, b)| format!("got {a:?} want {b:?}"))
        .collect();
    assert_eq!(
        got.len(),
        want.len(),
        "{what}: note count differs; first differences: {diffs:?}"
    );
    assert!(diffs.is_empty(), "{what}: {diffs:?}");
}

#[test]
fn mutopia_lilypond_notes_match_its_midi_export() {
    // Mutopia BWV 846 (Prelude 1), LilyPond source with the MIDI that LilyPond exported.
    let src = String::from_utf8(fixture("wtk1-prelude1.ly")).unwrap();
    let ly: ImportedScore = lilypond::parse(&src).unwrap();
    let mid: ImportedScore = midi::parse(&fixture("wtk1-prelude1.mid")).unwrap();
    assert_same_notes(
        "lilypond vs its midi",
        &sounding(&ly.notes),
        &sounding(&mid.notes),
    );
}

#[test]
fn musescore_mxl_piano_part_matches_the_xml_count() {
    // OpenScore Lieder "Just for Today" (CC0), exported by MuseScore 4.5.2: a sung line
    // (P1, one staff) and the piano (P2, two staves). Counts from tools in SOURCES.md.
    let s = import("lc6583477.mxl", &fixture("lc6583477.mxl")).unwrap();
    assert_eq!(s.title, "Just for Today");
    assert_eq!(s.composer, "Jane Bingham Abbott");
    assert_eq!(s.measures.len(), 41);
    assert_eq!(s.measures[0].time, (3, 4));
    let right = s.notes.iter().filter(|n| n.hand == Hand::Right).count();
    let left = s.notes.iter().filter(|n| n.hand == Hand::Left).count();
    // Piano part only: 295 treble-staff and 188 bass-staff notes. The vocal line is
    // not counted (it would be 102 more right-hand notes).
    assert_eq!((right, left), (295, 188));
    let last_end = s
        .notes
        .iter()
        .map(|n| n.start + n.beats)
        .fold(0.0f64, f64::max);
    assert!(
        last_end <= 41.0 * 3.0 + 1e-9,
        "notes run past the last bar: {last_end}"
    );
}

#[test]
fn import_detects_the_lilypond_file() {
    let s = import("wtk1-prelude1.ly", &fixture("wtk1-prelude1.ly")).unwrap();
    assert_eq!(s.title, "Das Wohltemperierte Clavier I");
    assert_eq!(s.measures[0].time, (4, 4));
}

/// (MIDI pitch, start, length) in quarter notes, read by mido (CC0 file, see SOURCES.md).
const BOOGIE_NOTES: &[(u8, f64, f64)] = &[
    (36, 1.000000, 0.414583),
    (36, 1.666667, 0.331250),
    (45, 2.000000, 0.664583),
    (36, 2.666667, 0.331250),
    (43, 3.000000, 0.664583),
    (36, 3.666667, 0.331250),
    (45, 4.000000, 0.664583),
    (43, 4.666667, 0.331250),
    (36, 5.000000, 0.414583),
    (36, 5.666667, 0.331250),
    (45, 6.000000, 0.664583),
    (36, 6.666667, 0.331250),
    (43, 7.000000, 0.664583),
    (36, 7.666667, 0.331250),
    (45, 8.000000, 0.664583),
    (43, 8.666667, 0.331250),
    (41, 9.000000, 0.414583),
    (41, 9.666667, 0.331250),
    (50, 10.000000, 0.664583),
    (41, 10.666667, 0.331250),
    (48, 11.000000, 0.664583),
    (41, 11.666667, 0.331250),
    (50, 12.000000, 0.664583),
    (48, 12.666667, 0.331250),
    (36, 13.000000, 0.414583),
    (36, 13.666667, 0.331250),
    (45, 14.000000, 0.664583),
    (36, 14.666667, 0.331250),
    (43, 15.000000, 0.664583),
    (36, 15.666667, 0.331250),
    (45, 16.000000, 0.664583),
    (43, 16.666667, 0.331250),
    (43, 17.000000, 0.331250),
    (43, 17.666667, 0.331250),
    (52, 18.000000, 0.664583),
    (43, 18.666667, 0.331250),
    (50, 19.000000, 0.664583),
    (43, 19.666667, 0.331250),
    (52, 20.000000, 0.664583),
    (50, 20.666667, 0.331250),
    (41, 21.000000, 0.414583),
    (41, 21.666667, 0.331250),
    (50, 22.000000, 0.664583),
    (41, 22.666667, 0.331250),
    (48, 23.000000, 0.664583),
    (41, 23.666667, 0.331250),
    (50, 24.000000, 0.664583),
    (48, 24.666667, 0.331250),
    (36, 25.000000, 0.414583),
    (36, 25.666667, 0.331250),
    (45, 26.000000, 0.664583),
    (36, 26.666667, 0.331250),
    (43, 27.000000, 0.664583),
    (36, 27.666667, 0.331250),
    (45, 28.000000, 0.664583),
    (43, 28.666667, 0.331250),
    (36, 29.000000, 0.414583),
    (36, 29.666667, 0.331250),
    (45, 30.000000, 0.664583),
    (36, 30.666667, 0.331250),
    (43, 31.000000, 0.664583),
    (36, 31.666667, 0.331250),
    (45, 32.000000, 0.664583),
    (43, 32.666667, 0.331250),
    (45, 35.000000, 1.997917),
];

#[test]
fn cc0_sequencer_midi_notes_match_mido() {
    let s = midi::parse(&fixture("piano-boogie-left-hand-pattern.mid")).unwrap();
    assert_eq!(s.notes.len(), BOOGIE_NOTES.len());
    for (got, &(midi, start, beats)) in s.notes.iter().zip(BOOGIE_NOTES) {
        assert_eq!(got.midi, midi);
        assert!(
            (got.start - start).abs() < 1e-4,
            "start {} vs {start}",
            got.start
        );
        assert!(
            (got.beats - beats).abs() < 1e-4,
            "length {} vs {beats}",
            got.beats
        );
    }
    // One note track, all notes below middle C: every note is in the left hand.
    assert!(s.notes.iter().all(|n| n.hand == Hand::Left));
}
