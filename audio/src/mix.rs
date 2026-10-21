//! The mix: one place for every level, send and curve (D22, D30). Values
//! came from offline measurements of Ode to Joy play-along on web
//! (`docs/research/instrument-samples.md`).

/// Where a sound goes. Each part has its own gain bus and reverb send.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Part {
    /// The learner's own keys: skips the dynamics (no look-ahead latency).
    Live,
    /// App-played piano that is not a score part (pre-listen, hand parts).
    Piano,
    Acc,
    Drums,
    Bass,
    Pad,
    Choir,
    /// Menu cues on the piano (not used by default; kept for parity).
    Sfx,
}

impl Part {
    pub const ALL: [Part; 8] = [
        Part::Live,
        Part::Piano,
        Part::Acc,
        Part::Drums,
        Part::Bass,
        Part::Pad,
        Part::Choir,
        Part::Sfx,
    ];

    pub fn index(self) -> usize {
        self as usize
    }

    /// Score part key (`ACC`, `DRUMS`, ...) or `piano` / `live`.
    pub fn from_key(key: &str) -> Part {
        match key {
            "live" => Part::Live,
            "ACC" => Part::Acc,
            "DRUMS" => Part::Drums,
            "BASS" => Part::Bass,
            "PAD" => Part::Pad,
            "CHOIR" => Part::Choir,
            "sfx" => Part::Sfx,
            _ => Part::Piano,
        }
    }

    /// Default bus gain (linear).
    pub fn level(self) -> f32 {
        match self {
            Part::Live | Part::Piano | Part::Acc => 1.0,
            Part::Drums => 0.19,
            Part::Bass => 1.1,
            Part::Pad => 0.37,
            Part::Choir => 0.67,
            Part::Sfx => 0.6,
        }
    }

    /// Reverb send (linear): pads and voices sit further back than drums.
    pub fn reverb_send(self) -> f32 {
        match self {
            Part::Live => 0.12,
            Part::Piano => 0.14,
            Part::Acc => 0.16,
            Part::Drums => 0.08,
            Part::Bass => 0.03,
            Part::Pad => 0.35,
            Part::Choir => 0.40,
            Part::Sfx => 0.22,
        }
    }
}

/// Velocity -> gain: a gentle curve so soft notes stay audible.
pub fn velocity_gain(velocity: u8) -> f32 {
    (velocity.clamp(1, 127) as f32 / 127.0).powf(1.5)
}

/// Piano brightness: low-pass cutoff in Hz for a velocity (soft = darker).
pub fn piano_cutoff_hz(velocity: u8) -> f32 {
    let v = velocity.clamp(1, 127) as f32 / 127.0;
    1200.0 + 14000.0 * v * v
}

/// Closed hi-hats softer than this use the lighter hit.
pub const SOFT_HAT_BELOW: u8 = 72;

/// Glue compressor on the band (threshold dB, knee dB, ratio, attack s,
/// release s).
pub const GLUE: (f32, f32, f32, f32, f32) = (-20.0, 12.0, 2.5, 0.01, 0.25);

/// Limiter after the glue.
pub const LIMITER: (f32, f32, f32, f32, f32) = (-3.0, 0.0, 20.0, 0.001, 0.1);

/// Generated reverb impulse length in seconds.
pub const REVERB_SECONDS: f32 = 1.8;

/// Envelope per instrument: (attack s, release time constant s).
pub fn envelope(instrument: crate::bank::Instrument) -> (f32, f32) {
    use crate::bank::Instrument::*;
    match instrument {
        Piano => (0.002, 0.12),
        Bass => (0.002, 0.06),
        Strings => (0.12, 0.25),
        Choir => (0.15, 0.25),
    }
}
