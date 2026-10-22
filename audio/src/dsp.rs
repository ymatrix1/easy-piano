//! Effects: low-pass, compressor, convolution reverb and soft clipper. They
//! follow the Web Audio nodes the web build used (D22) closely enough that
//! both platforms measure the same (parity test).

use rustfft::{num_complex::Complex32, Fft, FftPlanner};
use std::sync::Arc;

/// RBJ biquad low-pass. `q_db` follows Web Audio, where a low-pass Q is a
/// resonance in dB.
#[derive(Clone, Copy, Default)]
pub struct LowPass {
    b0: f32,
    b1: f32,
    b2: f32,
    a1: f32,
    a2: f32,
    z1: [f32; 2],
    z2: [f32; 2],
}

impl LowPass {
    pub fn new(rate: f32, cutoff: f32, q_db: f32) -> LowPass {
        let q = 10f32.powf(q_db / 20.0);
        let w0 = 2.0 * std::f32::consts::PI * (cutoff / rate).min(0.49);
        let alpha = w0.sin() / (2.0 * q);
        let cos = w0.cos();
        let a0 = 1.0 + alpha;
        LowPass {
            b0: (1.0 - cos) / 2.0 / a0,
            b1: (1.0 - cos) / a0,
            b2: (1.0 - cos) / 2.0 / a0,
            a1: -2.0 * cos / a0,
            a2: (1.0 - alpha) / a0,
            ..Default::default()
        }
    }

    #[inline]
    pub fn process(&mut self, ch: usize, x: f32) -> f32 {
        // Transposed direct form II.
        let y = self.b0 * x + self.z1[ch];
        self.z1[ch] = self.b1 * x - self.a1 * y + self.z2[ch];
        self.z2[ch] = self.b2 * x - self.a2 * y;
        y
    }
}

/// Feed-forward stereo-linked compressor with a soft knee and automatic
/// makeup gain, like Web Audio's DynamicsCompressorNode.
pub struct Compressor {
    threshold: f32,
    knee: f32,
    ratio: f32,
    attack: f32,
    release: f32,
    makeup: f32,
    env_db: f32,
}

impl Compressor {
    pub fn new(
        rate: f32,
        (threshold, knee, ratio, attack, release): (f32, f32, f32, f32, f32),
    ) -> Self {
        let coef = |t: f32| (-1.0 / (t.max(1e-4) * rate)).exp();
        let mut c = Compressor {
            threshold,
            knee,
            ratio,
            attack: coef(attack),
            release: coef(release),
            makeup: 1.0,
            env_db: 0.0,
        };
        // Web Audio raises the output by (1 / gain at 0 dBFS) ^ 0.6.
        let full_range = db_to_gain(c.curve_db(0.0));
        c.makeup = (1.0 / full_range).powf(0.6);
        c
    }

    /// Gain reduction in dB (<= 0) for an input level in dB.
    fn curve_db(&self, x: f32) -> f32 {
        let over = x - self.threshold;
        let slope = 1.0 / self.ratio - 1.0;
        if self.knee > 0.0 && over.abs() <= self.knee / 2.0 {
            slope * (over + self.knee / 2.0).powi(2) / (2.0 * self.knee)
        } else if over > 0.0 {
            slope * over
        } else {
            0.0
        }
    }

    /// Processes one stereo frame.
    #[inline]
    pub fn process(&mut self, l: f32, r: f32) -> (f32, f32) {
        let level = l.abs().max(r.abs());
        let target = self.curve_db(gain_to_db(level));
        let coef = if target < self.env_db {
            self.attack
        } else {
            self.release
        };
        self.env_db = target + (self.env_db - target) * coef;
        let g = db_to_gain(self.env_db) * self.makeup;
        (l * g, r * g)
    }
}

#[inline]
pub fn db_to_gain(db: f32) -> f32 {
    10f32.powf(db / 20.0)
}

#[inline]
pub fn gain_to_db(g: f32) -> f32 {
    20.0 * g.max(1e-9).log10()
}

