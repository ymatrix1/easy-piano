//! The audio engine for the web AudioWorklet (D30 stage 3). Plain C-ABI
//! exports, no wasm-bindgen: an AudioWorkletGlobalScope has no TextDecoder
//! or fetch, so `app/web/audio_worklet.js` instantiates this module itself
//! and calls these functions directly. One engine per module instance; the
//! worklet is single-threaded.
//!
//! Codes shared with the worklet and `piano_synth_web.dart`:
//! - sample kind: 0 piano, 1 bass, 2 strings, 3 choir, 4 drum (key = GM
//!   number, once per round-robin hit), 5 soft hat, 6 click, 7 accent click
//! - instrument: 0 piano, 1 bass, 2 strings, 3 choir
//! - part: index into [Part::ALL] (0 live, 1 piano, 2 ACC, 3 DRUMS, 4 BASS,
//!   5 PAD, 6 CHOIR, 7 sfx)

use easy_piano_audio::{Engine, Event, Instrument, Part, Sample, SampleBank, Sound};
use std::cell::RefCell;
use std::sync::Arc;

/// Frames per render call: one Web Audio render quantum.
pub const QUANTUM: usize = 128;

struct State {
    engine: Engine,
    /// Bank being filled; handed to the engine on [ep_commit].
    bank: SampleBank,
    out: Vec<f32>,
    /// Scratch for incoming PCM (planar float channels).
    input: Vec<f32>,
}

thread_local! {
    static STATE: RefCell<Option<State>> = const { RefCell::new(None) };
}

fn with<R: Default>(f: impl FnOnce(&mut State) -> R) -> R {
    STATE.with(|s| s.borrow_mut().as_mut().map(f).unwrap_or_default())
}

fn instrument(code: u32) -> Option<Instrument> {
    Instrument::ALL.get(code as usize).copied()
}

fn part(code: u32) -> Part {
    Part::ALL.get(code as usize).copied().unwrap_or(Part::Piano)
}

fn velocity(v: u32) -> u8 {
    v.clamp(1, 127) as u8
}

/// Starts an engine at the context's sample rate (call once).
#[no_mangle]
pub extern "C" fn ep_init(rate: u32) {
    STATE.with(|s| {
        *s.borrow_mut() = Some(State {
            engine: Engine::new(rate, Arc::new(SampleBank::default())),
            bank: SampleBank::default(),
            out: vec![0.0; 2 * QUANTUM],
            input: Vec::new(),
        })
    });
}

/// Room for `floats` input samples; returns where to write them.
#[no_mangle]
pub extern "C" fn ep_input(floats: usize) -> *mut f32 {
    with(|s| {
        s.input.clear();
        s.input.resize(floats, 0.0);
        s.input.as_mut_ptr() as usize
    }) as *mut f32
}

/// Adds the PCM written to [ep_input] (`channels` planar channels of
/// `frames` each at `rate`) to the bank being built.
#[no_mangle]
pub extern "C" fn ep_add_sample(kind: u32, key: u32, channels: u32, frames: usize, rate: u32) {
    with(|s| {
        let chans: Vec<Vec<f32>> = s
            .input
            .chunks(frames.max(1))
            .take(channels.clamp(1, 2) as usize)
            .map(<[f32]>::to_vec)
            .collect();
        if chans.is_empty() || chans[0].len() < frames {
            return;
        }
        let looped = instrument(kind).and_then(|i| i.spec().3);
        let sample = Arc::new(Sample::from_channels(&chans, rate, looped));
        let bank = &mut s.bank;
        match kind {
            0..=3 => {
                if let Some(i) = instrument(kind) {
                    bank.pitched.entry(i).or_default().insert(key as u8, sample);
                }
            }
            4 => bank.drums.entry(key as u8).or_default().push(sample),
            5 => bank.soft_hat = Some(sample),
            6 => bank.click = Some(sample),
            7 => bank.click_accent = Some(sample),
            _ => {}
        }
        s.input = Vec::new();
    })
}

/// Hands the samples added so far to the engine.
#[no_mangle]
pub extern "C" fn ep_commit() {
    with(|s| s.engine.set_bank(Arc::new(s.bank.clone())))
}

