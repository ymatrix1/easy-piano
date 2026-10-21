//! Parity with the web build (D30 stage 1): render the Ode to Joy play-along
//! events the app schedules and compare each part's level with what Web
//! Audio measured for the same events.

use easy_piano_audio::{Engine, Event, Instrument, Part, SampleBank, Sound};
use std::path::PathBuf;
use std::sync::{Arc, OnceLock};

const RATE: u32 = 44_100;
const SECONDS: f32 = 24.0;
const PARTS: [Part; 5] = [Part::Acc, Part::Bass, Part::Drums, Part::Pad, Part::Choir];

fn here(rel: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(rel)
}

fn bank() -> Arc<SampleBank> {
    static BANK: OnceLock<Arc<SampleBank>> = OnceLock::new();
    BANK.get_or_init(|| Arc::new(SampleBank::load_app_assets(&here("../app"))))
        .clone()
}

fn events() -> Vec<Event> {
    let text = std::fs::read_to_string(here("tests/fixtures/ode_to_joy_events.csv")).unwrap();
    let frames = |s: &str| (s.parse::<f64>().unwrap() * RATE as f64).round() as u64;
    text.lines()
        .filter(|l| !l.starts_with('#') && !l.trim().is_empty())
        .map(|l| {
            let f: Vec<&str> = l.split(',').collect();
            let pitch: u8 = f[2].parse().unwrap();
            let velocity: u8 = f[5].parse().unwrap();
            let sound = match f[0] {
                "drum" => Sound::Drum {
                    gm: pitch,
                    velocity,
                },
                "click" => Sound::Click { accent: pitch == 1 },
                inst => Sound::Note {
                    instrument: Instrument::from_key(inst).unwrap(),
                    part: Part::from_key(f[1]),
                    pitch,
                    dur: frames(f[4]),
                    velocity,
                },
            };
            Event {
                at: frames(f[3]),
                sound,
            }
        })
        .collect()
}

fn web_levels() -> Vec<(String, f32, f32)> {
    std::fs::read_to_string(here("tests/fixtures/ode_to_joy_web_levels.csv"))
        .unwrap()
        .lines()
        .filter(|l| !l.starts_with('#') && !l.trim().is_empty())
        .map(|l| {
            let f: Vec<&str> = l.split(',').collect();
            (
                f[0].to_string(),
                f[1].parse().unwrap(),
                f[2].parse().unwrap(),
            )
        })
        .collect()
}

/// Whole-render RMS and sample peak in dBFS (same definition as the web
/// probe).
fn render(solo: Option<Part>) -> (f32, f32) {
    let mut engine = Engine::new(RATE, bank());
    if let Some(solo) = solo {
        for p in Part::ALL {
            if p != solo {
                engine.set_part_level(p, 0.0);
            }
        }
    }
    for e in events() {
        engine.schedule(e);
    }
    let mut buf = vec![0f32; 2 * (SECONDS * RATE as f32) as usize];
    engine.render(&mut buf);
    let sum: f64 = buf.iter().map(|v| (*v as f64).powi(2)).sum();
    let peak = buf.iter().fold(0f32, |m, v| m.max(v.abs()));
    let db = |x: f64| 10.0 * x.max(1e-12).log10();
    (
        db(sum / buf.len() as f64) as f32,
        20.0 * peak.max(1e-9).log10(),
    )
}

fn key(p: Part) -> &'static str {
    match p {
        Part::Acc => "ACC",
        Part::Bass => "BASS",
        Part::Drums => "DRUMS",
        Part::Pad => "PAD",
        Part::Choir => "CHOIR",
        _ => unreachable!(),
    }
}

#[test]
fn part_balance_matches_web_within_2_db() {
    let web = web_levels();
    let web_rms = |k: &str| web.iter().find(|w| w.0 == k).unwrap().1;
    let acc = render(Some(Part::Acc)).0;
    let mut report = format!(
        "{:<6} {:>9} {:>9} {:>9} {:>9}\n",
        "part", "rust", "web", "rust-ACC", "web-ACC"
    );
    let mut worst = 0f32;
    for p in PARTS {
        let (rms, _) = if p == Part::Acc {
            (acc, 0.0)
        } else {
            render(Some(p))
        };
        let rel = rms - acc;
        let web_rel = web_rms(key(p)) - web_rms("ACC");
        worst = worst.max((rel - web_rel).abs());
        report += &format!(
            "{:<6} {:>9.2} {:>9.2} {:>9.2} {:>9.2}\n",
            key(p),
            rms,
            web_rms(key(p)),
            rel,
            web_rel
        );
    }
    println!("{report}worst balance difference: {worst:.2} dB");
    assert!(
        worst <= 2.0,
        "part balance differs from web by {worst:.2} dB\n{report}"
    );
}

#[test]
fn full_mix_stays_under_full_scale() {
    let (rms, peak) = render(None);
    let web = web_levels();
    let (_, web_rms, web_peak) = web.iter().find(|w| w.0 == "mix").unwrap();
    println!("mix: rust rms {rms:.2} peak {peak:.2} dBFS; web rms {web_rms:.2} peak {web_peak:.2}");
    assert!(peak < 0.0, "mix peak {peak:.2} dBFS");
    assert!(
        (rms - web_rms).abs() <= 3.0,
        "mix level {rms:.2} vs web {web_rms:.2} dBFS"
    );
}

#[test]
fn decoded_samples_fit_phone_memory() {
    let bank = bank();
    // What the web build holds today: every file decoded in full as float32
    // stereo (AudioBuffer).
    let mut web_bytes = 0usize;
    for inst in Instrument::ALL {
        for (_, file) in inst.files() {
            let bytes = std::fs::read(here("../app").join(file)).unwrap();
            let (ch, _) = easy_piano_audio::decode::decode_mp3(bytes).unwrap();
            web_bytes += ch[0].len() * 2 * 4;
        }
    }
    let ours = bank.bytes();
    println!(
        "pitched + band samples: web float32 full length {:.1} MB, engine 16-bit trimmed {:.1} MB (all incl. drums)",
        web_bytes as f64 / 1e6,
        ours as f64 / 1e6
    );
    assert!(
        ours * 2 < web_bytes,
        "engine should hold under half of the web footprint"
    );
}
