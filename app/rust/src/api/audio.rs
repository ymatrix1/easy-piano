//! Bridge over the Rust audio engine (`easy_piano_audio`, D30) for native
//! platforms. Web keeps its Web Audio synth until stage 3, so on wasm every
//! function is a harmless no-op.

use flutter_rust_bridge::frb;

/// What the output stream reports once started.
pub struct AudioInfo {
    pub sample_rate: u32,
    /// Platform-reported output latency (callback to speaker), ms.
    pub latency_ms: f64,
}

#[cfg(not(target_arch = "wasm32"))]
use crate::native_audio as imp;

/// Opens the default output device and starts the engine. Safe to call
/// again.
pub fn audio_start() -> Result<AudioInfo, String> {
    #[cfg(not(target_arch = "wasm32"))]
    return imp::start();
    #[cfg(target_arch = "wasm32")]
    Err("web uses Web Audio".into())
}

/// Decodes one bundled MP3 into the bank being built. [kind]: `piano`,
/// `bass`, `strings`, `choir` (key = MIDI pitch), `drum` (key = GM number,
/// call once per round-robin hit), `soft_hat`, `click`, `click_accent`.
pub fn audio_add_sample(kind: String, key: u8, mp3: Vec<u8>) -> Result<(), String> {
    #[cfg(not(target_arch = "wasm32"))]
    return imp::add_sample(&kind, key, mp3);
    #[cfg(target_arch = "wasm32")]
    {
        let _ = (kind, key, mp3);
        Ok(())
    }
}

/// Hands the samples added so far to the engine.
#[frb(sync)]
pub fn audio_commit() {
    #[cfg(not(target_arch = "wasm32"))]
    imp::with(|p| p.commit());
}

/// Schedules a pitched note [start_sec] from now on the audio clock.
#[frb(sync)]
pub fn audio_note(instrument: String, part: String, pitch: u8, start_sec: f64, dur_sec: f64, velocity: u8) {
    #[cfg(not(target_arch = "wasm32"))]
    imp::note(&instrument, &part, pitch, start_sec, dur_sec, velocity);
    #[cfg(target_arch = "wasm32")]
    let _ = (instrument, part, pitch, start_sec, dur_sec, velocity);
}

/// Schedules a drum hit (General MIDI number).
#[frb(sync)]
pub fn audio_drum(gm: u8, start_sec: f64, velocity: u8) {
    #[cfg(not(target_arch = "wasm32"))]
    imp::sound(start_sec, easy_piano_audio::Sound::Drum { gm, velocity });
    #[cfg(target_arch = "wasm32")]
    let _ = (gm, start_sec, velocity);
}

/// Schedules a metronome click.
#[frb(sync)]
pub fn audio_click(start_sec: f64, accent: bool) {
    #[cfg(not(target_arch = "wasm32"))]
    imp::sound(start_sec, easy_piano_audio::Sound::Click { accent });
    #[cfg(target_arch = "wasm32")]
    let _ = (start_sec, accent);
}

/// Learner key down / up, now (live bus, no dynamics).
#[frb(sync)]
pub fn audio_note_on(pitch: u8, velocity: u8) {
    #[cfg(not(target_arch = "wasm32"))]
    imp::with(|p| p.note_on(pitch, velocity));
    #[cfg(target_arch = "wasm32")]
    let _ = (pitch, velocity);
}

#[frb(sync)]
pub fn audio_note_off(pitch: u8) {
    #[cfg(not(target_arch = "wasm32"))]
    imp::with(|p| p.note_off(pitch));
    #[cfg(target_arch = "wasm32")]
    let _ = pitch;
}

/// Scales a part's bus (1 = default mix).
#[frb(sync)]
pub fn audio_set_part_level(part: String, level: f64) {
    #[cfg(not(target_arch = "wasm32"))]
    imp::with(|p| p.set_part_level(imp::part(&part), level as f32));
    #[cfg(target_arch = "wasm32")]
    let _ = (part, level);
}

#[frb(sync)]
pub fn audio_stop_all() {
    #[cfg(not(target_arch = "wasm32"))]
    imp::with(|p| p.stop_all());
}

/// Audio clock in seconds (frames rendered / rate); 0 before start.
#[frb(sync)]
pub fn audio_now_sec() -> f64 {
    #[cfg(not(target_arch = "wasm32"))]
    return imp::with(|p| p.now_secs()).unwrap_or(0.0);
    #[cfg(target_arch = "wasm32")]
    0.0
}
