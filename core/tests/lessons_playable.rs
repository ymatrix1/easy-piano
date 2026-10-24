//! Runs the session engine over the real lesson scores in content/songs:
//! a simulated perfect student must pass every song with 3 stars in both
//! modes with both hands graded, and a student who skips half the notes must fail play-along.

use easy_piano_core::session::{HandFilter, Mode, NoteEvent, Session, Settings};
use easy_piano_core::song::Song;
use std::fs;
use std::path::Path;

fn songs() -> Vec<Song> {
    let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("../content/songs");
    let mut out: Vec<Song> = fs::read_dir(&dir)
        .expect("content/songs")
        .flatten()
        .map(|e| Song::from_json(&fs::read_to_string(e.path()).unwrap()).unwrap())
        .collect();
    out.sort_by(|a, b| a.id.cmp(&b.id));
    assert!(out.len() >= 7, "expected the Piano Basics scores");
    out
}

/// Plays every target `offset_us` after its due time, skipping targets where `skip(i)`.
fn play(
    song: &Song,
    settings: Settings,
    offset_us: i64,
    skip: impl Fn(usize) -> bool,
) -> easy_piano_core::session::StageResult {
    let mut s = Session::new(song, settings);
    let us_per_beat = 60e6 / (song.bpm * settings.tempo);
    let plan: Vec<(i64, Vec<u8>)> = s
        .targets()
        .iter()
        .map(|t| {
            (
                (t.beat * us_per_beat) as i64 + offset_us,
                t.pitches.iter().copied().collect(),
            )
        })
        .collect();
    for (i, (t_us, pitches)) in plan.into_iter().enumerate() {
        if skip(i) {
            continue;
        }
        for p in pitches {
            s.on_note(NoteEvent {
                pitch: p,
                on: true,
                velocity: 80,
                t_us,
            });
        }
        s.tick(t_us);
    }
    s.tick(s.end_us());
    s.result()
}

#[test]
fn perfect_student_gets_three_stars_on_every_lesson_song() {
    for song in songs() {
        for (mode, tempo) in [
            (Mode::Wait, 1.0),
            (Mode::PlayAlong, 0.7),
            (Mode::PlayAlong, 1.0),
        ] {
            let r = play(
                &song,
                Settings {
                    mode,
                    tempo,
                    hand: HandFilter::Both,
                    ..Settings::default()
                },
                15_000,
                |_| false,
            );
            assert!(
                r.passed && r.stars == 3,
                "{} {mode:?} {tempo}: {r:?}",
                song.id
            );
        }
    }
}

#[test]
fn skipping_half_the_notes_fails_play_along() {
    for song in songs() {
        let r = play(
            &song,
            Settings {
                hand: HandFilter::Both,
                ..Settings::default()
            },
            0,
            |i| i % 2 == 0,
        );
        assert!(!r.passed && r.stars == 0, "{}: {r:?}", song.id);
    }
}
