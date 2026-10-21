//! Native audio output (D30 stage 2): the engine runs inside the platform's
//! audio callback (WASAPI, CoreAudio, AAudio via cpal). The callback owns the
//! engine; the app talks to it through a channel, so the audio thread never
//! waits on a lock. The frames rendered so far are the audio clock.

use crate::bank::SampleBank;
use crate::engine::{Engine, Event, Sound};
use crate::mix::Part;
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::Arc;

enum Command {
    Schedule(Event),
    NoteOn(u8, u8),
    NoteOff(u8),
    Level(Part, f32),
    StopAll,
    Bank(Arc<SampleBank>),
}

/// Handle to a running output stream.
pub struct Player {
    tx: Sender<Command>,
    clock: Arc<AtomicU64>,
    latency_us: Arc<AtomicU32>,
    rate: u32,
    bank: SampleBank,
}

impl Player {
    /// Opens the default output device and starts the engine on it.
    pub fn start() -> Result<Player, String> {
        let (tx, rx) = mpsc::channel::<Command>();
        let clock = Arc::new(AtomicU64::new(0));
        let latency_us = Arc::new(AtomicU32::new(0));
        let (ready_tx, ready_rx) = mpsc::channel::<Result<u32, String>>();
        let (c, l) = (clock.clone(), latency_us.clone());
        // cpal streams are not Send on every platform: build and keep the
        // stream on its own thread for the life of the app.
        std::thread::Builder::new()
            .name("easy-piano-audio".into())
            .spawn(move || match open_stream(rx, c, l) {
                Ok((stream, rate)) => {
                    let _ = ready_tx.send(Ok(rate));
                    let _keep = stream;
                    loop {
                        std::thread::park();
                    }
                }
                Err(e) => {
                    let _ = ready_tx.send(Err(e));
                }
            })
            .map_err(|e| e.to_string())?;
        let rate = ready_rx.recv().map_err(|e| e.to_string())??;
        Ok(Player {
            tx,
            clock,
            latency_us,
            rate,
            bank: SampleBank::default(),
        })
    }

    pub fn rate(&self) -> u32 {
        self.rate
    }

    /// Audio clock: seconds of audio rendered so far.
    pub fn now_secs(&self) -> f64 {
        self.clock.load(Ordering::Relaxed) as f64 / self.rate as f64
    }

    /// Output latency the platform reports (callback to speaker), in ms.
    pub fn latency_ms(&self) -> f64 {
        self.latency_us.load(Ordering::Relaxed) as f64 / 1000.0
    }

    /// The bank being built; [Player::commit] hands a copy to the engine.
    pub fn bank_mut(&mut self) -> &mut SampleBank {
        &mut self.bank
    }

    pub fn commit(&self) {
        let _ = self.tx.send(Command::Bank(Arc::new(self.bank.clone())));
    }

    /// Plays [sound] [secs] seconds from now (on the audio clock).
    pub fn schedule_in(&self, secs: f64, sound: Sound) {
        let at = self.clock.load(Ordering::Relaxed) + (secs.max(0.0) * self.rate as f64) as u64;
        let _ = self.tx.send(Command::Schedule(Event { at, sound }));
    }

    /// Frames for a duration in seconds at the output rate.
    pub fn frames(&self, secs: f64) -> u64 {
        (secs.max(0.0) * self.rate as f64) as u64
    }

    pub fn note_on(&self, pitch: u8, velocity: u8) {
        let _ = self.tx.send(Command::NoteOn(pitch, velocity));
    }

    pub fn note_off(&self, pitch: u8) {
        let _ = self.tx.send(Command::NoteOff(pitch));
    }

    pub fn set_part_level(&self, part: Part, level: f32) {
        let _ = self.tx.send(Command::Level(part, level));
    }

    pub fn stop_all(&self) {
        let _ = self.tx.send(Command::StopAll);
    }
}

fn open_stream(
    rx: Receiver<Command>,
    clock: Arc<AtomicU64>,
    latency_us: Arc<AtomicU32>,
) -> Result<(cpal::Stream, u32), String> {
    let host = cpal::default_host();
    let device = host.default_output_device().ok_or("no output device")?;
    let config = device.default_output_config().map_err(|e| e.to_string())?;
    let rate = config.sample_rate().0;
    let channels = config.channels() as usize;
    let format = config.sample_format();
    let mut render = Render {
        engine: Engine::new(rate, Arc::new(SampleBank::default())),
        rx,
        scratch: Vec::new(),
        clock,
        latency_us,
    };

    let err = |e| eprintln!("audio stream error: {e}");
    let cfg: cpal::StreamConfig = config.into();
    let stream = match format {
        cpal::SampleFormat::F32 => device.build_output_stream(
            &cfg,
            move |out: &mut [f32], info| {
                let stereo = render.fill(out.len() / channels, info);
                spread(out, stereo, channels, |v| v);
            },
            err,
            None,
        ),
        cpal::SampleFormat::I16 => device.build_output_stream(
            &cfg,
            move |out: &mut [i16], info| {
                let stereo = render.fill(out.len() / channels, info);
                spread(out, stereo, channels, |v| {
                    (v.clamp(-1.0, 1.0) * 32767.0) as i16
                });
            },
            err,
            None,
        ),
        other => return Err(format!("unsupported sample format {other:?}")),
    }
    .map_err(|e| e.to_string())?;
    stream.play().map_err(|e| e.to_string())?;
    Ok((stream, rate))
}

/// State owned by the audio callback.
struct Render {
    engine: Engine,
    rx: Receiver<Command>,
    scratch: Vec<f32>,
    clock: Arc<AtomicU64>,
    latency_us: Arc<AtomicU32>,
}

impl Render {
    /// Applies pending commands and renders [frames] stereo frames.
    fn fill(&mut self, frames: usize, info: &cpal::OutputCallbackInfo) -> &[f32] {
        while let Ok(cmd) = self.rx.try_recv() {
            match cmd {
                Command::Schedule(e) => self.engine.schedule(e),
                Command::NoteOn(p, v) => self.engine.note_on(p, v),
                Command::NoteOff(p) => self.engine.note_off(p),
                Command::Level(part, l) => self.engine.set_part_level(part, l),
                Command::StopAll => self.engine.stop_all(),
                Command::Bank(b) => self.engine.set_bank(b),
            }
        }
        let ts = info.timestamp();
        if let Some(d) = ts.playback.duration_since(&ts.callback) {
            self.latency_us
                .store(d.as_micros() as u32, Ordering::Relaxed);
        }
        if self.scratch.len() < frames * 2 {
            self.scratch.resize(frames * 2, 0.0);
        }
        self.engine.render(&mut self.scratch[..frames * 2]);
        self.clock.store(self.engine.now(), Ordering::Relaxed);
        &self.scratch[..frames * 2]
    }
}

/// Copies engine stereo into a device buffer with any channel count (mono
/// gets the average; extra channels stay silent).
fn spread<T: Copy + Default>(
    out: &mut [T],
    stereo: &[f32],
    channels: usize,
    conv: impl Fn(f32) -> T,
) {
    for (i, frame) in out.chunks_mut(channels).enumerate() {
        let (l, r) = (stereo[2 * i], stereo[2 * i + 1]);
        match channels {
            1 => frame[0] = conv((l + r) * 0.5),
            _ => {
                frame[0] = conv(l);
                frame[1] = conv(r);
                for s in frame.iter_mut().skip(2) {
                    *s = T::default();
                }
            }
        }
    }
}
