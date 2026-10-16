# Practice screen

Status: draft, implementing. Behaviour and layout are modeled on the reference app, observed in a local screen recording of its Piano Basics and song levels (2026-10-16; recording not committed). Art, colors and icons are our own ([D6](../DECISIONS.md)).

## Layout

| Zone | Content |
|---|---|
| Top bar | Round pause button (left), instruction text ("Play the following notes"), progress pill (right): repeats done / total in wait mode, thin song progress line in play-along |
| Staff area | Vivid violet background; a white band behind the staff; black notation. Staff layout comes from the level's `ui` field: `treble` or `bass` draws a **single staff** (beginner levels), `both` draws the grand staff. It does not depend on which hand plays |
| Finger badges | Plain finger numbers above notes; only the **current** note gets a badge (hand pictogram with the finger highlighted in the reference; ours: rounded badge with the number) |
| Keyboard | Optional. Wide realistic keyboard across the bottom (about 4 octaves), "C" label on middle C, the next key highlighted. Shown by default when the level's `keyboard` is true and the screen is at least 560 px tall; a top-bar button toggles it |

## Wait stages

- The whole exercise is laid out to fit the width (about 3 bars); longer pieces page with the 1 s slide at 72% width.
- Current note **yellow**, its badge **orange**; played notes and badges turn **cyan/teal**; no timing pressure.
- When the last note is played a **green check** appears at the end of the line; the exercise repeats `repeats` times (stage field, default 1) and the pill counts `n / repeats`.
- Before the first try, an optional demo dims the staff and sweeps a light beam across the notes while the app plays them (needs audio; bean piano-k0ht).

## Play-along stages

- Clef stays fixed; notes scroll right to left toward a **cyan play bar just after the clef** (≈ 12% of the width) with a soft glow trail behind it.
- Finger numbers above notes; hit notes turn **cyan**, missed notes **red**.

## Pause

Pause button dims the staff and opens a menu: resume, restart, back to the list, and a tempo selector (60 / 80 / 100%, plus the stage default) in play-along.

## End of stage

"Completed!" title, the piece name, three circular stats (**Notes** hit / total, **Timing** %, **Assists** %), 0–3 stars with half stars, replay and next buttons.

Timing % = `100 × (1 − mean |timing error| / input window)`, clamped to 0–100. Assists % is 100 until hints / slow-down tracking exists.

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
