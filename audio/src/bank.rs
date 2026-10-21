//! Decoded samples, held compactly: 16-bit stereo, quiet tails trimmed.

use std::collections::BTreeMap;
use std::sync::Arc;

/// Pitched instruments (sample every 3 semitones, nearest one pitch-shifted).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum Instrument {
    Piano,
    Bass,
    Strings,
    Choir,
}

impl Instrument {
    pub const ALL: [Instrument; 4] = [
        Instrument::Piano,
        Instrument::Bass,
        Instrument::Strings,
        Instrument::Choir,
    ];

    /// Asset folder under `app/`, lowest and highest octave (the top one has
    /// only its C), and the steady stretch to loop for long notes.
    pub fn spec(self) -> (&'static str, i32, i32, Option<(f32, f32)>) {
        match self {
            Instrument::Piano => ("assets/piano", 1, 8, None),
            Instrument::Bass => ("assets/band/bass", 1, 4, None),
            Instrument::Strings => ("assets/band/strings", 3, 6, Some((0.5, 2.9))),
            Instrument::Choir => ("assets/band/choir", 3, 6, Some((0.5, 2.9))),
        }
    }

    pub fn from_key(key: &str) -> Option<Instrument> {
        match key {
            "piano" => Some(Instrument::Piano),
            "bass" => Some(Instrument::Bass),
            "strings" => Some(Instrument::Strings),
            "choir" => Some(Instrument::Choir),
            _ => None,
        }
    }

    /// (MIDI pitch, file stem) for every sample of the instrument.
    pub fn files(self) -> Vec<(u8, String)> {
        const NAMES: [&str; 4] = ["C", "Eb", "Gb", "A"];
        let (dir, low, high, _) = self.spec();
        let mut out = Vec::new();
        for octave in low..=high {
            for (k, name) in NAMES.iter().enumerate() {
                if octave == high && k > 0 {
                    break; // top sample is a C
                }
                let pitch = (octave + 1) * 12 + 3 * k as i32;
                out.push((pitch as u8, format!("{dir}/{name}{octave}.mp3")));
            }
        }
        out
    }
}

/// Drum one-shots by General MIDI number, played in turn (round robin).
pub const DRUM_FILES: [(u8, &[&str]); 5] = [
    (36, &["kick", "kick_2", "kick_3"]),
    (38, &["snare", "snare_2", "snare_3"]),
    (42, &["hihat_closed", "hihat_closed_2", "hihat_closed_3"]),
    (46, &["hihat_open"]),
    (49, &["crash"]),
];
pub const SOFT_HAT_FILE: &str = "hihat_closed_soft";
pub const CLICK_FILES: [&str; 2] = ["click", "click_accent"];

/// Longest kept sample tail: held piano notes past this fade out.
const MAX_SECONDS: f32 = 10.0;

/// One decoded sample: interleaved stereo 16-bit at its own sample rate.
pub struct Sample {
    pub rate: u32,
    pub data: Vec<i16>,
    /// Loop region in frames, crossfaded so the seam is seamless.
    pub looped: Option<(usize, usize)>,
}

impl Sample {
    pub fn frames(&self) -> usize {
        self.data.len() / 2
    }

    /// Builds a sample from float channels (1 or 2). Trims the tail once it
    /// stays 60 dB under the peak, and at 10 s at most (50 ms fade), unless
    /// it loops; loops get
    /// the seam crossfaded (equal power, 150 ms).
    pub fn from_channels(channels: &[Vec<f32>], rate: u32, looped: Option<(f32, f32)>) -> Sample {
        let left = &channels[0];
        let right = channels.get(1).unwrap_or(left);
        let n = left.len().min(right.len());
        let mut l = left[..n].to_vec();
        let mut r = right[..n].to_vec();

        let mut loop_frames = None;
        if let Some((from, to)) = looped {
            let start = (from * rate as f32).round() as usize;
            let end = ((to * rate as f32).round() as usize).min(n);
            let fade = ((0.15 * rate as f32).round() as usize).min(start);
            for ch in [&mut l, &mut r] {
                for i in 0..fade {
                    let w = i as f32 / fade as f32 * std::f32::consts::FRAC_PI_2;
                    let tail = end - fade + i;
                    ch[tail] = ch[tail] * w.cos() + ch[start - fade + i] * w.sin();
                }
            }
            l.truncate(end);
            r.truncate(end);
            loop_frames = Some((start, end));
        } else {
            let peak = l.iter().chain(&r).fold(0f32, |m, v| m.max(v.abs()));
            let floor = peak * 10f32.powf(-60.0 / 20.0);
            let last = (0..n)
                .rev()
                .find(|&i| l[i].abs() > floor || r[i].abs() > floor)
                .unwrap_or(0);
            let fade = (0.05 * rate as f32) as usize;
            let keep = (last + fade)
                .min(n)
                .min((MAX_SECONDS * rate as f32) as usize);
            l.truncate(keep);
            r.truncate(keep);
            let fade_from = keep.saturating_sub(fade);
            for i in fade_from..keep {
                let g = (keep - i) as f32 / fade.max(1) as f32;
                l[i] *= g;
                r[i] *= g;
            }
        }

        let mut data = Vec::with_capacity(l.len() * 2);
        for i in 0..l.len() {
            data.push((l[i].clamp(-1.0, 1.0) * 32767.0) as i16);
            data.push((r[i].clamp(-1.0, 1.0) * 32767.0) as i16);
        }
        Sample {
            rate,
            data,
            looped: loop_frames,
        }
    }

