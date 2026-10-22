// Mic note model, pure parts (docs/specs/input.md): resampler, log-band
// front-end and note decoder. Mirrors tools/mic-model/features.py and
// eval_model.py; tools/mic-model/tests/test_web_parity.py checks the
// front-end numbers against the Python ones. No DOM, no onnxruntime here, so
// it loads in the worker and in Node.

export const SR = 16000;
export const HOP = 256;
export const WIN = 1024;
export const NBANDS = 264;
export const NKEYS = 88;
export const MIDI_LO = 21;
export const LOOKAHEAD = 3;
export const FRONT_CTX = 2 * LOOKAHEAD + 1;
const LOG_GAIN = 4;

// ---- resampler: windowed-sinc, any input rate -> 16 kHz ---------------------
export class Resampler {
  constructor(inRate) {
    this.ratio = inRate / SR; // input samples per output sample
    this.pass = this.ratio > 1 ? 0.45 / this.ratio : 0.45; // cutoff, cycles per input sample
    this.half = Math.ceil(8 * Math.max(1, this.ratio));
    this.buf = new Float32Array(0);
    this.base = 0; // absolute input index of buf[0]
    this.next = 0; // next output sample index
  }

  /** Appends input samples, returns the new 16 kHz samples. */
  push(x) {
    const nb = new Float32Array(this.buf.length + x.length);
    nb.set(this.buf);
    nb.set(x, this.buf.length);
    this.buf = nb;
    const out = [];
    const total = this.base + this.buf.length;
    for (;;) {
      const c = this.next * this.ratio;
      const i0 = Math.floor(c) - this.half + 1;
      if (i0 + 2 * this.half > total) break;
      let acc = 0;
      for (let j = 0; j < 2 * this.half; j++) {
        const i = i0 + j;
        const d = i - c;
        const w = 0.5 + 0.5 * Math.cos((Math.PI * d) / (this.half + 1));
        const s = d === 0 ? 1 : Math.sin(2 * Math.PI * this.pass * d) / (2 * Math.PI * this.pass * d);
        const v = i < this.base ? 0 : this.buf[i - this.base];
        acc += v * s * w;
      }
      out.push(acc * 2 * this.pass);
      this.next++;
    }
    const keep = Math.floor(this.next * this.ratio) - this.half;
    if (keep > this.base) {
      this.buf = this.buf.slice(keep - this.base);
      this.base = keep;
    }
    return Float32Array.from(out);
  }
}

// ---- front-end: 16 kHz samples -> log-band frames ---------------------------
const NBINS = WIN / 2 + 1;
const hann = Float64Array.from({ length: WIN }, (_, n) => 0.5 - 0.5 * Math.cos((2 * Math.PI * n) / WIN));
const cosT = Float64Array.from({ length: WIN / 2 }, (_, k) => Math.cos((2 * Math.PI * k) / WIN));
const sinT = Float64Array.from({ length: WIN / 2 }, (_, k) => -Math.sin((2 * Math.PI * k) / WIN));
const rev = (() => {
  const bits = Math.log2(WIN);
  return Uint16Array.from({ length: WIN }, (_, i) => {
    let r = 0;
    for (let b = 0; b < bits; b++) r |= ((i >> b) & 1) << (bits - 1 - b);
    return r;
  });
})();
const bandBin = new Int32Array(NBANDS);
const bandW = new Float64Array(NBANDS);
for (let b = 0; b < NBANDS; b++) {
  const midi = MIDI_LO + (b - 1) / 3;
  const pos = (440 * 2 ** ((midi - 69) / 12)) / (SR / WIN);
  bandBin[b] = Math.floor(pos);
  bandW[b] = pos - Math.floor(pos);
}

function fftMag(re, im, mag) {
  for (let i = 0; i < WIN; i++) {
    const j = rev[i];
    if (j > i) {
      [re[i], re[j]] = [re[j], re[i]];
      [im[i], im[j]] = [im[j], im[i]];
    }
  }
  for (let size = 2; size <= WIN; size <<= 1) {
    const half = size >> 1;
    const step = WIN / size;
    for (let s = 0; s < WIN; s += size) {
      for (let k = 0; k < half; k++) {
        const wr = cosT[k * step];
        const wi = sinT[k * step];
        const a = s + k;
        const b = a + half;
        const tr = re[b] * wr - im[b] * wi;
        const ti = re[b] * wi + im[b] * wr;
        re[b] = re[a] - tr;
        im[b] = im[a] - ti;
        re[a] += tr;
        im[a] += ti;
      }
    }
  }
  for (let i = 0; i < NBINS; i++) mag[i] = Math.hypot(re[i], im[i]);
}

export class Frontend {
  constructor() {
    this.samples = new Float32Array(0);
    this.base = 0; // absolute index of samples[0]
    this.frame = 0; // next frame to produce (centred on sample frame*HOP)
    this.re = new Float64Array(WIN);
    this.im = new Float64Array(WIN);
    this.mag = new Float64Array(NBINS);
  }

