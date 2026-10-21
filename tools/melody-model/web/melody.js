// Spec prefix, masked decoding and song decoding for the melody model (docs/specs/melody-model.md "Browser export").
// Mirrors melody_model/tokenizer.py (encode_spec, encode_pattern, encode_plan, decode, format_hand).
// No DOM and no onnxruntime here: the model is passed in, so Node tests can drive it with a fake.

export const DURATIONS = ["1", "1.", "2", "2.", "2..", "4", "4.", "4..", "8", "8.", "16", "16.", "32"];
const PATTERN_KEYS = ["rhythm", "interval_min", "accidental", "pitch", "hand", "min_bar_share", "rest", "chord", "hands_together"];
const SHARES = [25, 50, 75, 100];
const STEP_SEMITONES = { C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11 };
const MAX_CHORD = 4; // notes per chord
const CHORD_SPAN = 12; // semitones from the chord's lowest note (playability filter)
const NONE = "<none>";

export function midiOf(name) {
  const m = /^([A-G])(#|b)?(\d)$/.exec(name);
  if (!m) return null;
  return 12 * (+m[3] + 1) + STEP_SEMITONES[m[1]] + (m[2] === "#" ? 1 : m[2] === "b" ? -1 : 0);
}

// Length in 32nd notes ("4." = 12).
export function durUnits(d) {
  const base = parseInt(d, 10);
  const dots = d.length - d.replace(/\.+$/, "").length;
  let len = 32 / base, add = len;
  for (let i = 0; i < dots; i++) { add /= 2; len += add; }
  return len;
}

export function barUnits(time) {
  const [num, den] = time.split("/").map(Number);
  return (num * 32) / den;
}

export function makeVocab(v) {
  const id = {};
  for (const f of ["kind", "pitch", "dur", "finger"]) id[f] = new Map(v[f].map((x, i) => [x, i]));
  const K = (name) => {
    const i = id.kind.get(name);
    if (i === undefined) throw new Error(`no kind ${name}`);
    return i;
  };
  return { ...v, id, K, midi: v.pitch.map((p) => (p === NONE ? null : midiOf(p))), units: v.dur.map((d) => (d === NONE ? 0 : durUnits(d))) };
}

function step(V, kind, pitch = NONE, dur = NONE, finger = NONE) {
  const s = [V.K(kind), V.id.pitch.get(pitch), V.id.dur.get(dur), V.id.finger.get(finger)];
  if (s.some((x) => x === undefined)) throw new Error(`no vocab entry in ${kind} ${pitch} ${dur} ${finger}`);
  return s;
}

function encodePattern(V, p) {
  const unknown = Object.keys(p).filter((k) => !PATTERN_KEYS.includes(k));
  if (unknown.length) throw new Error(`pattern keys ${unknown}`);
  const out = [step(V, "PAT")];
  for (const k of PATTERN_KEYS) {
    if (!(k in p)) continue;
    const v = p[k];
    if (k === "rhythm") out.push(step(V, "PAT_rhythm", NONE, v));
    else if (k === "interval_min") out.push(step(V, `PAT_interval_min_${v}`));
    else if (k === "accidental") out.push(step(V, "PAT_accidental", `${v}4`));
    else if (k === "pitch") out.push(step(V, "PAT_pitch", v));
    else if (k === "hand") out.push(step(V, `PAT_hand_${v}`));
    else if (k === "min_bar_share") out.push(step(V, `PAT_share_${SHARES.find((x) => x >= Math.round(v * 100))}`));
    else if (v === true) out.push(step(V, `PAT_${k}`));
    else throw new Error(`pattern ${k}=${v}`);
  }
  return out;
}

// spec: {time, key, bars, range_lo, range_hi, durs, hands, course?, patterns?, styles?, source?, level?}
// Returns BOS + encode_spec(spec), the prefix the model continues with PLAN.
export function encodeSpec(V, spec) {
  const out = [step(V, "BOS"), step(V, "SPEC")];
  for (const x of [...(spec.styles || [])].sort()) out.push(step(V, `STYLE_${x}`));
  if (spec.source) out.push(step(V, `SRC_${spec.source}`));
  if (spec.level) out.push(step(V, `LEVEL_${spec.level}`));
  out.push(step(V, `COURSE_${spec.course || "none"}`), step(V, `TIME_${spec.time}`), step(V, `KEY_${spec.key}`),
    step(V, `BARS_${spec.bars}`), step(V, "RANGE_LO", spec.range_lo), step(V, "RANGE_HI", spec.range_hi));
  const durs = [...spec.durs].sort((a, b) => DURATIONS.indexOf(a) - DURATIONS.indexOf(b));
  for (const d of durs) out.push(step(V, "DUR_ALLOW", NONE, d));
  out.push(step(V, `HANDS_${spec.hands}`));
  for (const p of spec.patterns || []) out.push(...encodePattern(V, p));
  out.push(step(V, "SPEC_END"));
  return out;
}

// ---- grammar: which field values a candidate may take next ----

export class Grammar {
  constructor(V, spec) {
    this.V = V;
    this.spec = spec;
    this.cap = barUnits(spec.time);
    this.lo = midiOf(spec.range_lo);
    this.hi = midiOf(spec.range_hi);
    this.hands = spec.hands === "BOTH" ? ["RH", "LH"] : [spec.hands];
    const ids = (names) => { const set = new Set(names); return V.dur.map((d, i) => (set.has(d) ? i : -1)).filter((i) => i >= 0); };
    this.durIds = ids(spec.durs);
    // Optional taught-set masks (practice mode, generate.py Masker): pitches per hand, max leap in
    // semitones, chord size per hand, rest durations. Pitches match by spelling, so no enharmonic (Fb4 for E4) slips in; no ties and no fingering (the rubric checks the rest).
    const m = spec.mask;
    this.mask = m ? {
      pitches: Object.fromEntries(this.hands.map((h) => [h, new Set(m.pitches[h] || [])])),
      maxLeap: m.max_leap,
      poly: Object.fromEntries(this.hands.map((h) => [h, Math.min(MAX_CHORD, (m.poly && m.poly[h]) || 1)])),
    } : null;
    this.restIds = m ? ids(m.rest_durs || []) : this.durIds;
    const all = [...new Set([...this.durIds, ...this.restIds])];
    // fill[r]: r 32nds can be filled exactly with allowed durations
    this.fill = new Array(this.cap + 1).fill(false);
    this.fill[0] = true;
    for (let r = 1; r <= this.cap; r++) this.fill[r] = all.some((i) => V.units[i] <= r && this.fill[r - V.units[i]]);
    if (!this.fill[this.cap]) throw new Error(`allowed durations cannot fill a ${spec.time} bar`);
    const g = (pre) => V.kind.map((k, i) => (k.startsWith(pre) ? i : -1)).filter((i) => i >= 0);
    this.sec = g("SEC_");
    this.cad = g("CAD_");
    this.con = g("CON_");
  }

  init() {
    return { phase: "PLAN", plan: 0, maxSec: -1, bar: 0, hand: 0, used: 0, events: 0, last: null, root: null, top: null, chord: 0, fingered: false, prev: this.startPrev() };
  }

  kinds(st) {
    const V = this.V, K = V.K;
    switch (st.phase) {
      case "PLAN": return [K("PLAN")];
      case "PLAN_SEQ": {
        const pos = st.plan % 3;
        if (st.plan === 3 * this.spec.bars) return [K("PLAN_END")];
        if (pos === 0) return this.sec.slice(0, Math.min(this.sec.length, st.maxSec + 2)); // lettered from A
        return pos === 1 ? this.cad : this.con;
      }
      case "BAR": return [K("BAR")];
      case "HAND": return [K(this.hands[st.hand])];
      case "IN": {
        const rem = this.cap - st.used, out = [];
        const fits = (ids) => ids.some((i) => V.units[i] <= rem && this.fill[rem - V.units[i]]);
        if (rem > 0 && st.last !== "TIE" && fits(this.restIds)) out.push(K("REST"));
        if (rem > 0 && fits(this.durIds) && this.notePitches(st).length) out.push(K("NOTE"));
        const inChord = st.last === "NOTE" || st.last === "CHORD";
        const maxChord = this.mask ? this.mask.poly[this.hands[st.hand]] : MAX_CHORD;
        if (inChord && st.chord < maxChord && this.chordPitches(st).length) out.push(K("CHORD"));
        const lastSlot = st.bar === this.spec.bars && st.hand === this.hands.length - 1 && rem === 0;
        if (inChord && !lastSlot && !this.mask) out.push(K("TIE"));
        if (rem === 0 && st.events > 0) {
          if (st.hand < this.hands.length - 1) out.push(K(this.hands[st.hand + 1]));
          else out.push(K(st.bar < this.spec.bars ? "BAR" : "END"));
        }
        return out;
      }
      default: return [K("PAD")];
    }
  }

  // Streaming practice: `mask.start` ({hand: pitch name}) is the last note of the previous chunk, so the
  // leap rule holds across chunk boundaries.
  startPrev() {
    const start = (this.spec.mask && this.spec.mask.start) || {};
    return Object.fromEntries(Object.entries(start).map(([h, p]) => [h, midiOf(p)]));
  }

  // With a mask: taught pitches of the current hand within max leap of that hand's previous note.
  notePitches(st) {
    const out = [], hand = this.hands[st.hand], prev = st.prev[hand];
    const taught = this.mask && this.mask.pitches[hand];
    this.V.midi.forEach((m, i) => {
      if (m === null || m < this.lo || m > this.hi) return;
      if (taught && (!taught.has(this.V.pitch[i]) || (prev != null && Math.abs(m - prev) > this.mask.maxLeap))) return;
      out.push(i);
    });
    return out;
  }

  chordPitches(st) {
    const out = [], taught = this.mask && this.mask.pitches[this.hands[st.hand]];
    this.V.midi.forEach((m, i) => { if (m !== null && m > st.top && m <= this.hi && m - st.root <= CHORD_SPAN && (!taught || taught.has(this.V.pitch[i]))) out.push(i); });
    return out;
  }

  // Allowed ids of `field` given the sampled kind (and pitch). [0] = field does not apply.
  values(st, field, kindName) {
    const V = this.V;
    if (field === "pitch") {
      if (kindName === "NOTE") return this.notePitches(st);
      if (kindName === "CHORD") return this.chordPitches(st);
      return [0];
    }
    if (field === "dur") {
      if (kindName !== "NOTE" && kindName !== "REST") return [0];
      const rem = this.cap - st.used;
      return (kindName === "REST" ? this.restIds : this.durIds).filter((i) => V.units[i] <= rem && this.fill[rem - V.units[i]]);
    }
    if (field === "finger") {
      if (this.mask) return [0];
      if (kindName === "NOTE") return [0, 1, 2, 3, 4, 5];
      if (kindName === "CHORD") return st.fingered ? [1, 2, 3, 4, 5] : [0];
      return [0];
    }
    throw new Error(field);
  }

  advance(st, s) {
    const V = this.V, k = V.kind[s[0]];
    switch (st.phase) {
      case "PLAN": st.phase = "PLAN_SEQ"; break;
      case "PLAN_SEQ":
        if (k === "PLAN_END") st.phase = "BAR";
        else { if (st.plan % 3 === 0) st.maxSec = Math.max(st.maxSec, this.sec.indexOf(s[0])); st.plan++; }
        break;
      case "BAR": st.bar++; st.hand = 0; st.phase = "HAND"; break;
      case "HAND": st.used = 0; st.events = 0; st.last = null; st.phase = "IN"; break;
      case "IN":
        if (k === "NOTE") {
          st.used += V.units[s[2]]; st.events++; st.last = "NOTE";
          st.root = st.top = V.midi[s[1]]; st.chord = 1; st.fingered = s[3] !== 0;
          st.prev[this.hands[st.hand]] = V.midi[s[1]];
        } else if (k === "CHORD") { st.top = V.midi[s[1]]; st.chord++; st.last = "CHORD"; }
        else if (k === "REST") { st.used += V.units[s[2]]; st.events++; st.last = "REST"; }
        else if (k === "TIE") st.last = "TIE";
        else if (k === "RH" || k === "LH") { st.hand++; st.used = 0; st.events = 0; st.last = null; }
        else if (k === "BAR") { st.bar++; st.hand = 0; st.phase = "HAND"; }
        else if (k === "END") st.phase = "DONE";
        break;
    }
  }
}

// ---- sampling ----

export function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Sample one id from `logits` (a row) restricted to `allowed`; returns [id, log p under the masked distribution].
function pick(logits, allowed, temperature, rng) {
  if (allowed.length === 1) return [allowed[0], 0];
  let mx = -Infinity;
  for (const i of allowed) mx = Math.max(mx, logits[i] / temperature);
  const w = allowed.map((i) => Math.exp(logits[i] / temperature - mx));
  const z = w.reduce((a, b) => a + b, 0);
  let r = rng() * z;
  for (let j = 0; j < allowed.length; j++) {
    r -= w[j];
    if (r <= 0 || j === allowed.length - 1) return [allowed[j], Math.log(w[j] / z)];
  }
}

// model: { start(prefix, n) -> h, next(steps) -> h, heads(h, kind, pitch, dur) -> [kindL, pitchL, durL, fingerL] }
// h is opaque; heads returns Float32Arrays of shape (n, vocab). All async.
// Returns n candidates {steps, logp, len}, sorted by mean log p (best first); unfinished ones have done = false.
export async function generate(V, model, spec, { n = 8, temperature = 1.0, seed = 1, maxSteps = 900 } = {}) {
  const g = new Grammar(V, spec);
  const rng = mulberry32(seed);
  const prefix = encodeSpec(V, spec);
  const states = Array.from({ length: n }, () => g.init());
  const cands = Array.from({ length: n }, () => ({ steps: prefix.map((s) => s.slice()), logp: 0, len: 0 }));
  const sizes = [V.kind.length, V.pitch.length, V.dur.length, V.finger.length];
  const PAD = [V.K("PAD"), 0, 0, 0];
  let h = await model.start(prefix, n);
  for (let t = 0; t < maxSteps && states.some((s) => s.phase !== "DONE"); t++) {
    const chosen = states.map(() => [0, 0, 0, 0]);
    for (let f = 0; f < 4; f++) {
      const allowed = states.map((st, b) => (st.phase === "DONE" ? [0]
        : f === 0 ? g.kinds(st) : g.values(st, ["pitch", "dur", "finger"][f - 1], V.kind[chosen[b][0]])));
      // the heads run only when some candidate has a real choice for this field
      const lg = allowed.some((a) => a.length > 1)
        ? await model.heads(h, chosen.map((c) => c[0]), chosen.map((c) => c[1]), chosen.map((c) => c[2])) : null;
      for (let b = 0; b < n; b++) {
        const st = states[b];
        if (st.phase === "DONE") continue;
        // dead end (a taught-set mask leaves nothing that fits): drop this candidate, keep the others
        if (!allowed[b].length) { st.phase = "DONE"; st.dead = true; chosen[b] = PAD.slice(); continue; }
        const row = lg && lg[f].subarray(b * sizes[f], (b + 1) * sizes[f]);
        const [id, lp] = pick(row, allowed[b], temperature, rng);
        chosen[b][f] = id;
        cands[b].logp += lp;
      }
    }
    for (let b = 0; b < n; b++) {
      if (states[b].phase === "DONE") { chosen[b] = PAD.slice(); continue; }
      g.advance(states[b], chosen[b]);
      cands[b].steps.push(chosen[b]);
      cands[b].len++;
    }
    h = await model.next(chosen);
  }
  states.forEach((st, b) => { cands[b].done = st.phase === "DONE" && !st.dead; cands[b].mean = cands[b].logp / Math.max(1, cands[b].len); });
  return cands.sort((a, b) => (b.done - a.done) || (b.mean - a.mean));
}

// ---- decoding (tokenizer.decode) ----

export function formatHand(events) {
  const out = [];
  for (const e of events) {
    const head = e.pitches.length ? e.pitches.join("") : "r";
    out.push(`${head}:${e.dur}${e.fingers.length ? "@" + e.fingers.join("") : ""}`);
    if (e.tie) out.push("{tie}");
  }
  return out.join(" ");
}

const PREFIX_KINDS = new Set(["PAD", "BOS", "PAT", "SPEC", "SPEC_END", "RANGE_LO", "RANGE_HI", "DUR_ALLOW", "PLAN", "PLAN_END",
  "CAD_STABLE", "CAD_OPEN", "CON_UP", "CON_DOWN", "CON_FLAT", "FIM_PRE", "FIM_SUF", "FIM_MID"]);
const PREFIX_GROUPS = ["COURSE_", "BARS_", "HANDS_", "PAT_", "SEC_", "STYLE_", "SRC_", "LEVEL_"];

export function decode(V, steps) {
  let time = null, key = null, events = null, hand = null;
  const bars = [];
  const bad = (msg) => { throw new Error(msg); };
  const flush = () => {
    if (events !== null) {
      if (!events.length) bad(`empty ${hand} in bar ${bars.length}`);
      bars[bars.length - 1][hand] = formatHand(events);
    }
  };
  for (let i = 0; i < steps.length; i++) {
    const s = steps[i];
    const sizes = [V.kind.length, V.pitch.length, V.dur.length, V.finger.length];
    if (s.length !== 4 || s.some((v, j) => !(v >= 0 && v < sizes[j]))) bad(`step ${i}: ids out of range ${s}`);
    const kind = V.kind[s[0]], pitch = V.pitch[s[1]], dur = V.dur[s[2]], finger = V.finger[s[3]];
    if (kind === NONE) bad(`step ${i}: no kind`);
    if (kind.startsWith("TIME_")) time = kind.slice(5);
    else if (kind.startsWith("KEY_")) key = kind.slice(4);
    else if (kind === "BAR") { flush(); events = null; hand = null; bars.push({}); }
    else if (kind === "RH" || kind === "LH") {
      if (!bars.length) bad(`step ${i}: ${kind} before BAR`);
      if (kind in bars[bars.length - 1] || kind === hand) bad(`step ${i}: ${kind} twice in bar ${bars.length}`);
      flush();
      events = [];
      hand = kind;
    } else if (kind === "NOTE" || kind === "REST" || kind === "CHORD") {
      if (events === null) bad(`step ${i}: ${kind} outside a hand`);
      if (kind === "NOTE" && (pitch === NONE || dur === NONE)) bad(`step ${i}: NOTE needs pitch and dur`);
      if (kind === "REST" && (dur === NONE || pitch !== NONE || finger !== NONE)) bad(`step ${i}: REST takes only dur`);
      if (kind === "CHORD") {
        if (pitch === NONE || dur !== NONE) bad(`step ${i}: CHORD takes pitch (and finger), no dur`);
        const prev = events[events.length - 1];
        if (!prev || !prev.pitches.length) bad(`step ${i}: CHORD without a preceding NOTE`);
        if ((prev.fingers.length > 0) !== (finger !== NONE)) bad(`step ${i}: fingering on some chord notes only`);
        prev.pitches.push(pitch);
        if (finger !== NONE) prev.fingers.push(+finger);
        continue;
      }
      events.push({ pitches: kind === "REST" ? [] : [pitch], dur, fingers: finger !== NONE ? [+finger] : [], tie: false });
    } else if (kind === "TIE") {
      const prev = events && events[events.length - 1];
      if (!prev || !prev.pitches.length || prev.tie || pitch !== NONE || dur !== NONE || finger !== NONE) bad(`step ${i}: TIE must follow a note and carry no fields`);
      prev.tie = true;
    } else if (kind === "END") break;
    else if (PREFIX_KINDS.has(kind) || PREFIX_GROUPS.some((p) => kind.startsWith(p))) {
      if (bars.length) bad(`step ${i}: ${kind} after the first BAR`);
    } else bad(`step ${i}: unexpected ${kind}`);
  }
  flush();
  if (time === null || key === null) bad("no TIME or KEY");
  if (!bars.length || bars.some((b) => !Object.keys(b).length)) bad("no bars, or an empty bar");
  return { time, key, bars };
}
