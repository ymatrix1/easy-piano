// Blind listening test: plays playlist.json tunes, collects ratings.
// Method labels are not served; summarize.py joins ratings with out/key.json.
import { parseSong } from './notation.js';
import { Synth } from './synth.js';

const STORE = 'listening-test-ratings';
const app = document.getElementById('app');
const synth = new Synth('piano/');

const { tunes } = await (await fetch('playlist.json', { cache: 'no-store' })).json();
const listId = tunes.map((t) => t.id).join(',');
const answered = (r) => r && (r.rating || r.familiar || r.note);
let state = loadState();

// Playback: `gen` bumps on every start and stop, so a start whose samples finish
// loading after a Stop, Next or second Play is discarded.
let gen = 0;
let playing = null;
let pending = false;

function loadState() {
  let old = null;
  try { old = JSON.parse(localStorage.getItem(STORE)); } catch { /* fresh start */ }
  if (old && old.listId === listId) return old;
  // Different playlist: save the earlier session's ratings before replacing them.
  if (old && Object.keys(old.ratings ?? {}).length) download(old, 'previous-');
  return { listId, started: new Date().toISOString(), index: 0, ratings: {}, downloaded: false };
}

function save() {
  try { localStorage.setItem(STORE, JSON.stringify(state)); } catch { /* backup only */ }
}

function exportJson(s) {
  return {
    started: s.started,
    exported: new Date().toISOString(),
    total: s.listId.split(',').length,
    ratings: Object.values(s.ratings).filter(answered),
  };
}

function download(s, prefix = '') {
  const data = exportJson(s);
  const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = `${prefix}ratings-${data.exported.slice(0, 19).replace(/[:T]/g, '-')}.json`;
  a.click();
}

function stop() {
  gen++;
  pending = false;
  playing?.stop();
  playing = null;
}

async function play(tune, r) {
  stop();
  const my = gen;
  r.plays++;
  save();
  showError('');
  pending = true;
  try {
    const handle = await synth.play(parseSong(tune), () => my !== gen);
    if (my !== gen) handle?.stop();
    else playing = handle;
  } catch (e) {
    if (my === gen) showError(`Can't play this tune: ${e.message}`);
  } finally {
    if (my === gen) pending = false;
  }
}

const escape = (s) => s.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
const $ = (id) => document.getElementById(id);
const showError = (msg) => { const el = $('err'); if (el) el.textContent = msg; };

function render() {
  stop();
  document.onkeydown = null;
  if (state.index >= tunes.length) return renderEnd();
  const tune = tunes[state.index];
  const r = (state.ratings[tune.id] ??= { id: tune.id, rating: 0, familiar: false, note: '', plays: 0 });
  app.innerHTML = `
    <progress max="${tunes.length}" value="${state.index}"></progress>
    <p class="muted">Tune ${state.index + 1} of ${tunes.length}</p>
    <div class="row">
      <button id="play" class="primary">&#9654; Play</button>
      <button id="stop">&#9632; Stop</button>
    </div>
    <p id="err" class="err"></p>
    <div class="stars">${[1, 2, 3, 4, 5].map((n) =>
      `<button data-n="${n}" class="${r.rating === n ? 'on' : ''}">${n}</button>`).join('')}</div>
    <div class="row"><label><input type="checkbox" id="fam" ${r.familiar ? 'checked' : ''}> Sounds like a known song</label></div>
    <div class="row"><input type="text" id="note" placeholder="Optional note (which song? what is off?)" value="${escape(r.note)}"></div>
    <div class="row">
      <button id="back" ${state.index ? '' : 'disabled'}>&larr; Back</button>
      <button id="next" class="primary" ${r.rating ? '' : 'disabled'}>Next &rarr;</button>
      <button id="dl">Download ratings</button>
    </div>`;
  const rate = (n) => {
    r.rating = n;
    save();
    app.querySelectorAll('.stars button').forEach((x) => x.classList.toggle('on', Number(x.dataset.n) === n));
    $('next').disabled = false;
  };
  const go = (step) => { state.index += step; save(); render(); };
  $('play').onclick = () => play(tune, r);
  $('stop').onclick = stop;
  app.querySelectorAll('.stars button').forEach((b) => (b.onclick = () => rate(Number(b.dataset.n))));
  $('fam').onchange = (e) => { r.familiar = e.target.checked; save(); };
  $('note').oninput = (e) => { r.note = e.target.value; save(); };
  $('back').onclick = () => go(-1);
  $('next').onclick = () => go(1);
  $('dl').onclick = () => download(state);
  document.onkeydown = (e) => {
    if (e.target.tagName === 'INPUT' && e.target.type === 'text') return;
    if (e.key === ' ') { e.preventDefault(); playing || pending ? stop() : play(tune, r); }
    else if (/^[1-5]$/.test(e.key)) rate(Number(e.key));
    else if (e.key === 'Enter' && r.rating) go(1);
  };
}

function renderEnd() {
  if (!state.downloaded) {
    download(state);
    state.downloaded = true;
    save();
  }
  app.innerHTML = `<p>Done. Ratings downloaded (also kept in this browser).</p>
    <p class="muted">Methods stay hidden here; run summarize.py on the downloaded file.</p>
    <div class="row"><button id="dl">Download again</button>
    <button id="back">&larr; Back</button><button id="restart">Start over</button></div>`;
  $('dl').onclick = () => download(state);
  $('back').onclick = () => { state.index--; save(); render(); };
  $('restart').onclick = () => {
    if (!confirm('Clear saved ratings and start over?')) return;
    localStorage.removeItem(STORE);
    state = loadState();
    render();
  };
}

render();
