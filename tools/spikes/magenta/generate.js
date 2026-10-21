// Feasibility spike: rule-limited melodies from Magenta.js MusicRNN checkpoints.
//
//   node generate.js [--level e1|e3] [--n 20] [--reject 200] [--temp 1.0] [--seed 1]
//                    [--only basic_rnn,melody_rnn]
//
// Two modes per checkpoint:
//   masked   - our own copy of MusicRNN.sampleRnn (Apache-2.0, magenta-js) that sets
//              disallowed event logits to -Infinity before sampling, so every tune
//              obeys the rules by construction.
//   reject   - plain sampling from the model, rules checked afterwards; reports the
//              acceptance rate.
// Writes the top 5 songs per checkpoint (our content JSON), summary-<level>-<checkpoint>.json
// and index.json (for viewer.html) to out/.
require('./stub-tone');
const fs = require('fs');
const path = require('path');
const tf = require('@tensorflow/tfjs');
const mm = require('@magenta/music/node/music_rnn');
const pkg = require('@magenta/music/package.json');

const BASE = 'https://storage.googleapis.com/magentadata/js/checkpoints/music_rnn/';

// Level rule sets. Durations and rests in 16th steps (4 per quarter, 4/4).
const LEVELS = {
  e1: {
    label: 'Essentials I: C4-G4, eighth/quarter/half, max leap 5th, end on C4',
    pitches: [60, 62, 64, 65, 67], // C position, white keys
    durations: [2, 4, 8],
    rests: [], // no rests
    maxLeap: 7,
    chords: ['C', 'F', 'G', 'C', 'C', 'F', 'G', 'C'],
    bpm: 80,
  },
  e3: {
    label: 'Treble C4-C5 with F#4/Bb4, eighth/quarter/dotted quarter/half, quarter/half rests, max leap 6th, end on C',
    pitches: [60, 62, 64, 65, 66, 67, 69, 70, 71, 72],
    durations: [2, 4, 6, 8],
    rests: [4, 8],
    maxLeap: 9,
    chords: ['C', 'Am', 'Dm', 'G', 'C', 'F', 'G7', 'C'],
    bpm: 90,
  },
};
const LEVEL_ID = (() => {
  const i = process.argv.indexOf('--level');
  return i > 0 ? process.argv[i + 1] : 'e1';
})();
if (!LEVELS[LEVEL_ID]) throw new Error(`unknown level ${LEVEL_ID}`);
const RULES = { ...LEVELS[LEVEL_ID], bars: 8, stepsPerBar: 16, final: 60 };
const CHECKPOINTS = [{ id: 'basic_rnn' }, { id: 'melody_rnn' }, { id: 'chord_pitches_improv', chords: RULES.chords }];
const TOTAL = RULES.bars * RULES.stepsPerBar;
const FINAL_ONSET = TOTAL - 8; // last note: half note C on beats 3-4 of bar 8
const NAMES = ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'G#', 'A', 'Bb', 'B'];
const noteName = (p) => `${NAMES[p % 12]}${Math.floor(p / 12) - 1}`;
const DUR_TOKEN = { 2: '8', 4: '4', 6: '4.', 8: '2' };

const args = Object.fromEntries(
  process.argv.slice(2).reduce((a, v, i, all) => (v.startsWith('--') ? [...a, [v.slice(2), all[i + 1]]] : a), []),
);
const N = Number(args.n ?? 20);
const NREJECT = Number(args.reject ?? 200);
const TEMP = Number(args.temp ?? 1.0);
const SEED0 = Number(args.seed ?? 1);

// mulberry32: small seeded PRNG so runs are reproducible.
function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Event index layout of Magenta's MelodyConverter: 0 = hold, 1 = note off, 2.. = pitch.
const HOLD = 0;
const OFF = 1;

// Boundaries a note must not cross: every barline, plus the forced final onset.
function nextBoundary(t) {
  const bar = (Math.floor(t / RULES.stepsPerBar) + 1) * RULES.stepsPerBar;
  return t < FINAL_ONSET && bar > FINAL_ONSET ? FINAL_ONSET : bar;
}

