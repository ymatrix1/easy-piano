//! The engine: schedules sample-accurate events and renders stereo frames.
//! It owns the audio clock (frames rendered so far), rule 7.

use crate::bank::{Instrument, Sample, SampleBank};
use crate::dsp::{impulse_response, soft_clip, Compressor, Convolver, LowPass};
use crate::mix::{self, Part};
use std::sync::Arc;

/// What to play. Times are in frames of the engine clock.
#[derive(Clone, Copy, Debug)]
pub enum Sound {
    /// A pitched note held for `dur` frames, then released.
    Note {
        instrument: Instrument,
        part: Part,
        pitch: u8,
        dur: u64,
        velocity: u8,
    },
    /// A drum hit by General MIDI number (36 kick, 38 snare, 42/46 hi-hat,
    /// 49 crash).
    Drum { gm: u8, velocity: u8 },
    /// Metronome click (accent on beat 1).
    Click { accent: bool },
}

#[derive(Clone, Copy, Debug)]
pub struct Event {
    pub at: u64,
    pub sound: Sound,
}

enum Source {
    Pitched(Instrument, u8),
    Drum(u8, usize),
    SoftHat,
    Click(bool),
}

struct Voice {
    source: Source,
    pos: f64,
    step: f64,
    /// Envelope: current gain, target gain, per-frame attack increment.
    gain: f32,
    level: f32,
    attack_step: f32,
    /// Frame at which the release starts, and its per-frame decay factor.
    release_at: u64,
    decay: f32,
    /// None goes straight to the output (clicks), else the part's bus.
    part: Option<Part>,
    tone: Option<LowPass>,
    choke_group: bool,
    done: bool,
}

pub struct Engine {
    rate: f32,
    bank: Arc<SampleBank>,
    now: u64,
    queue: Vec<Event>,
    voices: Vec<Voice>,
    levels: [f32; 8],
    turns: [usize; 128],
    glue: Compressor,
    limiter: Compressor,
    reverb: Convolver,
}

impl Engine {
    pub fn new(rate: u32, bank: Arc<SampleBank>) -> Engine {
        let r = rate as f32;
        let mut levels = [0f32; 8];
        for p in Part::ALL {
            levels[p.index()] = p.level();
        }
        Engine {
            rate: r,
            bank,
            now: 0,
            queue: Vec::new(),
            voices: Vec::new(),
            levels,
            turns: [0; 128],
            glue: Compressor::new(r, mix::GLUE),
            limiter: Compressor::new(r, mix::LIMITER),
            reverb: Convolver::new(&impulse_response(r, mix::REVERB_SECONDS), 128),
        }
    }

    /// Frames rendered so far: the audio clock.
    pub fn now(&self) -> u64 {
        self.now
    }

    pub fn rate(&self) -> u32 {
        self.rate as u32
    }

    /// Scales a part's bus (1 = default mix level, 0 = muted).
    pub fn set_part_level(&mut self, part: Part, level: f32) {
        self.levels[part.index()] = part.level() * level.clamp(0.0, 2.0);
    }

    /// Queues an event; events in the past start at once.
    pub fn schedule(&mut self, event: Event) {
        let pos = self.queue.partition_point(|e| e.at <= event.at);
        self.queue.insert(pos, event);
    }

    /// Releases every voice and drops queued events.
    pub fn stop_all(&mut self) {
        self.queue.clear();
        let now = self.now;
        for v in &mut self.voices {
            v.release_at = v.release_at.min(now);
            v.decay = (-1.0 / (0.03 * self.rate)).exp();
        }
    }

