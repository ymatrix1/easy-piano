# Listening test

Blind A/B-style rating of generated tunes against hand-written ones (melody-generation spike, bean `piano-i7ho`, parent research `piano-ze9t`). No build step, no dependencies beyond Python 3 and a browser.

## Run

From this folder:

```bash
python build.py demo-manifest.json
```

From the repo root (the page loads piano samples from `app/assets/piano/`):

```bash
python -m http.server 8770 --bind 127.0.0.1
```

Open <http://127.0.0.1:8770/tools/listening-test/>. Rate every tune 1-5 (keys: Space play/stop, 1-5 rate, Enter next). At the end the page downloads `ratings-<date>.json` (also kept in localStorage, so a reload resumes) and offers "Reveal methods".

```bash
python summarize.py ~/Downloads/ratings-2026-10-20-12-00-00.json
```

prints per-method n / mean / median / familiar count and lists the tunes marked familiar.

## Manifest

```json
{"items": [
  {"path": "../../content/songs/ode-to-joy.json", "method": "control-song"},
  {"path": "gen/rules-001.json", "method": "rules"}
]}
```

`path` is relative to the manifest; files use the song format in `docs/specs/content-format.md` (only `bpm`, `time`, `bars` are read). `method` is any label. `build.py` shuffles (`--seed N` for a fixed order), gives each tune a random opaque id, and writes:

| File | Contents |
|---|---|
| `out/playlist.json` | ids + bpm/time/bars only (no title, path or method) |
| `out/key.json` | id -> method, path. Don't open it before rating. |

`out/` and `ratings*.json` are git-ignored. `demo-manifest.json` holds the 40 hand-written `content/songs` split into `control-song` and `control-drill`.

## Playback

`notation.js` reads note tokens (chords, rests, dots, `n/d`, fingers, `{directives}` and `(annotations)` skipped). `synth.js` plays `RH`/`LH`/`ACC` with the app's FluidR3 piano samples (MIT, see `app/assets/piano/README.md`), `BASS` as a filtered saw and `DRUMS` as a sine/noise kit, scheduled on the WebAudio clock at song bpm. `PAD`/`CHOIR` are not played.

Test: `node --test notation.test.mjs` (parses every `content/songs` file).
