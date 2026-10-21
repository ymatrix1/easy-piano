//! Plays the Ode to Joy play-along fixture through the default output
//! device and prints the stream rate, reported latency and clock drift.
//! `cargo run --release --example play_ode --features output`

use easy_piano_audio::output::Player;
use easy_piano_audio::{Instrument, Part, SampleBank, Sound};
use std::path::PathBuf;
use std::time::{Duration, Instant};

fn main() {
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let bank = SampleBank::load_app_assets(&dir.join("../app"));
    let mut player = Player::start().expect("open output");
    *player.bank_mut() = bank;
    player.commit();
    let text = std::fs::read_to_string(dir.join("tests/fixtures/ode_to_joy_events.csv")).unwrap();
    for l in text
        .lines()
        .filter(|l| !l.starts_with('#') && !l.trim().is_empty())
    {
        let f: Vec<&str> = l.split(',').collect();
        let (pitch, start, dur, vel): (u8, f64, f64, u8) = (
            f[2].parse().unwrap(),
            f[3].parse().unwrap(),
            f[4].parse().unwrap(),
            f[5].parse().unwrap(),
        );
        let sound = match f[0] {
            "drum" => Sound::Drum {
                gm: pitch,
                velocity: vel,
            },
            inst => Sound::Note {
                instrument: Instrument::from_key(inst).unwrap(),
                part: Part::from_key(f[1]),
                pitch,
                dur: player.frames(dur),
                velocity: vel,
            },
        };
        player.schedule_in(start, sound);
    }
    let wall = Instant::now();
    let clock0 = player.now_secs();
    std::thread::sleep(Duration::from_secs(21));
    let drift_ms = ((player.now_secs() - clock0) - wall.elapsed().as_secs_f64()) * 1000.0;
    println!(
        "rate {} Hz, reported output latency {:.1} ms, audio clock vs wall over 21 s: {:+.1} ms",
        player.rate(),
        player.latency_ms(),
        drift_ms
    );
}
