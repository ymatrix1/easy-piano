// node --test notation.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { PARTS, parseHand, parseSong, wholeNotes } from './notation.js';

test('durations', () => {
  assert.equal(wholeNotes('4'), 0.25);
  assert.equal(wholeNotes('2.'), 0.75);
  assert.equal(wholeNotes('4..'), 0.4375);
  assert.equal(wholeNotes('3/8'), 0.375);
});

test('chords, rests, accidentals, fingers, directives', () => {
  const { notes, length } = parseHand('C4E4G4:2@135 r:4 {chord:"C"} F#4:8.(acc) Bb3:16');
  assert.deepEqual(notes.map((x) => x.pitches), [[60, 64, 67], [66], [58]]);
  assert.deepEqual(notes.map((x) => x.t), [0, 0.75, 0.9375]);
  assert.equal(length, 1);
});

test('malformed tokens throw', () => {
  for (const bad of ['C4', 'C4:', 'H4:4', 'C4:4@9', 'r:x']) {
    assert.throws(() => parseHand(bad), /bad note token/, bad);
  }
});

test('every content song: each part sums to the time signature in every bar', () => {
  const dir = new URL('../../content/songs/', import.meta.url);
  for (const f of readdirSync(dir)) {
    const song = JSON.parse(readFileSync(new URL(f, dir)));
    const [num, den] = song.time.split('/').map(Number);
    song.bars.forEach((bar, i) => {
      for (const part of PARTS) {
        if (bar[part] === undefined) continue;
        assert.ok(Math.abs(parseHand(bar[part]).length - num / den) < 1e-9, `${f} bar ${i + 1} ${part}`);
      }
    });
    const { notes, length } = parseSong(song);
    assert.ok(notes.length > 0, f);
    assert.ok(notes.every((x) => x.start + x.dur <= length + 1e-6 && x.midi >= 21 && x.midi <= 108), f);
  }
});
