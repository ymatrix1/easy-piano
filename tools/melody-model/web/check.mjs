// Node check of melody.js against fixtures written by tests/test_web.py:
//   node web/check.mjs <fixture.json> <out.json>
// 1. encodeSpec(spec) equals the Python prefix; 2. decode(steps) equals tokenizer.decode;
// 3. masked generation with a random-logit fake model; the generated steps go to <out.json> for Python to check.
import { readFileSync, writeFileSync } from "node:fs";
import { decode, encodeSpec, generate, makeVocab, mulberry32 } from "./melody.js";

const [fixturePath, outPath] = process.argv.slice(2);
const fx = JSON.parse(readFileSync(fixturePath, "utf8"));
const V = makeVocab(fx.vocab);
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);
let fails = 0;
const fail = (msg) => { fails++; console.error("FAIL", msg); };

for (const c of fx.specs) if (!eq(encodeSpec(V, c.spec), c.steps)) fail(`encodeSpec ${JSON.stringify(c.spec)}`);
for (const c of fx.songs) {
  const got = decode(V, c.steps);
  if (!eq(got, c.decoded)) fail(`decode ${c.name}: ${JSON.stringify(got).slice(0, 200)}`);
}

function fakeModel(seed) {
  const rng = mulberry32(seed);
  const sizes = [V.kind.length, V.pitch.length, V.dur.length, V.finger.length];
  let n = 0;
  return {
    async start(prefix, k) { n = k; return null; },
    async next() { return null; },
    async heads() { return sizes.map((s) => Float32Array.from({ length: n * s }, () => 4 * rng())); },
  };
}

const generated = [];
for (const [i, spec] of fx.gen_specs.entries()) {
  const cands = await generate(V, fakeModel(i + 1), spec, { n: 4, seed: i + 1 });
  for (const c of cands) {
    if (!c.done) fail(`generation ${i} did not finish`);
    generated.push({ spec, steps: c.steps, decoded: decode(V, c.steps) });
  }
}
writeFileSync(outPath, JSON.stringify(generated));
console.log(`specs ${fx.specs.length}, songs ${fx.songs.length}, generated ${generated.length}, fails ${fails}`);
process.exit(fails ? 1 : 0);
