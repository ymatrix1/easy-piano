// Checks for the Magenta spike. Run: node test.js   (needs network for checkpoints)
//
// 1. Equivalence: our re-implemented sampleRnn (generate.js, greedy, unmasked) gives the
//    same per-step probabilities as the library's continueSequenceAndReturnProbabilities.
// 2. Repeat: the same seed gives the same tune twice.
// 3. Mask property: 5000 tunes per level sampled from random logits through the mask
//    break no rule (simulation; no model needed).
require('./stub-tone');
const assert = require('assert');
const tf = require('@tensorflow/tfjs');
const g = require('./generate');

const PRIMER = {
  notes: [{ pitch: 60, quantizedStartStep: 0, quantizedEndStep: 1 }],
  quantizationInfo: { stepsPerQuarter: 4 },
  totalQuantizedSteps: 1,
};

async function equivalence(id) {
  g.useLevel('e1');
  const chords = id === 'chord_pitches_improv' ? g.rules().chords : undefined;
  await g.verifyCheckpoint(id);
  const model = await g.loadModel(id);
  const steps = g.rules().bars * g.rules().stepsPerBar;
  const lib = await model.continueSequenceAndReturnProbabilities(PRIMER, steps - 1, undefined, chords);
  const ours = g.generate(model, chords, { masked: false, temp: 0, seed: 1, withProbs: true });
  assert.strictEqual(lib.probs.length, ours.probs.length);
  let maxDiff = 0;
  let argMismatch = 0;
  for (let t = 0; t < lib.probs.length; t++) {
    const a = lib.probs[t];
    const b = ours.probs[t];
    for (let i = 0; i < a.length; i++) maxDiff = Math.max(maxDiff, Math.abs(a[i] - b[i]));
    const argA = a.indexOf(Math.max(...a));
    if (argA !== ours.events[t + 1]) argMismatch++;
  }
  model.dispose();
  console.log(`equivalence ${id}: ${lib.probs.length} steps, max |p_lib - p_ours| = ${maxDiff.toExponential(2)}, argmax mismatches = ${argMismatch}`);
  assert.ok(maxDiff < 1e-4, 'probabilities differ');
  assert.strictEqual(argMismatch, 0);
}

async function repeat() {
  g.useLevel('e3');
  const model = await g.loadModel('chord_pitches_improv');
  const chords = g.rules().chords;
  const a = g.generate(model, chords, { masked: true, temp: 1, seed: 7 }).events;
  const b = g.generate(model, chords, { masked: true, temp: 1, seed: 7 }).events;
  model.dispose();
  assert.deepStrictEqual(a, b);
  console.log(`repeat: chord_pitches_improv e3 seed 7 twice, ${a.length} events identical`);
}

// Same state machine as generate(), with random logits in place of the model.
function simulate(level, n) {
  g.useLevel(level);
  const R = g.rules();
  const minPitch = 48;
  const depth = 38;
  const total = R.bars * R.stepsPerBar;
  const why = {};
  for (let k = 0; k < n; k++) {
    const rand = g.rng(k + 1);
    const events = [R.pitches[0] - minPitch + 2];
    let cur = { onset: 0, pitch: R.pitches[0] };
    let lastPitch = cur.pitch;
    for (let t = 1; t < total; t++) {
      const logits = Array.from({ length: depth }, () => (rand() - 0.5) * 8);
      const mask = g.allowed(t, cur, lastPitch, minPitch, depth);
      assert.ok(mask.some((x) => x), `dead end at step ${t} (level ${level}, run ${k})`);
      const ev = g.sampleIndex(logits, mask, 1, rand);
      events.push(ev);
      if (ev >= 2) {
        cur = { onset: t, pitch: ev - 2 + minPitch };
        lastPitch = cur.pitch;
      } else if (ev === 1 && cur.pitch !== null) cur = { onset: t, pitch: null };
    }
    for (const b of g.violations(g.toNotes({ events, minPitch }))) why[b] = (why[b] ?? 0) + 1;
  }
  console.log(`mask simulation ${level}: ${n} tunes, violations ${JSON.stringify(why)}`);
  assert.deepStrictEqual(why, {});
}

(async () => {
  await tf.setBackend('cpu');
  simulate('e1', 5000);
  simulate('e3', 5000);
  for (const id of ['basic_rnn', 'melody_rnn', 'chord_pitches_improv']) await equivalence(id);
  await repeat();
  console.log('all checks passed');
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
