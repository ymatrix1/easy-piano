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

const TOKEN = /^(r|(?:[A-G][#bn]?-?\d)+):(\d+\.*|\d+\/\d+)(?:@[1-5]+)?$/;

/** Hand string -> { notes: [{t, dur, pitches}], length } in whole notes. Throws on a bad token. */
export function parseHand(text) {
  const notes = [];
  let t = 0;
  const clean = text.replace(/\{[^}]*\}/g, ' ').replace(/\([^)]*\)/g, '');
  for (const tok of clean.trim().split(/\s+/)) {
    if (!tok) continue;
    const m = TOKEN.exec(tok);
    if (!m) throw new Error(`bad note token "${tok}"`);
    const dur = wholeNotes(m[2]);
    if (m[1] !== 'r') {
      const pitches = [...m[1].matchAll(PITCH)].map((p) => midi(p[1], p[2], p[3]));
      notes.push({ t, dur, pitches });
    }
    t += dur;
  }
  return { notes, length: t };
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
      for (const n of parseHand(bar[part]).notes) {
        for (const m of n.pitches) {
          notes.push({ part, start: i * barSec + n.t * secPerWhole, dur: n.dur * secPerWhole, midi: m });
        }
      }
    }
  });
  return { notes, length: song.bars.length * barSec };
}
