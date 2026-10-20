// node --test notation.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { parseHand, parseSong, wholeNotes } from './notation.js';

test('durations', () => {
  assert.equal(wholeNotes('4'), 0.25);
  assert.equal(wholeNotes('2.'), 0.75);
  assert.equal(wholeNotes('4..'), 0.4375);
  assert.equal(wholeNotes('3/8'), 0.375);
});

test('chords, rests, accidentals, fingers, directives', () => {
  const n = parseHand('C4E4G4:2@135 r:4 {chord:"C"} F#4:8.(acc) Bb3:16');
  assert.deepEqual(n.map((x) => x.pitches), [[60, 64, 67], [66], [58]]);
  assert.deepEqual(n.map((x) => x.t), [0, 0.75, 0.9375]);
});

test('every content song: each part fills each bar', () => {
  const dir = new URL('../../content/songs/', import.meta.url);
  for (const f of readdirSync(dir)) {
    const song = JSON.parse(readFileSync(new URL(f, dir)));
    const { notes, length } = parseSong(song);
    assert.ok(notes.length > 0, f);
    assert.ok(notes.every((x) => x.start + x.dur <= length + 1e-6 && x.midi >= 21 && x.midi <= 108), f);
  }
});
