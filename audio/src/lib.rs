//! Easy Piano audio engine (D30): one sampler, mixer and effects chain for
//! every platform. Pure: it renders frames into buffers; platform output
//! (cpal/Oboe/CoreAudio, or a web AudioWorklet) lives outside this crate.

pub mod bank;
#[cfg(feature = "decode")]
pub mod decode;
pub mod dsp;
pub mod engine;
pub mod mix;

pub use bank::{Instrument, Sample, SampleBank};
pub use engine::{Engine, Event, Sound};
pub use mix::Part;
