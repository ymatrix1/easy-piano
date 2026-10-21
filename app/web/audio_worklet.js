// The Easy Piano audio engine (D30 stage 3) on the web: the Rust crate in
// audio/ compiled to wasm (audio/web, built to audio_engine.wasm by
// tools/build_audio_wasm.py) renders every frame here, on the audio thread.
// piano_synth_web.dart only sends events and decoded PCM through the port;
// times are seconds from "now" on this engine's clock (rule 7).
//
// Messages (arrays, first item is the op):
//   ['sample', kind, key, rate, [Float32Array...]]  then ['commit']
//   ['note', inst, part, pitch, startSec, durSec, vel]
//   ['drum', gm, startSec, vel]   ['click', startSec, accent]
//   ['on', pitch, vel]   ['off', pitch]   ['level', part, level]   ['stop']
//   ['ping', id]  answered with {pong: id} once everything before it ran
// The worklet posts {ready: true} once the module runs.
class PianoEngine extends AudioWorkletProcessor {
  constructor(options) {
    super();
    this.ep = null;
    this.pending = [];
    this.port.onmessage = (e) => (this.ep ? this.run(e.data) : this.pending.push(e.data));
    WebAssembly.instantiate(options.processorOptions.wasm, {}).then((r) => {
      const ep = r.instance.exports;
      ep.ep_init(sampleRate);
      this.ep = ep;
      for (const m of this.pending) this.run(m);
      this.pending = [];
      this.port.postMessage({ ready: true });
    });
  }

  run(m) {
    const ep = this.ep;
    switch (m[0]) {
      case 'sample': {
        const [, kind, key, rate, chans] = m;
        const frames = chans[0].length;
        const at = ep.ep_input(frames * chans.length) / 4;
        const heap = new Float32Array(ep.memory.buffer);
        chans.forEach((c, i) => heap.set(c, at + i * frames));
        ep.ep_add_sample(kind, key, chans.length, frames, rate);
        break;
      }
      case 'commit': ep.ep_commit(); break;
      case 'note': ep.ep_note(m[1], m[2], m[3], m[4], m[5], m[6]); break;
      case 'drum': ep.ep_drum(m[1], m[2], m[3]); break;
      case 'click': ep.ep_click(m[1], m[2] ? 1 : 0); break;
      case 'on': ep.ep_note_on(m[1], m[2]); break;
      case 'off': ep.ep_note_off(m[1]); break;
      case 'level': ep.ep_set_part_level(m[1], m[2]); break;
      case 'stop': ep.ep_stop_all(); break;
      case 'ping': this.port.postMessage({ pong: m[1] }); break;
    }
  }

  process(_inputs, outputs) {
    const out = outputs[0];
    if (!this.ep || !out || out.length < 2) return true;
    const f = new Float32Array(this.ep.memory.buffer, this.ep.ep_render(), 256);
    const l = out[0], r = out[1];
    for (let i = 0; i < 128; i++) {
      l[i] = f[2 * i];
      r[i] = f[2 * i + 1];
    }
    return true;
  }
}

registerProcessor('piano-engine', PianoEngine);

// Measurement tap (?mixprobe only): after a 'probe' message, posts the
// context time of the first quantum whose input is audible.
class LevelTap extends AudioWorkletProcessor {
  constructor() {
    super();
    this.armed = false;
    this.port.onmessage = () => (this.armed = true);
  }

  process(inputs) {
    const ch = inputs[0] && inputs[0][0];
    if (this.armed && ch) {
      for (let i = 0; i < ch.length; i++) {
        if (ch[i] > 1e-4 || ch[i] < -1e-4) {
          this.armed = false;
          this.port.postMessage({ loudAt: currentTime + i / sampleRate });
          break;
        }
      }
    }
    return true;
  }
}

registerProcessor('level-tap', LevelTap);
