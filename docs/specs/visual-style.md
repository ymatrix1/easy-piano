# Visual style: game menus

Status: draft (decision [D13](../DECISIONS.md#d13-chunky-game-style-menus-with-an-in-code-widget-kit), proposed). Applies to menus and overlays: home / course map, level info cards, result screen, pause bar. The staff band and keyboard keep the practice palette ([practice-screen.md](practice-screen.md)).

## Direction

Bright, chunky casual-strategy-game look: things feel like physical toys you can press. Inspiration is the genre (bevels, gold, sky, bounce), not any one game. **No third-party assets**: no logos, fonts, characters, icons or screenshots from Clash of Clans, Simply Piano or any other app. All art is drawn in code (`CustomPainter`, gradients, Material icons).

## Tokens (`app/lib/ui/game/game_theme.dart`)

| Token | Value | Use |
|---|---|---|
| `skyTop` / `skyBottom` | `#3FA9F5` / `#9FE0FF` | Home background gradient |
| `grass` / `grassDark` | `#7BD148` / `#4E9A2A` | Ground hills behind the map |
| `gold` / `goldDark` / `goldLight` | `#FFC93C` / `#D98E04` / `#FFE58A` | Primary buttons, stars, coins |
| `green` / `greenDark` | `#6FD13B` / `#3E9418` | Go / continue buttons |
| `blue` / `blueDark` | `#46B3FF` / `#1C74C9` | Secondary buttons |
| `red` / `redDark` | `#FF6B5B` / `#C0392B` | Exit / destructive |
| `wood` / `woodDark` | `#B9773C` / `#7A4520` | Panel frames, plaques |
| `parchment` | `#FFF4D6` | Panel fill |
| `outline` | `#2B1A0E` | Text stroke, button rim |
| `night` / `nightDeep` | `#3B2A7A` / `#1E1442` | Result / pause overlay background |

## Type

- Display text (`GameText`): heavy weight (w900), white fill, 2–4 px dark `outline` stroke, 0–3 px drop shadow. Used for titles, button labels, numbers.
- Body text: platform sans, w600–w700, dark on parchment.
- No bundled third-party display font yet (OFL font pick is a follow-up; see D10).

## Components (`app/lib/ui/game/`)

| Widget | Look | Motion |
|---|---|---|
| `GameButton` | Rounded rect, top-light gradient, darker 6 px "lip" under it, 3 px outline rim, gloss highlight on the top half | Press: lip collapses (face moves down 5 px) and scales to 0.94; release springs back with `Curves.elasticOut` (300 ms) |
| `GameRoundButton` | Same, circular, icon only | Same |
| `GamePanel` | Parchment card in a wood frame, inner shadow, optional ribbon title plaque | Pop-in: scale 0.6 → 1 with `easeOutBack` |
| `GameText` | Outlined display text | — |
| `StarRow` | 3 big stars, partial fill from the left | Each star pops in staggered 180 ms, overshoot + rotate, sparkle burst on fill |
| `CountUp` | Number that ticks from 0 to its value | 700 ms `easeOutCubic` |
| `PopIn` / `SlideIn` | Entrance wrappers | `easeOutBack`, staggered by index |
| `Bob` | Gentle endless up/down float | 2.4 s sine |
| `SkyBackground` | Sky gradient, drifting clouds, rolling hills | Clouds drift slowly (60 s loop) |

## Screens

- **Home / course map.** Sky background with clouds and hills. Top bar: game logo plaque ("Easy Piano" in `GameText` on a wood plaque) and a star counter pill (total stars, count-up). Each course: ribbon header, then a winding path of round level nodes (zig-zag left/right, dotted trail between them). Node colour by kind (lesson blue, song green, boss red, star gate gold); first not-yet-starred node bobs and has a "PLAY" tag; earned stars sit under the node. Nodes pop in staggered on first build.
- **Level info stage** (scene placeholder): `GamePanel` with ribbon title, captions, green CONTINUE `GameButton`, red round close button.
- **Result screen.** Night gradient with light rays. Ribbon title "Completed!" / "Almost there!" pops in, `StarRow`, stat medallions with `CountUp`, then round replay (blue) and next (green, disabled grey when failed) buttons.
- **Pause.** Pause is a `GameRoundButton`. Paused: resume (green), restart (blue), exit (red) round buttons slide into the top bar; tempo selector becomes chunky segmented gold pills.

## Motion rules

- Entrances ≤ 600 ms; staggers 60–180 ms; nothing blocks input longer than 300 ms.
- Respect `MediaQuery.disableAnimations`: entrance and loop animations jump to the end state.
- Menu animations never touch song time (rule 7): they run on their own controllers, outside the practice clock.

## Acceptance

- [x] Tokens and widget kit in `app/lib/ui/game/`
- [x] Home course map, info stage, result screen and pause bar use the kit
- [ ] Bundled OFL display font (follow-up)
- [ ] Sound effects on press / star (follow-up, needs audio engine)