/// Linear up to 0.7, then a smooth knee that never exceeds 0.98.
#[inline]
pub fn soft_clip(x: f32) -> f32 {
    let a = x.abs();
    let y = if a <= 0.7 {
        a
    } else {
        0.7 + 0.28 * ((a - 0.7) / 0.28).tanh()
    };
    y.copysign(x)
}

/// Stereo decaying noise, darker as it decays (the same recipe as the web
/// build), normalized like a Web Audio ConvolverNode (`normalize = true`).
pub fn impulse_response(rate: f32, seconds: f32) -> [Vec<f32>; 2] {
    let len = (rate * seconds) as usize;
    let mut rng = 11u64;
    let mut next = move || {
        // xorshift64*: deterministic, no dependency.
        rng ^= rng << 13;
        rng ^= rng >> 7;
        rng ^= rng << 17;
        (rng >> 11) as f32 / (1u64 << 53) as f32 * 2.0 - 1.0
    };
    let mut out = [vec![0f32; len], vec![0f32; len]];
    for ch in out.iter_mut() {
        let mut lp = 0f32;
        for (i, s) in ch.iter_mut().enumerate() {
            let t = i as f32 / rate;
            let a = 0.15 + 0.8 * (-t * 3.0).exp();
            lp += a * (next() - lp);
            *s = lp * (-t * 3.8).exp() * if t < 0.01 { t / 0.01 } else { 1.0 };
        }
    }
    // Web Audio normalization: scale = 0.00125 / rms * 44100 / rate.
    let power = out.iter().flatten().map(|v| v * v).sum::<f32>() / (2 * len) as f32;
    let scale = 0.00125 / power.sqrt().max(0.000125) * 44100.0 / rate;
    for ch in out.iter_mut() {
        for s in ch.iter_mut() {
            *s *= scale;
        }
    }
    out
}

/// Uniformly partitioned FFT convolution, one impulse per channel (left in
/// -> left IR, right in -> right IR), as a stereo ConvolverNode does.
pub struct Convolver {
    block: usize,
    fft: Arc<dyn Fft<f32>>,
    ifft: Arc<dyn Fft<f32>>,
    /// Per channel: IR partitions in the frequency domain.
    parts: [Vec<Vec<Complex32>>; 2],
    /// Per channel: past input spectra, newest first (ring).
    history: [Vec<Vec<Complex32>>; 2],
    head: usize,
    input: [Vec<f32>; 2],
    overlap: [Vec<f32>; 2],
    output: [Vec<f32>; 2],
    fill: usize,
}

impl Convolver {
    pub fn new(ir: &[Vec<f32>; 2], block: usize) -> Convolver {
        let mut planner = FftPlanner::<f32>::new();
        let fft = planner.plan_fft_forward(2 * block);
        let ifft = planner.plan_fft_inverse(2 * block);
        let count = ir[0].len().div_ceil(block);
        let mut parts: [Vec<Vec<Complex32>>; 2] = [Vec::new(), Vec::new()];
        for (ch, p) in parts.iter_mut().enumerate() {
            for k in 0..count {
                let mut buf = vec![Complex32::new(0.0, 0.0); 2 * block];
                for (i, c) in buf.iter_mut().take(block).enumerate() {
                    if let Some(&v) = ir[ch].get(k * block + i) {
                        c.re = v;
                    }
                }
                fft.process(&mut buf);
                p.push(buf);
            }
        }
        let zeros = || vec![vec![Complex32::new(0.0, 0.0); 2 * block]; count];
        Convolver {
            block,
            fft,
            ifft,
            parts,
            history: [zeros(), zeros()],
            head: 0,
            input: [vec![0.0; block], vec![0.0; block]],
            overlap: [vec![0.0; block], vec![0.0; block]],
            output: [vec![0.0; block], vec![0.0; block]],
            fill: 0,
        }
    }

