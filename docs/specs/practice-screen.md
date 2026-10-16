# Practice screen

Status: draft, implementing. Behaviour and layout are modeled on the reference app, observed in a local screen recording of its Piano Basics and song levels (2026-10-16; recording not committed). Art, colors and icons are our own ([D6](../DECISIONS.md)).

## Layout

| Zone | Content |
|---|---|
| Top bar | Round pause button (left), instruction text ("Play the following notes"), progress pill (right): repeats done / total in wait mode, thin song progress line in play-along |
| Staff area | Vivid violet background; a white band behind the staff; black notation. Staff layout comes from the level's `ui` field: `treble` or `bass` draws a **single staff** (beginner levels), `both` draws the grand staff. It does not depend on which hand plays |
| Finger badges | Plain finger numbers above notes; only the **current** note gets a badge (hand pictogram with the finger highlighted in the reference; ours: rounded badge with the number) |
| Keyboard | Optional. Soft look: small gaps between white keys, rounded fronts, shadows instead of outlines, felt strip on top. Wide realistic keyboard across the bottom (C2–C6, middle C centred), "C" label on middle C, the next key highlighted. Shown by default when the level's `keyboard` is true and the screen is at least 560 px tall; a top-bar button toggles it |

## Wait stages

- The whole exercise is laid out to fit the width (about 3 bars); longer pieces page with the 1 s slide at 72% width.
- Current note **yellow**, its badge **orange**; played notes and badges turn **cyan/teal**; no timing pressure.
- When the last note is played a **green check** appears at the end of the line; the pill counts stages done / stages in the level (the reference has no in-stage repeats; the `repeats` field stays available but unused).
- No hint at first. After 4 s without the right note, a soft white **light beam** fades in over the awaited note (0.2 s) and the target keys light up; one beam per note.
- Wrong keys show a blue splash at the played pitch and are not penalised.
- Each expected note is consumed once; a repeated key press does not count twice (Web MIDI is opened once and duplicate deliveries within 25 ms are dropped).
- Before the first try, an optional demo dims the staff and sweeps a light beam across the notes while the app plays them (needs audio; bean piano-k0ht).

## Play-along stages

- Clef and **play bar stay fixed** just after the clef (≈ 12% of the width); the **notes scroll** right to left (reference code: the notes container moves with song time, the rhythm line never moves). The bar's glow **pulses on every beat**.
- The top progress bar advances with song time.
- Finger numbers above notes; hit notes turn **cyan**, missed notes **red**.

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