fn frames_in(s: &State, sec: f64) -> u64 {
    (sec.max(0.0) * s.engine.rate() as f64).round() as u64
}

fn schedule_in(s: &mut State, start_sec: f64, sound: Sound) {
    let at = s.engine.now() + frames_in(s, start_sec);
    s.engine.schedule(Event { at, sound });
}

/// A pitched note `start_sec` from now on the engine clock.
#[no_mangle]
pub extern "C" fn ep_note(
    inst: u32,
    part_code: u32,
    pitch: u32,
    start_sec: f64,
    dur_sec: f64,
    vel: u32,
) {
    let Some(instrument) = instrument(inst) else {
        return;
    };
    with(|s| {
        let dur = frames_in(s, dur_sec);
        schedule_in(
            s,
            start_sec,
            Sound::Note {
                instrument,
                part: part(part_code),
                pitch: pitch.min(127) as u8,
                dur,
                velocity: velocity(vel),
            },
        )
    })
}

#[no_mangle]
pub extern "C" fn ep_drum(gm: u32, start_sec: f64, vel: u32) {
    with(|s| {
        schedule_in(
            s,
            start_sec,
            Sound::Drum {
                gm: gm.min(127) as u8,
                velocity: velocity(vel),
            },
        )
    })
}

#[no_mangle]
pub extern "C" fn ep_click(start_sec: f64, accent: u32) {
    with(|s| {
        schedule_in(
            s,
            start_sec,
            Sound::Click {
                accent: accent != 0,
            },
        )
    })
}

/// Learner key down / up, now (live bus, no dynamics).
#[no_mangle]
pub extern "C" fn ep_note_on(pitch: u32, vel: u32) {
    with(|s| s.engine.note_on(pitch.min(127) as u8, velocity(vel)))
}

#[no_mangle]
pub extern "C" fn ep_note_off(pitch: u32) {
    with(|s| s.engine.note_off(pitch.min(127) as u8))
}

#[no_mangle]
pub extern "C" fn ep_set_part_level(part_code: u32, level: f32) {
    with(|s| s.engine.set_part_level(part(part_code), level))
}

#[no_mangle]
pub extern "C" fn ep_stop_all() {
    with(|s| s.engine.stop_all())
}

/// Renders one quantum; returns the interleaved stereo frames.
#[no_mangle]
pub extern "C" fn ep_render() -> *const f32 {
    with(|s| {
        s.engine.render(&mut s.out);
        s.out.as_ptr() as usize
    }) as *const f32
}

/// Audio clock: frames rendered so far.
#[no_mangle]
pub extern "C" fn ep_now() -> f64 {
    with(|s| s.engine.now() as f64)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn quantum() -> Vec<f32> {
        let p = ep_render();
        unsafe { std::slice::from_raw_parts(p, 2 * QUANTUM) }.to_vec()
    }

    #[test]
    fn plays_a_key_from_added_pcm() {
        ep_init(1000);
        let frames = 1000;
        let p = ep_input(2 * frames);
        let pcm = unsafe { std::slice::from_raw_parts_mut(p, 2 * frames) };
        pcm.fill(0.5);
        ep_add_sample(0, 60, 2, frames, 1000);
        ep_commit();
        assert!(quantum().iter().all(|v| *v == 0.0), "silent before a key");
        ep_note_on(60, 127);
        assert!(quantum()[2 * 100].abs() > 0.1, "key sounds");
        assert_eq!(ep_now(), 2.0 * QUANTUM as f64);
    }

    #[test]
    fn scheduled_drum_starts_on_its_frame() {
        ep_init(1000);
        let p = ep_input(500);
        unsafe { std::slice::from_raw_parts_mut(p, 500) }.fill(0.5);
        ep_add_sample(4, 38, 1, 500, 1000);
        ep_commit();
        ep_drum(38, 0.2, 127); // frame 200: in the second quantum
        assert!(quantum().iter().all(|v| *v == 0.0));
        let q = quantum();
        let first = q.iter().position(|v| *v != 0.0).unwrap() / 2;
        assert_eq!(QUANTUM + first, 200);
    }
}
