# Practice screen

Status: draft, implementing. Behaviour and layout are modeled on the reference app, observed in a local screen recording of its Piano Basics and song levels (2026-10-16; recording not committed). Art, colors and icons are our own ([D6](../DECISIONS.md)).

## Layout

| Zone | Content |
|---|---|
| Top bar | Round pause button (left), instruction text ("Play the following notes"), progress pill (right): repeats done / total in wait mode, thin song progress line in play-along |
| Staff area | Vivid violet background; a white band behind the staff; black notation. Staff layout comes from the level's `ui` field: `treble` or `bass` draws a **single staff** (beginner levels), `both` draws the grand staff, except that a grand staff with no notes on one staff for the whole stage (e.g. a right-hand stage of a two-hand piece) draws only the other staff. Streamed practice keeps the grand staff, since later bars may fill either |
| Finger badges | Plain finger numbers above notes; only the **current** note gets a badge (hand pictogram with the finger highlighted in the reference; ours: rounded badge with the number) |
| Keyboard | Optional. Soft look: small gaps between white keys, rounded fronts, shadows instead of outlines, felt strip on top. Wide realistic keyboard across the bottom (C2–C6, middle C centred), "C" label on middle C, the next key highlighted. Height is 24% of the screen, 150–260 px. Shown by default when the level's `keyboard` is true and the screen is at least 560 px tall; a top-bar button toggles it |

## Wait stages

- The whole exercise is laid out to fit the width (about 3 bars); longer pieces page like the reference: when the next note passes 60% of the width, a 1 s gentle (sine ease) slide brings it back to the left margin, stopping once the end of the piece is in view.
- Current note **yellow**, its badge **orange**; played notes and badges turn **cyan/teal**; no timing pressure.
- When the last note is played a **green check** appears at the end of the line; the pill counts stages done / stages in the level (the reference has no in-stage repeats; the `repeats` field stays available but unused).
- No hint at first. After 4 s without the right note, a soft white **light beam** fades in over the awaited note (0.2 s) and the target keys light up; one beam per note.
- Wrong keys show a blue splash at the played pitch and are not penalised.
- Each expected note is consumed once; a repeated key press does not count twice (Web MIDI is opened once and duplicate deliveries within 25 ms are dropped).
- **Pre-listen** (stage `pre_listen`, first attempt): the staff dims, the app plays the passage while the beam and highlight walk note by note, input is ignored, and a Skip button ends it. The graded clock starts after the demo.

## Play-along stages

- Clef and **play bar stay fixed**, the bar well right of the clefs (28% of the width, at least 144 px; reference rhythm line ≈ 0.28 of the width); wait-mode page start 3% left of it (at least 120 px); the **notes scroll** right to left (reference code: the notes container moves with song time, the rhythm line never moves). The bar's glow **pulses on every beat**.
- Grand staff system start: brace just left of the system line (line at 1.6 staff spaces), clefs 1 space after the line, notes hidden left of 3.4 spaces past the clef. A single staff has no brace; its frame starts 0.6 space from the edge and the clef 1 space after it.
- Grand staff: one white band per staff from the system line rightwards, exactly covering the staff (top to bottom line), stage colour in the 3-space gap between them; each staff is framed by a rectangle at 2× line width (left at the system line, right at the screen edge), no system line across the gap; clefs may overhang the band (reference look). The brace spans both bands, 1.4 spaces wide, staff colour at 40%. Note colour changes (current, hit, miss) tween linearly over 0.2 s (reference). Stage intro: visible notes rise from one staff-height below with a swingOut(2) overshoot and fade in, staggered k/(2n) s, each ≤ 0.5 s (reference intro). Single staff: same band and frame (from 0.6 space, clef 1 space after), no brace. Passed notes **slide under a cover**: a copy of the background (band, staff lines, clefs, brace, play bar) painted over the notes, opaque up to 1 space before the clefs' right edge and fading linearly to clear at the play bar. Notes left of the bar therefore ghost into the band and vanish under crisp clefs. Wait mode: the cover fades from the left edge to half a notehead before the page start, so the current note is never covered. No fade at the right edge. Mechanic from the reference teardown ([research](../research/simply-piano-teardown.md#staff-note-cover)); our own code.
- The top progress bar advances with song time.
- **Companion:** the app plays the hand not being practised plus the song's `ACC` part through the synth. A metronome toggle in the top bar (play-along only, default on, remembered per device) clicks every beat (a recorded cross-stick, accented on beat 1; [D22](../DECISIONS.md)), with or without a companion; off keeps only the count-in. Toggling mid-song reschedules from the current beat. A count-in of whole bars, at least 2.5 s long, clicks before the start while the first note scrolls in from the right. Pause stops the sound; resume reschedules from the current beat.
- Finger numbers above notes; hit notes turn **cyan**, missed notes **red** (the reference's only per-note feedback).
- **Error feedback** (ours, [D31](../DECISIONS.md)), 0.6 s fades driven by core feedback events: a wrong key flashes red on the on-screen keyboard; a missed note's keys get a red outline; a hit more than 120 ms off shows an amber "Early" / "Late" tag above the staff at the play bar. No staff mark for wrong or missed notes, no error sound.
- **Training** ([exercise engine](exercise-engine.md#training-mode)): a failed section rewinds to its start after a count-in, with a banner (red replay badge, "Try this part again"). The 2nd failure in a row starts slow practice at 75% of the stage tempo: an orange badge pops in (elastic, 0.6 s), its label fades in, the banner is gone by 2.2 s, and the count-in starts after 1.5 s; the top bar shows the slower tempo. Passing practice shows "Now at full speed!" and replays the section at the stage tempo. Menu synth cues: open (intro), win (practice passed), lose (failed).

## Sound

Sampled grand piano (Salamander Grand Piano V3, CC-BY 3.0; `app/assets/piano/`), one sample every 3 semitones C1–C8 with full decay, pitch-shifted in between, soft notes darker (velocity low-pass): Web Audio on web ([D22](../DECISIONS.md)); on Android, iOS and desktop the Rust engine in `audio/` plays the same samples and mix through the platform output ([D30](../DECISIONS.md)). The student's keys sound through it (MIDI controllers often have no speaker). A top-bar toggle mutes it for digital pianos with their own sound; the choice is remembered per device. Pre-listen and companion play even when muted.

## Pause

Pause dims the staff (nothing is drawn over it). In the top bar, resume / restart / back-to-list replace the pause button and instruction text, and in play-along a tempo selector (60 / 80 / 100%, plus the stage default) replaces the progress pill. The layout does not move.

## End of stage

"Completed!" title, the piece name, **Notes** hit / total and, for play-along, **Timing** % and **Assists** %, then 0–3 stars filled continuously, replay and next buttons. Formulas: [exercise engine](exercise-engine.md).

## Palette (ours)

| Token | Value | Use |
|---|---|---|
| `bg` | `#6E2CF2` → `#7B3BFF` | Stage background gradient |
| `band` | `#FFFFFF` | Staff band |
| `ink` | `#16131F` | Notation |
| `current` | `#F57C00` | Current note (dark enough to read on the white band) |
| `keyTarget` | `#FFB400` | Target key on the keyboard |
| `badgeCurrent` | `#FF8A1F` | Current finger badge |
| `done` | `#19C6DE` | Played notes and badges, play bar |
| `miss` | `#FF4D6A` | Missed notes |
| `badge` | `#5B21B6` | Pending finger badges |