    /// Stereo frame at a fractional position (linear interpolation).
    #[inline]
    pub fn frame(&self, pos: f64) -> (f32, f32) {
        let i = pos as usize;
        let frac = (pos - i as f64) as f32;
        let n = self.frames();
        if i + 1 >= n {
            if i < n {
                return (
                    self.data[2 * i] as f32 / 32768.0,
                    self.data[2 * i + 1] as f32 / 32768.0,
                );
            }
            return (0.0, 0.0);
        }
        let a = 2 * i;
        let l = self.data[a] as f32 + (self.data[a + 2] as f32 - self.data[a] as f32) * frac;
        let r =
            self.data[a + 1] as f32 + (self.data[a + 3] as f32 - self.data[a + 1] as f32) * frac;
        (l / 32768.0, r / 32768.0)
    }
}

/// Every sample the engine can play. Cheap to clone (samples are shared),
/// so a loader can add files and hand the engine a new bank.
#[derive(Default, Clone)]
pub struct SampleBank {
    pub pitched: BTreeMap<Instrument, BTreeMap<u8, Arc<Sample>>>,
    pub drums: BTreeMap<u8, Vec<Arc<Sample>>>,
    pub soft_hat: Option<Arc<Sample>>,
    pub click: Option<Arc<Sample>>,
    pub click_accent: Option<Arc<Sample>>,
}

impl SampleBank {
    /// Nearest decoded sample to [pitch] for [instrument].
    pub fn nearest(&self, instrument: Instrument, pitch: u8) -> Option<(u8, &Sample)> {
        self.pitched
            .get(&instrument)?
            .iter()
            .min_by_key(|(p, _)| (**p as i32 - pitch as i32).abs())
            .map(|(p, s)| (*p, s.as_ref()))
    }

    /// Bytes of decoded audio held.
    pub fn bytes(&self) -> usize {
        let all = self
            .pitched
            .values()
            .flat_map(|m| m.values())
            .chain(self.drums.values().flatten())
            .chain(self.soft_hat.iter())
            .chain(self.click.iter())
            .chain(self.click_accent.iter());
        all.map(|s| s.data.len() * 2).sum()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn instrument_files_match_the_bundled_names() {
        let piano = Instrument::Piano.files();
        assert_eq!(piano.len(), 29);
        assert_eq!(piano[0], (24, "assets/piano/C1.mp3".into()));
        assert_eq!(
            piano.last().unwrap(),
            &(108, "assets/piano/C8.mp3".to_string())
        );
        assert_eq!(Instrument::Bass.files().len(), 13);
    }

    #[test]
    fn loop_seam_has_no_jump() {
        // A sine whose loop points fall at different phases: the crossfade
        // must make the wrap from loop end to loop start continuous.
        let rate = 8000;
        let sine: Vec<f32> = (0..rate * 3)
            .map(|i| (i as f32 * 0.0731).sin() * 0.5)
            .collect();
        let s = Sample::from_channels(&[sine.clone(), sine], rate, Some((0.5, 2.9)));
        let (from, to) = s.looped.unwrap();
        let before = s.frame((to - 1) as f64).0;
        let after = s.frame(from as f64).0;
        assert!((before - after).abs() < 0.05, "{before} -> {after}");
    }

    #[test]
    fn quiet_tail_is_trimmed() {
        let rate = 1000;
        let mut ch = vec![0.5f32; 500];
        ch.extend(vec![0.0f32; 5000]);
        let s = Sample::from_channels(&[ch.clone(), ch], rate, None);
        assert!(s.frames() < 600);
    }
}