  /** Appends 16 kHz samples, returns the completed log-band frames (each Float32Array(264)). */
  push(x) {
    const nb = new Float32Array(this.samples.length + x.length);
    nb.set(this.samples);
    nb.set(x, this.samples.length);
    this.samples = nb;
    const total = this.base + nb.length;
    const out = [];
    while (this.frame * HOP + WIN / 2 <= total) {
      const start = this.frame * HOP - WIN / 2;
      for (let n = 0; n < WIN; n++) {
        const i = start + n;
        this.re[n] = i < 0 ? 0 : this.samples[i - this.base] * hann[n];
        this.im[n] = 0;
      }
      fftMag(this.re, this.im, this.mag);
      const f = new Float32Array(NBANDS);
      for (let b = 0; b < NBANDS; b++) {
        const i = bandBin[b];
        const m = i + 1 < NBINS ? (1 - bandW[b]) * this.mag[i] + bandW[b] * this.mag[i + 1] : 0;
        f[b] = Math.log1p(LOG_GAIN * m);
      }
      out.push(f);
      this.frame++;
    }
    const keep = this.frame * HOP - WIN / 2;
    if (keep > this.base) {
      this.samples = this.samples.slice(keep - this.base);
      this.base = keep;
    }
    return out;
  }
}

// ---- decoder: onset/frame probabilities -> note-ons -------------------------
export const DEFAULT_PARAMS = {
  thrExp: 0.25, // onset prob needed for an expected key
  thrUnexp: 0.9, // ... for any other key
  frameThr: 0.5, // frame prob an unexpected start must sustain
  hold: 3, // frames an unexpected start is held (persistence)
  thrBlind: 0.6, // onset prob when nothing is expected (free play, calibration)
  holdBlind: 3, // persistence frames in that case
  refractory: 6, // frames before a key may retrigger
  guardFrames: 6, // octave ghost guard (only when notes are expected): an unexpected onset an octave below a key that fired this recently, or is expected, is dropped
  calib: 0.006, // seconds added to the frame time to estimate the onset
  frameOff: 0.3, // frame prob under which a sounding key counts as released ...
  offFrames: 3, // ... after this many frames in a row
  maxHold: 0.6, // seconds; a mic can't see a key go up, so keys never stay lit longer (as the DSP detector)
};

export class Decoder {
  constructor(params = {}) {
    this.p = { ...DEFAULT_PARAMS, ...params };
    this.expected = new Set();
    this.armed = new Uint8Array(NKEYS).fill(1);
    this.last = new Int32Array(NKEYS).fill(-999);
    this.pending = []; // {g, k, hold}
    this.prevFrame = null;
    this.active = new Map(); // key -> {g, low} for keys reported on
    this.fired = new Int32Array(NKEYS).fill(-999); // last frame each key's onset crossed its threshold
  }

  /** Feeds the probabilities of model frame g; returns [{pitch, on, time, detectedAt}] (seconds, input timeline). */
  push(g, onset, frame) {
    const p = this.p;
    const out = [];
    const at = (gg) => ((gg + LOOKAHEAD) * HOP + WIN / 2) / SR;
    const emitOn = (k, g0, detectedAt) => {
      const time = (g0 * HOP) / SR + p.calib;
      if (this.active.has(k)) out.push({ pitch: k + MIDI_LO, on: false, time, detectedAt });
      this.active.set(k, { g: g0, low: 0 });
      out.push({ pitch: k + MIDI_LO, on: true, time, detectedAt });
    };
    const blind = this.expected.size === 0;
    for (let k = 0; k < NKEYS; k++) {
      if (onset[k] < 0.5 * p.thrExp) this.armed[k] = 1;
    }
    const fire = [];
    for (let k = 0; k < NKEYS; k++) {
      const thr = this.expected.has(k + MIDI_LO) ? p.thrExp : blind ? p.thrBlind : p.thrUnexp;
      if (this.armed[k] && onset[k] >= thr && g - this.last[k] >= p.refractory) fire.push(k);
    }
    for (const k of fire) this.fired[k] = g; // before judging: a ghost and its real note fire in the same frame
    for (const k of fire) {
      this.armed[k] = 0;
      this.last[k] = g;
      const expected = this.expected.has(k + MIDI_LO);
      if (!blind && !expected && k + 12 < NKEYS && (this.expected.has(k + 12 + MIDI_LO) || g - this.fired[k + 12] <= p.guardFrames)) {
        continue; // ghost: the octave above is sounding
      }
      if (expected) emitOn(k, g, at(g));
      else this.pending.push({ g, k, hold: blind ? p.holdBlind : p.hold });
    }
    const keep = [];
    for (const c of this.pending) {
      if (g - c.g >= c.hold) {
        // Still sounding at the end of the hold (the frame head lags the attack).
        if (Math.min(frame[c.k], this.prevFrame ? this.prevFrame[c.k] : 1) >= p.frameThr) emitOn(c.k, c.g, at(g));
      } else keep.push(c);
    }
    this.pending = keep;
    this.prevFrame = Float32Array.from(frame);
    // Releases: the frame head says the key stopped sounding, or it's been held too long.
    for (const [k, a] of this.active) {
      if (g <= a.g + 1) continue;
      a.low = frame[k] < p.frameOff ? a.low + 1 : 0;
      if (a.low >= p.offFrames || (g - a.g) * HOP / SR > p.maxHold) {
        this.active.delete(k);
        const time = (g * HOP) / SR + p.calib;
        out.push({ pitch: k + MIDI_LO, on: false, time, detectedAt: at(g) });
      }
    }
    return out;
  }
}