// Allowed events at step t given the current note or rest (onset step, pitch or null)
// and the last sounded pitch.
function allowed(t, cur, lastPitch, minPitch, depth) {
  const ok = new Uint8Array(depth);
  const len = t - cur.onset;
  if (t > FINAL_ONSET) {
    ok[HOLD] = 1;
    return ok;
  }
  const lens = cur.pitch === null ? RULES.rests : RULES.durations;
  const b = nextBoundary(cur.onset + 1);
  if (lens.some((d) => d >= len + 1 && cur.onset + d <= b)) ok[HOLD] = 1;
  if (lens.includes(len)) {
    const pitches = t === FINAL_ONSET ? [RULES.final] : RULES.pitches;
    // From bar 7 on, stay within a leap of the final C so the forced ending is reachable.
    const nearEnd = t >= TOTAL - 2 * RULES.stepsPerBar;
    for (const p of pitches) {
      if (Math.abs(p - lastPitch) > RULES.maxLeap) continue;
      if (nearEnd && Math.abs(p - RULES.final) > RULES.maxLeap) continue;
      ok[p - minPitch + 2] = 1;
    }
    // A rest may start after a note, never two rests in a row, and it must fit before the boundary.
    const rb = nextBoundary(t);
    if (cur.pitch !== null && t !== FINAL_ONSET && RULES.rests.some((d) => t + d <= rb)) ok[OFF] = 1;
  }
  return ok;
}

function sampleIndex(logits, mask, temp, rand) {
  let max = -Infinity;
  for (let i = 0; i < logits.length; i++) if ((!mask || mask[i]) && logits[i] > max) max = logits[i];
  const w = new Float64Array(logits.length);
  let sum = 0;
  for (let i = 0; i < logits.length; i++) {
    if (mask && !mask[i]) continue;
    w[i] = Math.exp((logits[i] - max) / temp);
    sum += w[i];
  }
  let r = rand() * sum;
  for (let i = 0; i < w.length; i++) {
    r -= w[i];
    if (r <= 0 && w[i] > 0) return i;
  }
  return w.findLastIndex((x) => x > 0);
}

// Adapted from MusicRNN.sampleRnn in magenta-js (Apache-2.0): same LSTM step, but
// the sampling happens on the CPU so we can mask logits. Primer: one step, C4 onset.
function generate(model, chords, { masked, temp, seed }) {
  const minPitch = model.dataConverter.minPitch;
  const depth = model.lstmFcW.shape[1];
  const rand = rng(seed);
  const events = [RULES.pitches[0] - minPitch + 2];
  const chordSteps = model.chordEncoder ? tf.split(model.chordEncoder.encodeProgression(chords, TOTAL), TOTAL) : null;
  let c = model.biasShapes.map((s) => tf.zeros([1, s / 4]));
  let h = model.biasShapes.map((s) => tf.zeros([1, s / 4]));
  let cur = { onset: 0, pitch: RULES.pitches[0] };
  let lastPitch = cur.pitch;
  for (let t = 1; t < TOTAL; t++) {
    const prev = tf.oneHot(tf.tensor1d([events[t - 1]], 'int32'), depth).toFloat();
    const input = chordSteps ? tf.concat([chordSteps[t], prev], 1) : prev;
    const next = tf.tidy(() => tf.multiRNNCell(model.lstmCells, input, c, h));
    c.forEach((x) => x.dispose());
    h.forEach((x) => x.dispose());
    [c, h] = next;
    const logits = tf.tidy(() => h[h.length - 1].matMul(model.lstmFcW).add(model.lstmFcB).as1D().dataSync());
    prev.dispose();
    if (input !== prev) input.dispose();
    const mask = masked ? allowed(t, cur, lastPitch, minPitch, depth) : null;
    const ev = sampleIndex(logits, mask, temp, rand);
    events.push(ev);
    if (ev >= 2) {
      cur = { onset: t, pitch: ev - 2 + minPitch };
      lastPitch = cur.pitch;
    } else if (ev === OFF && cur.pitch !== null) cur = { onset: t, pitch: null };
  }
  c.forEach((x) => x.dispose());
  h.forEach((x) => x.dispose());
  if (chordSteps) chordSteps.forEach((x) => x.dispose());
  return { events, minPitch };
}

// Events -> notes ({pitch|null for rest, start, dur} in steps).
function toNotes({ events, minPitch }) {
  const notes = [];
  for (let t = 0; t < events.length; t++) {
    const e = events[t];
    if (e === HOLD && notes.length) notes[notes.length - 1].dur++;
    else if (e === OFF || (e === HOLD && !notes.length)) {
      const last = notes[notes.length - 1];
      if (last && last.pitch === null) last.dur++;
      else notes.push({ pitch: null, start: t, dur: 1 });
    } else notes.push({ pitch: e - 2 + minPitch, start: t, dur: 1 });
  }
  return notes;
}

