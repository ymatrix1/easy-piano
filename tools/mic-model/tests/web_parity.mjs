// Reads <dir>/audio16.f32, audio48.f32; writes bands.f32 (Frontend on audio16) and rs.f32 (Resampler on audio48).
import { readFileSync, writeFileSync } from 'node:fs';
import { Frontend, Resampler } from '../../../app/web/mic_model_core.js';

const dir = process.argv[2];
const f32 = (n) => { const b = readFileSync(`${dir}/${n}`); return new Float32Array(b.buffer, b.byteOffset, b.length / 4); };
const fe = new Frontend();
const frames = [];
const a16 = f32('audio16.f32');
for (let i = 0; i < a16.length; i += 1000) frames.push(...fe.push(a16.slice(i, i + 1000)));
const flat = new Float32Array(frames.length * 264);
frames.forEach((f, i) => flat.set(f, i * 264));
writeFileSync(`${dir}/bands.f32`, Buffer.from(flat.buffer));
const rs = new Resampler(48000);
const parts = [];
const a48 = f32('audio48.f32');
for (let i = 0; i < a48.length; i += 512) parts.push(rs.push(a48.slice(i, i + 512)));
const out = Float32Array.from(parts.flatMap((p) => [...p]));
writeFileSync(`${dir}/rs.f32`, Buffer.from(out.buffer));
