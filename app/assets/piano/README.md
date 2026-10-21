# Piano samples

**Salamander Grand Piano V3** by Alexander Holm, licensed
[CC-BY 3.0](https://creativecommons.org/licenses/by/3.0/). MP3 renders from
[Tonejs/audio](https://github.com/Tonejs/audio/tree/master/salamander)
(`salamander/`), one velocity layer, full natural decay (up to 16 s).
Files `Ds*`/`Fs*` renamed `Eb*`/`Gb*`; audio unchanged.

Attribution required with every copy of the app: "Salamander Grand Piano
V3 by Alexander Holm, CC-BY 3.0". An in-app credits screen is tracked as a
bean; until then this file and `docs/research/instrument-samples.md` carry it.

One sample every 3 semitones from C1 to C8; the synth pitch-shifts the nearest
sample for the notes in between and darkens soft notes with a low-pass filter
(`app/lib/audio/`). Research: `docs/research/instrument-samples.md`.