// Post-hoc rule check; returns the list of broken rules (empty = accepted).
function violations(notes) {
  const v = new Set();
  let prev = null;
  for (const n of notes) {
    if (n.pitch === null) {
      if (!RULES.rests.includes(n.dur)) v.add('rest');
    } else {
      if (!RULES.pitches.includes(n.pitch)) v.add('pitch');
      if (!RULES.durations.includes(n.dur)) v.add('duration');
      if (prev !== null && Math.abs(n.pitch - prev) > RULES.maxLeap) v.add('leap');
      prev = n.pitch;
    }
    if (Math.floor(n.start / 16) !== Math.floor((n.start + n.dur - 1) / 16)) v.add('barline');
  }
  if (notes[notes.length - 1].pitch !== RULES.final) v.add('ending');
  return [...v];
}

function score(all) {
  const notes = all.filter((n) => n.pitch !== null);
  const ints = notes.slice(1).map((n, i) => Math.abs(n.pitch - notes[i].pitch));
  const stepwise = ints.filter((d) => d <= 2).length / ints.length;
  const repeatedNote = ints.filter((d) => d === 0).length / ints.length;
  const inBar = (b) => all.filter((n) => Math.floor(n.start / 16) === b);
  const barSig = (b) => inBar(b).map((n) => `${n.pitch}:${n.start % 16}:${n.dur}`).join(' ');
  const rhythmSig = (b) => inBar(b).map((n) => `${n.start % 16}:${n.dur}`).join(' ');
  // Phrase repetition: bars 1-2 come back (exactly, or as rhythm) in bars 5-6.
  let repetition = 0;
  for (const [a, b] of [[0, 4], [1, 5]]) repetition += barSig(a) === barSig(b) ? 0.5 : rhythmSig(a) === rhythmSig(b) ? 0.25 : 0;
  const pen = notes[notes.length - 2].pitch;
  const ending = [62, 64, 71].includes(pen) ? 1 : pen === 67 ? 0.6 : 0.3;
  const eighths = notes.filter((n) => n.dur === 2).length / notes.length;
  // Variety: distinct pitches (out of 5 wanted) and span (a fifth or more wanted), so loops on one note lose.
  const distinct = new Set(notes.map((n) => n.pitch)).size;
  const span = Math.max(...notes.map((n) => n.pitch)) - Math.min(...notes.map((n) => n.pitch));
  const variety = 0.5 * Math.min(1, distinct / 5) + 0.5 * Math.min(1, span / 7);
  // Rest cap: up to 15 % of the tune may be silent; beyond that, a steep penalty.
  const restShare = all.filter((n) => n.pitch === null).reduce((s, n) => s + n.dur, 0) / TOTAL;
  let total =
    0.35 * stepwise + 0.2 * repetition + 0.15 * ending + 0.1 * (1 - Math.max(0, eighths - 0.3)) + 0.2 * variety -
    0.2 * Math.max(0, repeatedNote - 0.3) - 2 * Math.max(0, restShare - 0.15);
  // Hard floor: fewer than 4 distinct pitches or a span under a fourth is a loop, not a tune.
  if (distinct < 4 || span < 5) total = 0;
  return {
    total: +total.toFixed(3), stepwise: +stepwise.toFixed(2), repetition, ending, eighths: +eighths.toFixed(2),
    repeatedNote: +repeatedNote.toFixed(2), distinct, span, restShare: +restShare.toFixed(2),
  };
}

// Five-finger positions, tried in order; a bar takes the first one that covers all its notes.
const POSITIONS = [
  { name: 'C', keys: [60, 62, 64, 65, 67] },
  { name: 'G', keys: [67, 69, 71, 72, 74] },
  { name: 'F', keys: [65, 67, 69, 70, 72] },
  { name: 'D', keys: [62, 64, 66, 67, 69] },
];
function fingerBar(pitches) {
  const pos = POSITIONS.find((p) => pitches.every((x) => p.keys.includes(x)));
  if (pos) return (x) => pos.keys.indexOf(x) + 1;
  // No five-finger position fits: spread the bar's span over fingers 1-5.
  const lo = Math.min(...pitches);
  const hi = Math.max(...pitches);
  return (x) => (hi === lo ? 1 : 1 + Math.round(((x - lo) / (hi - lo)) * 4));
}

