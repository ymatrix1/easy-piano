// Minimal reader for docs/specs/content-format.md note tokens, for playback only.
// token := (pitch+ | "r") ":" dur ("@" finger+)? ("(" ann ")")?   plus {directives}
export const PARTS = ['RH', 'LH', 'ACC', 'BASS', 'DRUMS'];

const STEP = { C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11 };
const PITCH = /([A-G])([#bn]?)(-?\d)/g;

export function midi(letter, acc, octave) {
  return 12 * (Number(octave) + 1) + STEP[letter] + (acc === '#' ? 1 : acc === 'b' ? -1 : 0);
}

/** Duration in whole notes: "4" quarter, "2." dotted half, "3/8" explicit. */
export function wholeNotes(dur) {
  if (dur.includes('/')) {
    const [n, d] = dur.split('/').map(Number);
    return n / d;
  }
  const dots = dur.match(/\.*$/)[0].length;
  let len = 1 / Number(dur.slice(0, dur.length - dots));
  let add = len;
  for (let i = 0; i < dots; i++) { add /= 2; len += add; }
  return len;
}

export function parseHand(text) {
  const out = [];
  let t = 0;
  const clean = text.replace(/\{[^}]*\}/g, ' ').replace(/\([^)]*\)/g, '');
  for (const tok of clean.trim().split(/\s+/)) {
    if (!tok) continue;
    const [head, rest] = tok.split(':');
    const dur = wholeNotes(rest.split('@')[0]);
    if (head !== 'r') {
      const pitches = [...head.matchAll(PITCH)].map((m) => midi(m[1], m[2], m[3]));
      out.push({ t, dur, pitches });
    }
    t += dur;
  }
  return out;
}

/** Song -> { notes: [{part, start, dur, midi}] in seconds, length }. */
export function parseSong(song) {
  const [num, den] = song.time.split('/').map(Number);
  const secPerWhole = (60 / song.bpm) * den;
  const barSec = (num / den) * secPerWhole;
  const notes = [];
  song.bars.forEach((bar, i) => {
    for (const part of PARTS) {
      if (!bar[part]) continue;
      for (const n of parseHand(bar[part])) {
        for (const m of n.pitches) {
          notes.push({ part, start: i * barSec + n.t * secPerWhole, dur: n.dur * secPerWhole, midi: m });
        }
      }
    }
  });
  return { notes, length: song.bars.length * barSec };
}
