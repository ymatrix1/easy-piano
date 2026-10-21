# Instrument samples for piano and backing band

Checked: 2026-10-21

Sources: licence files and READMEs of each project (links below); file listings and sizes from the GitHub API and HTTP `Content-Length`; files we downloaded and inspected locally with ffmpeg (duration, bitrate, levels). `.agents/rules/content-and-licensing.md`.

Question: which openly licensed samples can replace the synthesized `DRUMS`/`BASS`/`PAD`/`CHOIR` voices (D14) and the short piano samples, within a web budget, so play-along stops sounding like a chiptune?

## Why it sounds like a chiptune today

| Part | Today | Problem |
|---|---|---|
| Piano | FluidR3_GM via midi-js-soundfonts, 21 MP3s C2–C7, 0.54 MB | Every note is cut at 3.1 s (no natural decay), one velocity, mono-ish |
| `DRUMS` | Noise + oscillator blips | Classic 8-bit drum sound |
| `BASS` | Saw + sine through a closing low-pass | Synth bass |
| `PAD` | 3 detuned saws | Synth pad |
| `CHOIR` | 2 saws through /u/ formant filters | Buzzy "robot" voice |

No reverb, no dynamics, every app-played note at one fixed velocity and exactly on the grid.

## Candidates

A set is usable only if the licence is CC0, PD, MIT/BSD or CC-BY(-SA) with attribution we can carry.

| Instrument | Candidate | Licence | Attribution | Size (as we'd ship) | Verdict |
|---|---|---|---|---|---|
| Piano | **Salamander Grand Piano V3** (Alexander Holm), MP3 renders in [Tonejs/audio](https://github.com/Tonejs/audio/tree/master/salamander) | CC-BY 3.0 | Required: "Salamander Grand Piano V3 by Alexander Holm, CC-BY 3.0" | 29 files C1–C8 every 3 semitones, 1.90 MB (stereo, ~39 kbps, up to 16 s full decay) | **Use** |
| Piano | FluidR3_GM acoustic grand ([gleitz/midi-js-soundfonts](https://github.com/gleitz/midi-js-soundfonts)) | MIT | Licence file | 21 files, 0.54 MB, 3.1 s cut | Replace |
| Piano | Salamander full SFZ ([sfzinstruments/SalamanderGrandPiano](https://github.com/sfzinstruments/SalamanderGrandPiano)), 16 velocity layers | CC-BY 3.0 | same | Hundreds of MB FLAC; ~4 layers would be ~8 MB as MP3 | Later, if a velocity-layer budget is approved |
| Drums | **Virtuosity Drums** v0.925 (Versilian Studios, Karoryfer Samples), [sfzinstruments/virtuosity_drums](https://github.com/sfzinstruments/virtuosity_drums) | CC0 1.0 | None (we credit anyway) | Release zip 1.2 GB; we take 5 hits × 4 mics, mix to one-shots: 70 KB | **Use** |
| Drums | Salamander Drumkit, Hydrogen GMRockKit | Unclear / GPL kits | — | — | Skip (licence) |
| Bass | **FluidR3_GM electric bass (finger)** | MIT | Licence file | 13 files C1–C4, 0.21 MB | **Use** |
| Bass | FluidR3_GM acoustic bass | MIT | same | similar | Alternative for acoustic songs |
| Strings pad | **FluidR3_GM string ensemble 1** | MIT | same | 13 files C3–C6, 0.33 MB, steady 0.2–3.0 s (loopable) | **Use** |
| Strings pad | VSCO-2 CE ([sgossner/VSCO-2-CE](https://github.com/sgossner/VSCO-2-CE)) | CC0 | None | Solo/section sustains, larger, needs looping work | Later (richer strings) |
| Choir "ooh" | **FluidR3_GM voice oohs** | MIT | same | 13 files C3–C6, 0.33 MB, loopable | **Use** |
| Choir | FluidR3_GM choir aahs | MIT | same | similar | Alternative vowel |
| Reverb IR | Generated in code (decaying filtered stereo noise, 1.8 s) | n/a (ours) | — | 0 bytes | **Use** |
| Reverb IR | OpenAIR impulse responses | Mostly CC-BY | Per file | 100–500 KB | Not needed now |

All FluidR3 band instruments are already under the same MIT licence file we ship for the piano.

## Budget

| | Before | After |
|---|---|---|
| Piano | 0.54 MB | 1.90 MB |
| Band (bass, strings, choir, drums) | 0 | 0.95 MB |
| **Total audio** | **0.54 MB** | **2.87 MB** (target was ≤ 15 MB, piano ≤ 10 MB) |

Loading: piano loads on first use (all files in parallel; before they were fetched one after another). Band instruments load only for songs that have those parts, during the count-in. Browsers cache them like any app asset.

## Measurement (Ode to Joy play-along, web, offline render)

Same song, same scheduling code, rendered with `OfflineAudioContext` through the app's real synth (`?mixprobe` + `window.epMeasureMix()`, `app/lib/audio/piano_synth_web.dart`). Whole-song RMS / peak in dBFS; "vs ACC" is RMS relative to the companion piano.

| Part | Before RMS | Before peak | Before vs ACC | After RMS | After peak | After vs ACC |
|---|---|---|---|---|---|---|
| `ACC` | -30.4 | -12.6 | 0 | -21.4 | -4.8 | 0 |
| `BASS` | -36.2 | -29.6 | -5.8 | -26.6 | -13.7 | -5.2 |
| `DRUMS` | -42.4 | -20.6 | -12.1 | -30.3 | -11.4 | -8.9 |
| `CHOIR` | -45.8 | -27.0 | -15.4 | -35.4 | -18.2 | -14.0 |
| `PAD` | -46.5 | -33.7 | -16.2 | -36.4 | -21.8 | -15.0 |
| Mix | -29.1 | -10.1 | | -19.9 | -3.5 | |

Piano first load (local server, decode included, Chrome in the Claude preview pane): 3.57 s before, 1.65 s after. Network time on the real site adds roughly size / bandwidth (2.9 MB ≈ 2.3 s at 10 Mbit/s, band part overlapping the count-in).

The mix is about 9 dB louder than before (it was very quiet) with peaks held under -3 dBFS by the bus limiter. The balance between parts was kept close to the old one, drums a little more present.

## Implications

- Ship Salamander piano + FluidR3 band + Virtuosity drums; supersede the synth part of D14 (D22, proposed).
- CC-BY needs a visible credit in the app, not only in the repo.
- Velocity is now expressed by gain plus a low-pass on the piano (soft = darker); real velocity layers would need the Salamander SFZ and more budget.
- Native platforms stay silent until the native audio engine; the same assets will serve it.

## Follow-ups

- In-app credits screen (Salamander CC-BY attribution, FluidR3 MIT, Virtuosity CC0).
- Native audio engine plays the same samples (Android/iOS/desktop are silent today).
- Piano velocity layers (2–4) from the Salamander SFZ if a larger budget is approved.
- Listening-test tool (`tools/listening-test/`) should use the same samples.
- Menu SFX and the metronome click are still oscillators; sampled versions are a separate pass.