function toSong(notes, meta) {
  const bars = [];
  for (let b = 0; b < RULES.bars; b++) {
    const inBar = notes.filter((n) => Math.floor(n.start / 16) === b);
    const finger = fingerBar(inBar.filter((n) => n.pitch !== null).map((n) => n.pitch));
    bars.push({
      RH: inBar
        .map((n) => (n.pitch === null ? `r:${DUR_TOKEN[n.dur]}` : `${noteName(n.pitch)}:${DUR_TOKEN[n.dur]}@${finger(n.pitch)}`))
        .join(' '),
    });
  }
  const id = `gen-magenta-${LEVEL_ID}-${meta.checkpoint.replace(/_/g, '-')}-${meta.seed}`;
  return {
    id,
    title: `Generated tune ${LEVEL_ID} ${meta.checkpoint} #${meta.seed}`,
    composer: 'Generated (Magenta.js MusicRNN)',
    arranger: 'Easy Piano contributors',
    source: 'generated',
    source_url: null,
    license: 'CC0-1.0',
    composition_license: 'CC0-1.0',
    bpm: RULES.bpm,
    time: '4/4',
    key: 'C',
    generator: {
      method: 'magenta-musicrnn-masked-sampling',
      tool: '@magenta/music',
      tool_version: pkg.version,
      checkpoint: BASE + meta.checkpoint,
      seed: meta.seed,
      temperature: meta.temp,
      chords: meta.chords ?? null,
      level: LEVEL_ID,
      rules: RULES.label,
      score: meta.score,
    },
    bars,
    critical: [[0, RULES.bars]],
  };
}

async function main() {
  await tf.setBackend('cpu');
  const outDir = path.join(__dirname, 'out');
  fs.mkdirSync(outDir, { recursive: true });
  const summary = { level: LEVEL_ID, rules: RULES.label, tool_version: pkg.version, tfjs: tf.version.tfjs, backend: tf.getBackend(), node: process.version, temp: TEMP, n: N, reject_n: NREJECT, checkpoints: [] };
  for (const ck of CHECKPOINTS) {
    if (args.only && !args.only.split(',').includes(ck.id)) continue;
    let t0 = Date.now();
    let model;
    for (let attempt = 1; ; attempt++) {
      try {
        model = new mm.MusicRNN(BASE + ck.id);
        await model.initialize();
        break;
      } catch (e) {
        if (attempt >= 3) throw e; // checkpoint fetch from GCS sometimes aborts
      }
    }
    const loadMs = Date.now() - t0;

    t0 = Date.now();
    const masked = [];
    for (let i = 0; i < N; i++) {
      const seed = SEED0 + i;
      const notes = toNotes(generate(model, ck.chords, { masked: true, temp: TEMP, seed }));
      const bad = violations(notes);
      if (bad.length) throw new Error(`masked tune broke rules: ${bad} (${ck.id} seed ${seed})`);
      masked.push({ seed, notes, score: score(notes) });
    }
    const maskedMs = (Date.now() - t0) / N;

    t0 = Date.now();
    const why = {};
    let accepted = 0;
    for (let i = 0; i < NREJECT; i++) {
      const bad = violations(toNotes(generate(model, ck.chords, { masked: false, temp: TEMP, seed: 100000 + SEED0 + i })));
      if (!bad.length) accepted++;
      for (const b of bad) why[b] = (why[b] ?? 0) + 1;
    }
    const rejectMs = NREJECT ? (Date.now() - t0) / NREJECT : 0;

    masked.sort((a, b) => b.score.total - a.score.total);
    for (const m of masked.slice(0, 5)) {
      const song = toSong(m.notes, { checkpoint: ck.id, seed: m.seed, temp: TEMP, chords: ck.chords, score: m.score });
      fs.writeFileSync(path.join(outDir, `${song.id}.json`), JSON.stringify(song, null, 2) + '\n');
    }
    const meanScore = masked.reduce((s, m) => s + m.score.total, 0) / N;
    const row = {
      checkpoint: ck.id,
      chords: ck.chords ?? null,
      load_ms: loadMs,
      masked_ms_per_tune: Math.round(maskedMs),
      masked_mean_score: +meanScore.toFixed(3),
      masked_best: masked.slice(0, 5).map((m) => ({ seed: m.seed, ...m.score })),
      reject_ms_per_tune: Math.round(rejectMs),
      reject_accepted: accepted,
      reject_n: NREJECT,
      reject_violations: why,
    };
    summary.checkpoints.push(row);
    fs.writeFileSync(path.join(outDir, `summary-${LEVEL_ID}-${ck.id}.json`), JSON.stringify({ ...summary, checkpoints: [row] }, null, 2) + '\n');
    console.log(JSON.stringify(row));
    model.dispose();
  }
  const songs = fs.readdirSync(outDir).filter((f) => f.startsWith('gen-') && f.endsWith('.json')).sort();
  fs.writeFileSync(path.join(outDir, 'index.json'), JSON.stringify(songs, null, 2) + '\n');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
