//! Native side of `api::audio`: the running output stream (D30 stage 2).
use easy_piano_audio::bank::{Instrument, Sample};
use easy_piano_audio::decode::decode_mp3;
use easy_piano_audio::output::Player;
use easy_piano_audio::{Part, Sound};
use std::sync::{Arc, Mutex, OnceLock};

pub fn player() -> &'static Mutex<Option<Player>> {
    static P: OnceLock<Mutex<Option<Player>>> = OnceLock::new();
    P.get_or_init(|| Mutex::new(None))
}

pub fn with<R>(f: impl FnOnce(&mut Player) -> R) -> Option<R> {
    player().lock().ok()?.as_mut().map(f)
}

pub fn start() -> Result<crate::api::audio::AudioInfo, String> {
    let mut guard = player().lock().map_err(|e| e.to_string())?;
    if guard.is_none() {
        *guard = Some(Player::start()?);
    }
    let p = guard.as_ref().unwrap();
    Ok(crate::api::audio::AudioInfo { sample_rate: p.rate(), latency_ms: p.latency_ms() })
}

pub fn add_sample(kind: &str, key: u8, mp3: Vec<u8>) -> Result<(), String> {
    let (ch, rate) = decode_mp3(mp3)?;
    let looped = Instrument::from_key(kind).and_then(|i| i.spec().3);
    let sample = Arc::new(Sample::from_channels(&ch, rate, looped));
    with(|p| {
        let bank = p.bank_mut();
        match kind {
            "drum" => bank.drums.entry(key).or_default().push(sample),
            "soft_hat" => bank.soft_hat = Some(sample),
            "click" => bank.click = Some(sample),
            "click_accent" => bank.click_accent = Some(sample),
            inst => {
                if let Some(i) = Instrument::from_key(inst) {
                    bank.pitched.entry(i).or_default().insert(key, sample);
                }
            }
        }
    })
    .ok_or_else(|| "audio not started".to_string())
}

pub fn note(instrument: &str, part: &str, pitch: u8, start: f64, dur: f64, velocity: u8) {
    let Some(instrument) = Instrument::from_key(instrument) else { return };
    with(|p| {
        let dur = p.frames(dur);
        p.schedule_in(start, Sound::Note { instrument, part: Part::from_key(part), pitch, dur, velocity })
    });
}

pub fn sound(start: f64, s: Sound) {
    with(|p| p.schedule_in(start, s));
}

pub fn part(key: &str) -> Part {
    Part::from_key(key)
}
