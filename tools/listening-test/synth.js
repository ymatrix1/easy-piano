// WebAudio player: FluidR3 piano samples from app/assets/piano (MIT) for RH/LH/ACC,
// oscillator bass and a noise/sine drum kit for BASS/DRUMS.
const SAMPLES = ['C', 'Eb', 'Gb', 'A'];
const LEVEL = { RH: 1.0, LH: 0.8, ACC: 0.45, BASS: 0.35, DRUMS: 0.3 };

export class Synth {
  constructor(baseUrl) {
    this.baseUrl = baseUrl;
    this.buffers = null;
  }

  async init() {
    this.ctx ??= new AudioContext();
    await this.ctx.resume();
    if (this.buffers) return;
    const entries = [];
    for (let oct = 2; oct <= 7; oct++) {
      SAMPLES.forEach((name, i) => {
        const m = 12 * (oct + 1) + i * 3;
        if (m <= 96) entries.push([m, `${name}${oct}.mp3`]);
      });
    }
    this.buffers = new Map(await Promise.all(entries.map(async ([m, f]) => {
      const data = await (await fetch(this.baseUrl + f)).arrayBuffer();
      return [m, await this.ctx.decodeAudioData(data)];
    })));
    this.noise = this.ctx.createBuffer(1, this.ctx.sampleRate, this.ctx.sampleRate);
    const ch = this.noise.getChannelData(0);
    for (let i = 0; i < ch.length; i++) ch[i] = Math.random() * 2 - 1;
  }

  /** Schedules every note on the audio clock; returns { stop, length }. */
  async play({ notes, length }) {
    await this.init();
    const ctx = this.ctx;
    const bus = ctx.createGain();
    bus.gain.value = 0.5;
    bus.connect(ctx.destination);
    const t0 = ctx.currentTime + 0.15;
    for (const n of notes) {
      const at = t0 + n.start;
      if (n.part === 'DRUMS') this.drum(bus, n.midi, at);
      else if (n.part === 'BASS') this.bass(bus, n.midi, at, n.dur);
      else this.piano(bus, n.midi, at, n.dur, LEVEL[n.part]);
    }
    return {
      length,
      stop: () => {
        bus.gain.setTargetAtTime(0, ctx.currentTime, 0.03);
        setTimeout(() => bus.disconnect(), 300);
      },
    };
  }

  piano(out, m, at, dur, level) {
    let best = null;
    for (const k of this.buffers.keys()) if (best === null || Math.abs(k - m) < Math.abs(best - m)) best = k;
    const src = this.ctx.createBufferSource();
    src.buffer = this.buffers.get(best);
    src.playbackRate.value = 2 ** ((m - best) / 12);
    const g = this.ctx.createGain();
    g.gain.setValueAtTime(level, at);
    g.gain.setTargetAtTime(0, at + dur, 0.12);
    src.connect(g).connect(out);
    src.start(at);
    src.stop(at + dur + 1);
  }

  bass(out, m, at, dur) {
    const ctx = this.ctx;
    const osc = ctx.createOscillator();
    osc.type = 'sawtooth';
    osc.frequency.value = 440 * 2 ** ((m - 69) / 12);
    const lp = ctx.createBiquadFilter();
    lp.type = 'lowpass';
    lp.frequency.value = 500;
    const g = ctx.createGain();
    g.gain.setValueAtTime(0, at);
    g.gain.linearRampToValueAtTime(LEVEL.BASS, at + 0.01);
    g.gain.setTargetAtTime(0, at + dur * 0.9, 0.05);
    osc.connect(lp).connect(g).connect(out);
    osc.start(at);
    osc.stop(at + dur + 0.5);
  }

  drum(out, m, at) {
    const ctx = this.ctx;
    const g = ctx.createGain();
    g.connect(out);
    if (m === 36) { // kick: falling sine
      const osc = ctx.createOscillator();
      osc.frequency.setValueAtTime(140, at);
      osc.frequency.exponentialRampToValueAtTime(45, at + 0.12);
      g.gain.setValueAtTime(LEVEL.DRUMS * 2.5, at);
      g.gain.exponentialRampToValueAtTime(0.001, at + 0.25);
      osc.connect(g);
      osc.start(at);
      osc.stop(at + 0.3);
      return;
    }
    // snare 38, hats 42/46, crash 49: filtered noise
    const src = ctx.createBufferSource();
    src.buffer = this.noise;
    const f = ctx.createBiquadFilter();
    const snare = m === 38;
    f.type = snare ? 'bandpass' : 'highpass';
    f.frequency.value = snare ? 1800 : 7000;
    const len = snare ? 0.15 : m === 46 || m === 49 ? 0.4 : 0.05;
    g.gain.setValueAtTime(LEVEL.DRUMS * (snare ? 1.5 : 0.6), at);
    g.gain.exponentialRampToValueAtTime(0.001, at + len);
    src.connect(f).connect(g);
    src.start(at);
    src.stop(at + len + 0.05);
  }
}
