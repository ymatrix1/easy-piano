# Listening test

Blind A/B-style rating of generated tunes against hand-written ones (melody-generation spike, bean `piano-i7ho`, parent research `piano-ze9t`). No build step, no dependencies beyond Python 3 and a browser.

## Run

From this folder:

```bash
python build.py demo-manifest.json
```

Serve **only** the staged site (it holds the page, piano samples and the playlist; the key stays outside it):

```bash
python -m http.server 8770 --bind 127.0.0.1 --directory out/site
```

Open <http://127.0.0.1:8770/>. Rate every tune 1-5 (keys: Space play/stop, 1-5 rate, Enter next). At the end the page downloads `ratings-<time>.json` once (also kept in localStorage, so a reload resumes). If the playlist changes, the old session's ratings download as `previous-ratings-*.json` before they are replaced. The page never shows methods; only `summarize.py` does.

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
| `out/site/` | page files, `piano/` samples, `playlist.json`: ids + bpm/time/bars, with fingering, annotations, directives and non-played parts stripped |
| `out/key.json` | id -> method, path. Not served. Don't open it before rating. |

Edit the page sources here, then re-run `build.py` to restage. `out/` and `ratings*.json` are git-ignored. `demo-manifest.json` holds the 40 hand-written `content/songs` split into `control-song` and `control-drill`.

## Playback

`notation.js` reads note tokens (chords, rests, dots, `n/d`, fingers, `{directives}` and `(annotations)` skipped). `synth.js` plays `RH`/`LH`/`ACC` with the app's FluidR3 piano samples (MIT, see `app/assets/piano/README.md`), `BASS` as a filtered saw and `DRUMS` as a sine/noise kit, scheduled on the WebAudio clock at song bpm. `PAD`/`CHOIR` are not played.

Test: `npm test` or `node --test notation.test.mjs` (token parsing, bad tokens, bar sums of every `content/songs` file).

Residual tells: tempo, metre and length still differ between tunes and are audible; keep generated tunes in the same ranges as the controls.
