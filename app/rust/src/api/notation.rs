//! Thin bridge over `easy_piano_core`. Keep logic in core; only adapt types here.

use easy_piano_core::pitch;

/// Parses a pitch token (`C4`, `F#3`) to a MIDI note number.
#[flutter_rust_bridge::frb(sync)]
pub fn parse_pitch(token: String) -> Result<u8, String> {
    pitch::parse_pitch(&token).map_err(|e| format!("{e:?}"))
}

/// Spells a MIDI note number with sharps (`C#4`).
#[flutter_rust_bridge::frb(sync)]
pub fn pitch_name(midi: u8) -> String {
    pitch::pitch_name(midi)
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
