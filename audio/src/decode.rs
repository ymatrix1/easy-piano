//! MP3 decoding and loading the app's bundled samples (native builds and
//! tests; web passes PCM decoded by the browser instead, D30).

use crate::bank::{Instrument, Sample, SampleBank, CLICK_FILES, DRUM_FILES, SOFT_HAT_FILE};
use std::path::Path;
use std::sync::Arc;
use symphonia::core::audio::SampleBuffer;
use symphonia::core::codecs::DecoderOptions;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;

/// Decodes MP3 bytes to float channels and the sample rate.
pub fn decode_mp3(bytes: Vec<u8>) -> Result<(Vec<Vec<f32>>, u32), String> {
    let mss = MediaSourceStream::new(Box::new(std::io::Cursor::new(bytes)), Default::default());
    let mut hint = Hint::new();
    hint.with_extension("mp3");
    let fmt_opts = FormatOptions {
        enable_gapless: true,
        ..Default::default()
    };
    let probed = symphonia::default::get_probe()
        .format(&hint, mss, &fmt_opts, &MetadataOptions::default())
        .map_err(|e| e.to_string())?;
    let mut format = probed.format;
    let track = format.default_track().ok_or("no track")?;
    let track_id = track.id;
    let rate = track.codec_params.sample_rate.ok_or("no rate")?;
    let mut decoder = symphonia::default::get_codecs()
        .make(&track.codec_params, &DecoderOptions::default())
        .map_err(|e| e.to_string())?;
    let mut channels: Vec<Vec<f32>> = Vec::new();
    while let Ok(packet) = format.next_packet() {
        if packet.track_id() != track_id {
            continue;
        }
        let Ok(decoded) = decoder.decode(&packet) else {
            continue;
        };
        let spec = *decoded.spec();
        let n = spec.channels.count();
        let mut buf = SampleBuffer::<f32>::new(decoded.capacity() as u64, spec);
        buf.copy_interleaved_ref(decoded);
        if channels.is_empty() {
            channels = vec![Vec::new(); n];
        }
        for (i, v) in buf.samples().iter().enumerate() {
            channels[i % n].push(*v);
        }
    }
    if channels.is_empty() {
        return Err("no audio".into());
    }
    Ok((channels, rate))
}

fn load(path: &Path, looped: Option<(f32, f32)>) -> Option<Arc<Sample>> {
    let bytes = std::fs::read(path).ok()?;
    let (ch, rate) = decode_mp3(bytes).ok()?;
    Some(Arc::new(Sample::from_channels(&ch, rate, looped)))
}

impl SampleBank {
    /// Loads every bundled sample from the app folder (the one holding
    /// `assets/`). Missing files leave gaps that neighbours cover.
    pub fn load_app_assets(app_dir: &Path) -> SampleBank {
        let mut bank = SampleBank::default();
        for inst in Instrument::ALL {
            let looped = inst.spec().3;
            let map = bank.pitched.entry(inst).or_default();
            for (pitch, file) in inst.files() {
                if let Some(s) = load(&app_dir.join(&file), looped) {
                    map.insert(pitch, s);
                }
            }
        }
        let drums = app_dir.join("assets/band/drums");
        for (gm, files) in DRUM_FILES {
            let hits: Vec<Arc<Sample>> = files
                .iter()
                .filter_map(|f| load(&drums.join(format!("{f}.mp3")), None))
                .collect();
            if !hits.is_empty() {
                bank.drums.insert(gm, hits);
            }
        }
        bank.soft_hat = load(&drums.join(format!("{SOFT_HAT_FILE}.mp3")), None);
        bank.click = load(&drums.join(format!("{}.mp3", CLICK_FILES[0])), None);
        bank.click_accent = load(&drums.join(format!("{}.mp3", CLICK_FILES[1])), None);
        bank
    }
}
