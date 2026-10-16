import {
  BasicPitch,
  addPitchBendsToNoteEvents,
  noteFramesToTime,
  outputToNotesPoly,
} from '@spotify/basic-pitch';
import * as ort from 'onnxruntime-web';
import { DemucsProcessor, CONSTANTS } from 'demucs-web';

const logEl = document.getElementById('log');
const log = (msg) => {
  logEl.textContent += `\n${msg}`;
  console.log(msg);
};
logEl.textContent = `crossOriginIsolated: ${self.crossOriginIsolated}, WebGPU: ${'gpu' in navigator}`;

const truth = await (await fetch('/truth.json')).json();
let basicPitch;

async function decode(url, sampleRate) {
  const bytes = await (await fetch(url)).arrayBuffer();
  const ctx = new AudioContext({ sampleRate });
  const buf = await ctx.decodeAudioData(bytes);
  await ctx.close();
  return buf;
}

/** Mono Float32Array resampled to [rate] Hz. */
async function toMono(buffer, rate) {
  const off = new OfflineAudioContext(1, Math.ceil(buffer.duration * rate), rate);
  const src = off.createBufferSource();
  src.buffer = buffer;
  src.connect(off.destination);
  src.start();
  return (await off.startRendering()).getChannelData(0);
}

async function transcribe(mono22k) {
  basicPitch ??= new BasicPitch('/basic-pitch-model/model.json');
  const frames = [], onsets = [], contours = [];
  const t0 = performance.now();
  await basicPitch.evaluateModel(
    mono22k,
    (f, o, c) => {
      frames.push(...f);
      onsets.push(...o);
      contours.push(...c);
    },
    () => {},
  );
  const notes = noteFramesToTime(
    addPitchBendsToNoteEvents(contours, outputToNotesPoly(frames, onsets, 0.5, 0.3, 5)),
  );
  return { notes, ms: performance.now() - t0 };
}

/** Note-level F1: same pitch and onset within 50 ms (mir_eval convention). */
function score(notes) {
  const used = new Set();
  let hits = 0;
  for (const t of truth) {
    const i = notes.findIndex(
      (n, k) => !used.has(k) && n.pitchMidi === t.pitch && Math.abs(n.startTimeSeconds - t.start) <= 0.05,
    );
    if (i >= 0) {
      used.add(i);
      hits++;
    }
  }
  const p = notes.length ? hits / notes.length : 0;
  const r = hits / truth.length;
  const f1 = p + r ? (2 * p * r) / (p + r) : 0;
  return `notes=${notes.length} truth=${truth.length} P=${p.toFixed(2)} R=${r.toFixed(2)} F1=${f1.toFixed(2)}`;
}

async function runTranscription(label, url) {
  log(`\n[${label}] decoding…`);
  const mono = await toMono(await decode(url, 44100), 22050);
  const { notes, ms } = await transcribe(mono);
  log(`[${label}] Basic Pitch ${ms.toFixed(0)} ms for ${(mono.length / 22050).toFixed(1)} s audio · ${score(notes)}`);
  exportNotes(label, notes);
  return notes;
}

/** Keeps raw transcriptions on window.__notes for use as test fixtures. */
function exportNotes(label, notes) {
  window.__notes ??= {};
  window.__notes[label] = notes.map((n) => ({
    pitch: n.pitchMidi,
    start: +n.startTimeSeconds.toFixed(4),
    dur: +n.durationSeconds.toFixed(4),
    amp: +n.amplitude.toFixed(3),
  }));
}

function stemPlayer(name, stem) {
  const ctx = new AudioContext({ sampleRate: CONSTANTS.SAMPLE_RATE });
  const buf = ctx.createBuffer(2, stem.left.length, CONSTANTS.SAMPLE_RATE);
  buf.copyToChannel(stem.left, 0);
  buf.copyToChannel(stem.right, 1);
  const wrap = document.createElement('div');
  const btn = document.createElement('button');
  btn.textContent = `▶ ${name}`;
  btn.onclick = () => {
    const s = ctx.createBufferSource();
    s.buffer = buf;
    s.connect(ctx.destination);
    s.start();
  };
  wrap.append(btn);
  document.getElementById('stems').append(wrap);
  return buf;
}

async function runSeparation() {
  log('\n[demucs] loading model…');
  ort.env.wasm.numThreads = navigator.hardwareConcurrency || 4;
  let backend = 'wasm';
  if ('gpu' in navigator && (await navigator.gpu.requestAdapter().catch(() => null))) backend = 'webgpu';
  let lastPct = -1;
  const processor = new DemucsProcessor({
    ort,
    onDownloadProgress: (loaded, total) => {
      const pct = Math.floor((100 * loaded) / total / 10) * 10;
      if (pct !== lastPct) log(`[demucs] download ${pct}% of ${(total / 1e6).toFixed(0)} MB`), (lastPct = pct);
    },
    onLog: (phase, msg) => console.log(`[demucs:${phase}] ${msg}`),
  });
  const tLoad = performance.now();
  await processor.loadModel(CONSTANTS.DEFAULT_MODEL_URL);
  log(`[demucs] model ready in ${((performance.now() - tLoad) / 1000).toFixed(1)} s (backend hint: ${backend})`);

  const mix = await decode('/mix.wav', CONSTANTS.SAMPLE_RATE);
  const left = mix.getChannelData(0);
  const right = mix.numberOfChannels > 1 ? mix.getChannelData(1) : left;
  const t0 = performance.now();
  const stems = await processor.separate(left, right);
  const secs = (performance.now() - t0) / 1000;
  log(`[demucs] separated ${mix.duration.toFixed(1)} s audio in ${secs.toFixed(1)} s (${(secs / mix.duration).toFixed(2)}× realtime)`);

  for (const name of ['vocals', 'drums', 'bass', 'other']) stemPlayer(name, stems[name]);
  const otherBuf = stemPlayer('other (re-used)', stems.other);
  const { notes, ms } = await transcribe(await toMono(otherBuf, 22050));
  log(`[other stem] Basic Pitch ${ms.toFixed(0)} ms · ${score(notes)}`);
  exportNotes('other', notes);
}

const guard = (fn) => async () => {
  try {
    await fn();
  } catch (e) {
    log(`ERROR: ${e?.stack ?? e}`);
  }
};
document.getElementById('t-piano').onclick = guard(() => runTranscription('piano', '/piano.wav'));
document.getElementById('t-mix').onclick = guard(() => runTranscription('mix', '/mix.wav'));
document.getElementById('sep').onclick = guard(runSeparation);