    fn start(&mut self, sound: Sound) {
        match sound {
            Sound::Note {
                instrument,
                part,
                pitch,
                dur,
                velocity,
            } => {
                let Some((sample_pitch, sample)) = self.bank.nearest(instrument, pitch) else {
                    return;
                };
                let (attack, tau) = mix::envelope(instrument);
                let step = 2f64.powf((pitch as f64 - sample_pitch as f64) / 12.0)
                    * sample.rate as f64
                    / self.rate as f64;
                let level = mix::velocity_gain(velocity);
                let attack_frames = attack * self.rate;
                let tone = (instrument == Instrument::Piano)
                    .then(|| LowPass::new(self.rate, mix::piano_cutoff_hz(velocity), 0.5));
                self.voices.push(Voice {
                    source: Source::Pitched(instrument, sample_pitch),
                    pos: 0.0,
                    step,
                    gain: if attack > 0.005 { 0.0 } else { level },
                    level,
                    attack_step: if attack > 0.005 {
                        level / attack_frames
                    } else {
                        0.0
                    },
                    release_at: self.now + dur.max((0.05 * self.rate) as u64),
                    decay: (-1.0 / (tau * self.rate)).exp(),
                    part: Some(part),
                    tone,
                    choke_group: false,
                    done: false,
                });
            }
            Sound::Drum { gm, velocity } => {
                if gm == 42 || gm == 46 {
                    // A closed or new hi-hat chokes the open one, like the pedal.
                    let now = self.now;
                    let choke = (-1.0 / (0.02 * self.rate)).exp();
                    for v in self.voices.iter_mut().filter(|v| v.choke_group) {
                        v.release_at = v.release_at.min(now);
                        v.decay = choke;
                    }
                }
                let source =
                    if gm == 42 && velocity < mix::SOFT_HAT_BELOW && self.bank.soft_hat.is_some() {
                        Source::SoftHat
                    } else {
                        let Some(hits) = self.bank.drums.get(&gm) else {
                            return;
                        };
                        let turn = self.turns[gm as usize];
                        self.turns[gm as usize] += 1;
                        Source::Drum(gm, turn % hits.len())
                    };
                let rate = self.sample_of(&source).map_or(self.rate as u32, |s| s.rate);
                let g = mix::velocity_gain(velocity);
                self.voices.push(Voice {
                    source,
                    pos: 0.0,
                    step: rate as f64 / self.rate as f64,
                    gain: g,
                    level: g,
                    attack_step: 0.0,
                    release_at: u64::MAX,
                    decay: 1.0,
                    part: Some(Part::Drums),
                    tone: None,
                    choke_group: gm == 46,
                    done: false,
                });
            }
            Sound::Click { accent } => {
                let source = Source::Click(accent);
                let Some(rate) = self.sample_of(&source).map(|s| s.rate) else {
                    return;
                };
                self.voices.push(Voice {
                    source,
                    pos: 0.0,
                    step: rate as f64 / self.rate as f64,
                    gain: 1.0,
                    level: 1.0,
                    attack_step: 0.0,
                    release_at: u64::MAX,
                    decay: 1.0,
                    part: None,
                    tone: None,
                    choke_group: false,
                    done: false,
                });
            }
        }
    }

    fn sample_of(&self, source: &Source) -> Option<&Sample> {
        sample_in(&self.bank, source)
    }

    /// Renders interleaved stereo frames into `out` (len = 2 x frames).
    pub fn render(&mut self, out: &mut [f32]) {
        let bank = Arc::clone(&self.bank);
        for frame in out.chunks_exact_mut(2) {
            while self.queue.first().is_some_and(|e| e.at <= self.now) {
                let e = self.queue.remove(0);
                self.start(e.sound);
            }
            let mut bus = [[0f32; 2]; 8];
            let mut direct = [0f32; 2];
            for v in &mut self.voices {
                let Some(sample) = sample_in(&bank, &v.source) else {
                    v.done = true;
                    continue;
                };
                if let Some((from, to)) = sample.looped {
                    if v.pos >= to as f64 {
                        v.pos -= (to - from) as f64;
                    }
                } else if v.pos >= sample.frames() as f64 {
                    v.done = true;
                    continue;
                }
                let (mut l, mut r) = sample.frame(v.pos);
                v.pos += v.step;
                if let Some(t) = &mut v.tone {
                    l = t.process(0, l);
                    r = t.process(1, r);
                }
                if self.now >= v.release_at {
                    v.gain *= v.decay;
                    if v.gain < 1e-4 {
                        v.done = true;
                    }
                } else if v.attack_step > 0.0 && v.gain < v.level {
                    v.gain = (v.gain + v.attack_step).min(v.level);
                }
                let (l, r) = (l * v.gain, r * v.gain);
                match v.part {
                    Some(p) => {
                        bus[p.index()][0] += l;
                        bus[p.index()][1] += r;
                    }
                    None => {
                        direct[0] += l;
                        direct[1] += r;
                    }
                }
            }
            self.voices.retain(|v| !v.done);

            let (mut band, mut live, mut send) = ([0f32; 2], [0f32; 2], [0f32; 2]);
            for p in Part::ALL {
                let g = self.levels[p.index()];
                let (l, r) = (bus[p.index()][0] * g, bus[p.index()][1] * g);
                let target = if p == Part::Live {
                    &mut live
                } else {
                    &mut band
                };
                target[0] += l;
                target[1] += r;
                send[0] += l * p.reverb_send();
                send[1] += r * p.reverb_send();
            }
            let (wl, wr) = self.reverb.process(send[0], send[1]);
            let (gl, gr) = self.glue.process(band[0] + wl, band[1] + wr);
            let (ll, lr) = self.limiter.process(gl, gr);
            frame[0] = soft_clip(ll + live[0] + direct[0]);
            frame[1] = soft_clip(lr + live[1] + direct[1]);
            self.now += 1;
        }
    }
}