    /// One stereo frame in, one out (latency: one block, like the browser's
    /// own partitioned convolver).
    #[inline]
    pub fn process(&mut self, l: f32, r: f32) -> (f32, f32) {
        let out = (self.output[0][self.fill], self.output[1][self.fill]);
        self.input[0][self.fill] = l;
        self.input[1][self.fill] = r;
        self.fill += 1;
        if self.fill == self.block {
            self.fill = 0;
            self.run_block();
        }
        out
    }

    fn run_block(&mut self) {
        let n = self.parts[0].len();
        self.head = (self.head + n - 1) % n;
        for ch in 0..2 {
            let spec = &mut self.history[ch][self.head];
            for (i, c) in spec.iter_mut().enumerate() {
                *c = Complex32::new(
                    if i < self.block {
                        self.input[ch][i]
                    } else {
                        0.0
                    },
                    0.0,
                );
            }
            self.fft.process(spec);
            let mut acc = vec![Complex32::new(0.0, 0.0); 2 * self.block];
            for k in 0..n {
                let x = &self.history[ch][(self.head + k) % n];
                let h = &self.parts[ch][k];
                for i in 0..acc.len() {
                    acc[i] += x[i] * h[i];
                }
            }
            self.ifft.process(&mut acc);
            let norm = 1.0 / (2 * self.block) as f32;
            for i in 0..self.block {
                self.output[ch][i] = acc[i].re * norm + self.overlap[ch][i];
                self.overlap[ch][i] = acc[i + self.block].re * norm;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn convolver_with_unit_impulse_delays_by_one_block() {
        let mut ir = [vec![0f32; 300], vec![0f32; 300]];
        ir[0][0] = 1.0;
        ir[1][0] = 0.5;
        let mut c = Convolver::new(&ir, 128);
        let out: Vec<(f32, f32)> = (0..400)
            .map(|i| {
                c.process(
                    if i == 3 { 1.0 } else { 0.0 },
                    if i == 3 { 1.0 } else { 0.0 },
                )
            })
            .collect();
        assert!((out[128 + 3].0 - 1.0).abs() < 1e-4);
        assert!((out[128 + 3].1 - 0.5).abs() < 1e-4);
        assert!(out
            .iter()
            .enumerate()
            .all(|(i, o)| i == 131 || o.0.abs() < 1e-4));
    }

    #[test]
    fn convolver_tail_crosses_partitions() {
        let mut ir = [vec![0f32; 600], vec![0f32; 600]];
        ir[0][500] = 1.0;
        let mut c = Convolver::new(&ir, 128);
        let out: Vec<f32> = (0..900)
            .map(|i| c.process(if i == 0 { 1.0 } else { 0.0 }, 0.0).0)
            .collect();
        assert!((out[128 + 500] - 1.0).abs() < 1e-4);
    }

    #[test]
    fn compressor_leaves_quiet_signal_alone_but_for_makeup() {
        let mut c = Compressor::new(44100.0, (-20.0, 12.0, 2.5, 0.01, 0.25));
        let mut last = 0.0;
        for _ in 0..4410 {
            last = c.process(0.01, 0.01).0;
        }
        assert!((last / 0.01 - c.makeup).abs() < 1e-3);
        assert!(c.makeup > 1.0);
    }

    #[test]
    fn compressor_reduces_loud_signal() {
        let mut c = Compressor::new(44100.0, (-20.0, 0.0, 4.0, 0.001, 0.1));
        let mut last = 0.0;
        for _ in 0..4410 {
            last = c.process(1.0, 1.0).0;
        }
        // 0 dBFS in, 20 dB over at 4:1 -> 15 dB reduction, then makeup.
        let expected = db_to_gain(-15.0) * c.makeup;
        assert!((last - expected).abs() < 1e-3, "{last} vs {expected}");
    }

    #[test]
    fn soft_clip_is_linear_low_and_bounded() {
        assert_eq!(soft_clip(0.5), 0.5);
        assert_eq!(soft_clip(-0.5), -0.5);
        assert!(soft_clip(5.0) < 0.98 + 1e-6);
        assert!(soft_clip(-5.0) > -0.98 - 1e-6);
    }
}
