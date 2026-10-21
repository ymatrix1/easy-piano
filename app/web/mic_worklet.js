// Mic capture for Easy Piano (docs/specs/input.md). Batches the 128-frame
// render quanta into 512-frame chunks and posts them with the context frame
// of their first sample, so the main thread can time onsets exactly.
class MicCapture extends AudioWorkletProcessor {
  constructor() {
    super();
    this.buf = new Float32Array(512);
    this.fill = 0;
    this.startFrame = 0;
  }

  process(inputs) {
    const ch = inputs[0] && inputs[0][0];
    if (!ch) return true;
    if (this.fill === 0) this.startFrame = currentFrame;
    this.buf.set(ch, this.fill);
    this.fill += ch.length;
    if (this.fill >= this.buf.length) {
      this.port.postMessage({ frame: this.startFrame, samples: this.buf });
      this.buf = new Float32Array(512);
      this.fill = 0;
    }
    return true;
  }
}

registerProcessor('mic-capture', MicCapture);