fn sample_in<'a>(bank: &'a SampleBank, source: &Source) -> Option<&'a Sample> {
    match source {
        Source::Pitched(i, p) => bank.pitched.get(i)?.get(p),
        Source::Drum(gm, i) => bank.drums.get(gm)?.get(*i),
        Source::SoftHat => bank.soft_hat.as_ref(),
        Source::Click(true) => bank.click_accent.as_ref(),
        Source::Click(false) => bank.click.as_ref(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::bank::Sample;

    /// A one-second sample whose value is its index, so position is visible.
    fn ramp(rate: u32, value: f32) -> Sample {
        let ch = vec![vec![value; rate as usize]; 2];
        Sample::from_channels(&ch, rate, None)
    }

    fn bank() -> Arc<SampleBank> {
        let mut b = SampleBank::default();
        b.drums
            .insert(38, vec![ramp(1000, 0.1), ramp(1000, 0.2), ramp(1000, 0.3)]);
        b.drums.insert(42, vec![ramp(1000, 0.4)]);
        b.drums.insert(46, vec![ramp(1000, 0.5)]);
        b.soft_hat = Some(ramp(1000, 0.05));
        let mut piano = std::collections::BTreeMap::new();
        piano.insert(60, ramp(1000, 0.5));
        b.pitched.insert(Instrument::Piano, piano);
        Arc::new(b)
    }

    fn engine() -> Engine {
        let mut e = Engine::new(1000, bank());
        // Unity mix so values are easy to reason about.
        for p in Part::ALL {
            e.levels[p.index()] = 1.0;
        }
        e
    }

    #[test]
    fn drums_rotate_through_hits() {
        let mut e = engine();
        for i in 0..4 {
            e.schedule(Event {
                at: i * 100,
                sound: Sound::Drum {
                    gm: 38,
                    velocity: 127,
                },
            });
        }
        let mut buf = vec![0f32; 2 * 400];
        e.render(&mut buf);
        let order: Vec<_> = e
            .voices
            .iter()
            .map(|v| match v.source {
                Source::Drum(_, i) => i,
                _ => 99,
            })
            .collect();
        assert_eq!(order, vec![0, 1, 2, 0]);
    }

    #[test]
    fn soft_closed_hats_use_the_light_hit() {
        let mut e = engine();
        e.schedule(Event {
            at: 0,
            sound: Sound::Drum {
                gm: 42,
                velocity: 60,
            },
        });
        e.schedule(Event {
            at: 0,
            sound: Sound::Drum {
                gm: 42,
                velocity: 100,
            },
        });
        e.render(&mut [0f32; 2]);
        assert!(matches!(e.voices[0].source, Source::SoftHat));
        assert!(matches!(e.voices[1].source, Source::Drum(42, 0)));
    }

    #[test]
    fn closed_hat_chokes_open_hat() {
        let mut e = engine();
        e.schedule(Event {
            at: 0,
            sound: Sound::Drum {
                gm: 46,
                velocity: 100,
            },
        });
        e.schedule(Event {
            at: 100,
            sound: Sound::Drum {
                gm: 42,
                velocity: 100,
            },
        });
        e.render(&mut vec![0f32; 2 * 300]);
        assert!(
            e.voices.iter().all(|v| !v.choke_group),
            "open hat should have faded out"
        );
    }

    #[test]
    fn notes_start_on_their_frame_and_release_after_duration() {
        let rate = 44_100;
        let mut b = SampleBank::default();
        let mut piano = std::collections::BTreeMap::new();
        piano.insert(60, ramp(rate, 0.5));
        b.pitched.insert(Instrument::Piano, piano);
        let mut e = Engine::new(rate, Arc::new(b));
        let ms = |t: u64| t * rate as u64 / 1000;
        e.schedule(Event {
            at: ms(50),
            sound: Sound::Note {
                instrument: Instrument::Piano,
                part: Part::Live,
                pitch: 60,
                dur: ms(200),
                velocity: 127,
            },
        });
        let mut buf = vec![0f32; 2 * ms(600) as usize];
        e.render(&mut buf);
        let at = |t: u64| buf[2 * ms(t) as usize].abs();
        assert_eq!(at(49), 0.0);
        assert!(at(60) > 0.1);
        // Released at 250 ms with a 0.12 s time constant: well down by 580 ms.
        assert!(at(580) < at(240) * 0.15, "{} vs {}", at(580), at(240));
    }

    #[test]
    fn muted_part_is_silent() {
        let mut e = engine();
        e.set_part_level(Part::Drums, 0.0);
        e.schedule(Event {
            at: 0,
            sound: Sound::Drum {
                gm: 38,
                velocity: 127,
            },
        });
        let mut buf = vec![0f32; 2 * 300];
        e.render(&mut buf);
        assert!(buf.iter().all(|v| v.abs() < 1e-6));
    }
}
