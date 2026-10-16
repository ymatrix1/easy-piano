// Copies the Basic Pitch TF.js model from node_modules into public/ so Vite serves it.
import { cpSync, existsSync } from 'node:fs';
const src = 'node_modules/@spotify/basic-pitch/model';
if (existsSync(src)) cpSync(src, 'public/basic-pitch-model', { recursive: true });
