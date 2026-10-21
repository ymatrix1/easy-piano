// Reads <dir>/in.json {on:[[88]..], fr:[[88]..], expected:[[pitch..] per frame], params}; writes out.json (notes).
import { readFileSync, writeFileSync } from 'node:fs';
import { Decoder } from '../../../app/web/mic_model_core.js';

const dir = process.argv[2];
const { on, fr, expected, params } = JSON.parse(readFileSync(`${dir}/in.json`, 'utf8'));
const dec = new Decoder(params);
const notes = [];
for (let g = 0; g < on.length - 3; g++) {
  dec.expected = new Set(expected[g]);
  notes.push(...dec.push(g, on[g], fr[g]).map((n) => [n.pitch, n.time, n.detectedAt]));
}
writeFileSync(`${dir}/out.json`, JSON.stringify(notes));
