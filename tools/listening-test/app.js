// Blind listening test: plays out/playlist.json tunes, collects ratings.
import { parseSong } from './notation.js';
import { Synth } from './synth.js';

const STORE = 'listening-test-ratings';
const app = document.getElementById('app');
const synth = new Synth('../../app/assets/piano/');

const { tunes } = await (await fetch('out/playlist.json', { cache: 'no-store' })).json();
const listId = tunes.map((t) => t.id).join(',');
let state = loadState();
let playing = null;

function loadState() {
  try {
    const s = JSON.parse(localStorage.getItem(STORE));
    if (s && s.listId === listId) return s;
  } catch { /* fresh start */ }
  return { listId, started: new Date().toISOString(), index: 0, ratings: {} };
}

function save() {
  try { localStorage.setItem(STORE, JSON.stringify(state)); } catch { /* backup only */ }
}

function exportJson() {
  const ratings = tunes.map((t) => state.ratings[t.id]).filter((r) => r && r.rating);
  return { started: state.started, exported: new Date().toISOString(), total: tunes.length, ratings };
}

function download() {
  const blob = new Blob([JSON.stringify(exportJson(), null, 2)], { type: 'application/json' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = `ratings-${state.started.slice(0, 19).replace(/[:T]/g, '-')}.json`;
  a.click();
}

function stop() {
  playing?.stop();
  playing = null;
}

const escape = (s) => s.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
const $ = (id) => document.getElementById(id);

function render() {
  stop();
  document.onkeydown = null;
  if (state.index >= tunes.length) return renderEnd();
  const tune = tunes[state.index];
  const r = (state.ratings[tune.id] ??= { id: tune.id, rating: 0, familiar: false, note: '', plays: 0 });
  app.innerHTML = `
    <progress max="${tunes.length}" value="${state.index}"></progress>
    <p class="muted">Tune ${state.index + 1} of ${tunes.length} - ${tune.bpm} bpm - ${tune.time} - ${tune.bars.length} bars</p>
    <div class="row">
      <button id="play" class="primary">&#9654; Play</button>
      <button id="stop">&#9632; Stop</button>
    </div>
    <div class="stars">${[1, 2, 3, 4, 5].map((n) =>
      `<button data-n="${n}" class="${r.rating === n ? 'on' : ''}">${n}</button>`).join('')}</div>
    <div class="row"><label><input type="checkbox" id="fam" ${r.familiar ? 'checked' : ''}> Sounds like a known song</label></div>
    <div class="row"><input type="text" id="note" placeholder="Optional note (which song? what is off?)" value="${escape(r.note)}"></div>
    <div class="row">
      <button id="back" ${state.index ? '' : 'disabled'}>&larr; Back</button>
      <button id="next" class="primary" ${r.rating ? '' : 'disabled'}>Next &rarr;</button>
      <button id="dl">Download ratings</button>
    </div>`;
  const play = async () => {
    stop();
    r.plays++;
    save();
    playing = await synth.play(parseSong(tune));
  };
  const rate = (n) => {
    r.rating = n;
    save();
    app.querySelectorAll('.stars button').forEach((x) => x.classList.toggle('on', Number(x.dataset.n) === n));
    $('next').disabled = false;
  };
  const next = () => { state.index++; save(); render(); };
  $('play').onclick = play;
  $('stop').onclick = stop;
  app.querySelectorAll('.stars button').forEach((b) => (b.onclick = () => rate(Number(b.dataset.n))));
  $('fam').onchange = (e) => { r.familiar = e.target.checked; save(); };
  $('note').oninput = (e) => { r.note = e.target.value; save(); };
  $('back').onclick = () => { state.index--; save(); render(); };
  $('next').onclick = next;
  $('dl').onclick = download;
  document.onkeydown = (e) => {
    if (e.target.tagName === 'INPUT' && e.target.type === 'text') return;
    if (e.key === ' ') { e.preventDefault(); playing ? stop() : play(); }
    else if (/^[1-5]$/.test(e.key)) rate(Number(e.key));
    else if (e.key === 'Enter' && r.rating) next();
  };
}

function renderEnd() {
  download();
  app.innerHTML = `<p>Done. Ratings downloaded (also kept in this browser).</p>
    <div class="row"><button id="dl">Download again</button><button id="reveal">Reveal methods</button>
    <button id="back">&larr; Back</button><button id="restart">Start over</button></div>
    <div id="out"></div>`;
  $('dl').onclick = download;
  $('back').onclick = () => { state.index--; save(); render(); };
  $('restart').onclick = () => {
    if (!confirm('Clear saved ratings and start over?')) return;
    localStorage.removeItem(STORE);
    state = loadState();
    render();
  };
  $('reveal').onclick = async () => {
    const res = await fetch('out/key.json', { cache: 'no-store' });
    if (!res.ok) { $('out').textContent = 'out/key.json not found.'; return; }
    const key = await res.json();
    const by = {};
    for (const r of exportJson().ratings) (by[key[r.id]?.method ?? '?'] ??= []).push(r);
    $('out').innerHTML = `<table><tr><th>method</th><th>n</th><th>mean</th><th>familiar</th></tr>${
      Object.entries(by).map(([m, rs]) => `<tr><td>${escape(m)}</td><td>${rs.length}</td><td>${
        (rs.reduce((s, r) => s + r.rating, 0) / rs.length).toFixed(2)}</td><td>${
        rs.filter((r) => r.familiar).length}</td></tr>`).join('')}</table>`;
  };
}

render();
