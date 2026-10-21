# Backing band samples

| Folder | Instrument | Source | Licence |
|---|---|---|---|
| `bass/` | Electric bass (finger), C1–C4 every 3 semitones | FluidR3_GM via [gleitz/midi-js-soundfonts](https://github.com/gleitz/midi-js-soundfonts) `electric_bass_finger-mp3` | MIT (`LICENSE-midi-js-soundfonts.txt`) |
| `strings/` | String ensemble 1, C3–C6 | same, `string_ensemble_1-mp3` | MIT |
| `choir/` | Voice "oohs", C3–C6 | same, `voice_oohs-mp3` | MIT |
| `drums/` | Kick, snare, closed/open hi-hat, crash | [Virtuosity Drums](https://github.com/sfzinstruments/virtuosity_drums) v0.925 by Versilian Studios and Karoryfer Samples | CC0 1.0 (`LICENSE-virtuosity-drums-CC0.txt`) |

Drum one-shots are our mixdown of four mic positions (kick, snare, overhead,
room at -6 dB) of one hit each: `kick_snon_vl3_rr1`, `snare_center_vl24`,
`hh_closed_vl3_rr1`, `hh_open_vl3_rr1`, `crash_crash_vl2_rr1`, plus round-robin hits `kick_snon_vl3_rr2/rr3` (`kick_2/3`), `snare_center_vl22/vl26` (`snare_2/3`), `hh_closed_vl3_rr2/rr3` (`hihat_closed_2/3`, -5 dB to match) and the soft layer `hh_closed_vl2_rr1` (`hihat_closed_soft`); trimmed with a
fade, +6 dB, 96 kbps stereo MP3 (ffmpeg). The relative level between drums is
the recording's own.

Metronome: `drums/click.mp3` and `drums/click_accent.mp3` are Virtuosity Drums
`snare_crossstick_vl8` and `vl14` (snare mic + overhead at -6 dB), 0.25 s with
a fade, levelled to -12 / -6.7 dBFS peak. Loaded with the piano so the count-in
always has them.
