// Mic note model worker (docs/specs/input.md). Receives raw mic chunks, runs
// resample -> log-band front-end -> PianoNet (onnxruntime-web, wasm) -> decoder
// and posts note-ons. Module worker so onnxruntime-web's ES build loads.
//
// main -> worker: {type:'init', sampleRate, params?}, {type:'chunk', samples: Float32Array},
//                 {type:'expected', pitches: number[]}
// worker -> main: {type:'ready'}, {type:'error', message}, {type:'slow'},
//                 {type:'notes', notes:[{pitch, time, detectedAt}]} (seconds from the first sample),
//                 {type:'stats', meanMs, maxMs, frames}
import { Decoder, FRONT_CTX, Frontend, LOOKAHEAD, NBANDS, NKEYS, Resampler } from './mic_model_core.js';

const MODEL_BASE = './models/piano_net'; // .onnx + .json (state dims)
const ORT_DIR = new URL('./vendor/ort/', import.meta.url).href;
const MAX_BACKLOG_FRAMES = 40; // ~0.64 s behind real time: tell the main thread to fall back

let ort;
let session;
let resampler;
let frontend;
let decoder;
let ctx; // last FRONT_CTX frames, newest last
let states;
let stateDims; // from piano_net.json: dims of each state input
let step = 0;
let backlog = 0;
let chain = Promise.resolve();
let statSum = 0;
let statMax = 0;
let statN = 0;
let statAt = 0;

async function init(msg) {
  ort = await import(`${ORT_DIR}ort.wasm.min.mjs`);
  ort.env.wasm.wasmPaths = ORT_DIR;
  ort.env.wasm.numThreads = 1; // threaded wasm buys little for a model this small
  const base = new URL(msg.modelBase ?? MODEL_BASE, import.meta.url).href;
  session = await ort.InferenceSession.create(`${base}.onnx`, { executionProviders: ['wasm'], graphOptimizationLevel: 'all' });
  stateDims = (await (await fetch(`${base}.json`)).json()).states;
  resampler = new Resampler(msg.sampleRate);
  frontend = new Frontend();
  decoder = new Decoder(msg.params);
  ctx = Array.from({ length: FRONT_CTX }, () => new Float32Array(NBANDS));
  states = null;
  step = 0;
  // Warm the graph once so the first real frame isn't slow.
  await runFrame(true);
  step = 0;
  states = null;
  postMessage({ type: 'ready' });
}

function zeroStates() {
  return stateDims.map((dims) => new ort.Tensor('float32', new Float32Array(dims.reduce((a, b) => a * b, 1)), dims));
}

async function runFrame(dry) {
  if (!states) states = zeroStates();
  const flat = new Float32Array(FRONT_CTX * NBANDS);
  ctx.forEach((f, i) => flat.set(f, i * NBANDS));
  const feeds = { ctx: new ort.Tensor('float32', flat, [1, FRONT_CTX, NBANDS]) };
  states.forEach((t, i) => (feeds[`state${i}`] = t));
  const out = await session.run(feeds);
  states = stateDims.map((_, i) => out[`new_state${i}`]);
  return out;
}

async function onFrame(feat) {
  ctx.shift();
  ctx.push(feat);
  const t0 = performance.now();
  const out = await runFrame(false);
  const g = step - LOOKAHEAD; // model frame this step produced
  step++;
  if (g < 0) {
    states = null; // warm-up frames are silence, not state (tests/test_model.py)
    return [];
  }
  const notes = decoder.push(g, out.onset.data, out.frame.data);
  const ms = performance.now() - t0;
  statSum += ms;
  statMax = Math.max(statMax, ms);
  statN++;
  return notes;
}

async function process(samples) {
  const frames = frontend.push(resampler.push(samples));
  const notes = [];
  for (const f of frames) {
    notes.push(...(await onFrame(f)));
    backlog--;
  }
  if (notes.length) postMessage({ type: 'notes', notes });
  const now = performance.now();
  if (now - statAt > 5000 && statN) {
    postMessage({ type: 'stats', meanMs: statSum / statN, maxMs: statMax, frames: statN });
    statSum = statMax = statN = 0;
    statAt = now;
  }
}

self.onmessage = (e) => {
  const m = e.data;
  if (m.type === 'init') {
    init(m).catch((err) => postMessage({ type: 'error', message: String(err && err.message ? err.message : err) }));
  } else if (m.type === 'chunk' && session) {
    backlog += Math.ceil(m.samples.length / (m.sampleRate ?? 48000) * 62.5);
    if (backlog > MAX_BACKLOG_FRAMES) {
      postMessage({ type: 'slow' });
      backlog = 0;
    }
    chain = chain.then(() => process(m.samples)).catch((err) => postMessage({ type: 'error', message: String(err) }));
  } else if (m.type === 'expected' && decoder) {
    decoder.expected = new Set(m.pitches);
  }
};
