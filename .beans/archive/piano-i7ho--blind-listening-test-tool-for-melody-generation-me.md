---
# piano-i7ho
title: Blind listening-test tool for melody generation methods
status: completed
type: task
priority: normal
tags:
    - melody-gen
created_at: 2026-10-20T21:51:07Z
updated_at: 2026-10-20T22:02:16Z
blocking:
    - piano-ze9t
---

## Context
Melody-generation spike (piano-ze9t) compares rules random walk, PD-song variations, LLM agent skill and Magenta.js against hand-written songs (control). The user rates ~50 tunes blind in ~15 min. Blocked by: none.

## Higher Goal
Pick a generation method by ear, with evidence, before building it into content-cli.

## Acceptance Criteria
- [x] tools/listening-test/build.py: manifest (song paths + hidden method) -> shuffled playlist with opaque ids, key file kept apart
- [x] Static page plays our song format (chords, rests, dotted, n/d durations) RH+LH plus optional ACC/DRUMS/BASS at song bpm
- [x] UI: play/stop, 1-5 rating, 'sounds like a known song' + note, next; method labels hidden until the end
- [x] Ratings downloadable as JSON, localStorage backup
- [x] summarize.py prints per-method mean/median/n and familiar count
- [x] README; demo manifest from content/songs works now

## Out of Scope
Generators themselves, similarity checker, rubric; PAD/CHOIR voices; app integration.

## Summary of Changes
- `tools/listening-test/`: `build.py` (manifest -> shuffled `out/playlist.json` + `out/key.json`), static page (`index.html`, `app.js`, `notation.js`, `synth.js`) using the app's MIT FluidR3 piano samples, `summarize.py`, `demo-manifest.json` (40 content songs), `notation.test.mjs`, README.
- `.claude/launch.json`: `listening-test` preview server.
