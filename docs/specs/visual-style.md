# Visual style: menu skins

Status: draft (decision [D13](../DECISIONS.md#d13-skinnable-game-menus-classic-default-playful-option-with-an-in-code-widget-kit), proposed). Applies to menus and overlays: home / course map, level info cards, result screen, pause bar. The staff band and keyboard keep the practice palette ([practice-screen.md](practice-screen.md)).

## Direction

Menus feel like a polished game (tactile buttons, rewarding motion), but the **default look is grown-up**. A brighter cartoon look is an option, not the default. Skins are chosen in Settings (gear on the home screen) and apply live.

| Skin | For | Look |
|---|---|---|
| `classic` (default) | Teens and adults | Midnight-blue backdrop with a soft spotlight and drifting specks; brass accent; thin 1 px edges; small 3 px button lip; semibold text with a soft shadow, uppercase button labels; dark glass panels; slim brass title plaque; thin dashed trail; smooth `easeOutCubic` motion, no bounce |
| `playful` | Kids | Sky with drifting clouds and hills; wood and gold; 3 px dark outlines; 6 px lip and gloss; heavy outlined text; parchment-in-wood panels; banner ribbons with tails; sandy dotted trail; bouncy `easeOutBack` / elastic motion; light rays on the result screen |

Inspiration is the genre (casual mobile games), not any one game. **No third-party assets**: no logos, fonts, characters, icons or screenshots from Clash of Clans, Simply Piano or any other app. All art is drawn in code (`CustomPainter`, gradients, Material icons).

Later, the audience axis from D12 (`kids` / `teen_adult`) can pick the initial skin during onboarding.

## Tokens (`app/lib/ui/game/game_theme.dart`)

`GameSkin` holds every token; `GameSkin.of(context)` reads the current one (default `classic`). `GameSkinScope` is installed by `MaterialApp.builder`; `skinNotifier` holds the choice in memory until the settings store lands.

| Token | Classic | Playful |
|---|---|---|
| `bgTop` / `bgBottom` | `#0E1726` / `#1B2940` | `#3FA9F5` / `#9FE0FF` |
| `accent` / `accentLight` / `accentDark` | `#D4A84B` / `#F0D38A` / `#8F6A22` | `#FFC93C` / `#FFE58A` / `#D98E04` |
| `outline`, `outlineWidth` | white 20%, 1.2 | `#2B1A0E`, 3 |
| `lip`, `radius` | 3, 12 | 6, 16 |
| `panelFill` / `panelText` | `#182335` / `#E6EAF2` | `#FFF4D6` / `#2B1A0E` |
| `resultTop` / `resultBottom` | `#1B2940` / `#0B121E` | `#3B2A7A` / `#1E1442` |
| Tones (gold, green, blue, red, grey, wood) | muted: `#D4A84B`, `#2FA572`, `#3B6FC4`, `#C9504B`, `#4A5468`, slate `#2B3850` | saturated: `#FFC93C`, `#6FD13B`, `#46B3FF`, `#FF6B5B`, `#B8B8C4`, wood `#B9773C` |

## Components (`app/lib/ui/game/game_widgets.dart`)

| Widget | Behaviour |
|---|---|
| `GameButton`, `GameRoundButton` | Beveled face on a lip. Press: face sinks onto the lip and shrinks (6–8% playful, 3–4% classic); release springs back (elastic in playful). Classic lifts slightly on hover. Disabled: grey tone |
| `GameText` | Outlined heavy text (playful) or semibold with soft shadow (classic) |
| `GamePanel`, `GameRibbon` | Card + title plaque per skin |
| `GameStar`, `StarRow` | Stars appear staggered 220 ms; playful: elastic pop, tilt, sparkles, raised middle star; classic: fade + gentle scale, one light ring |
| `CountUp`, `StarCounter` | Numbers tick up over 700–800 ms |
| `PopIn`, `SlideIn` | Entrances; overshoot only in playful, classic travels half the distance |
| `Bob` | Marks the next level: float (playful) or soft brass glow pulse (classic) |
| `MenuBackground`, `ResultBackground` | Backdrops per skin |

## Screens

- **Home / course map.** Logo plaque, star counter, Settings gear (theme choice + developer spikes). Each course: title plaque, description card, winding trail of round level nodes coloured by kind (lesson blue, song green, boss red, star gate gold); next node is marked (`PLAY` / `NEXT` tag + `Bob`); earned stars under each node; staggered entrance.
- **Level info stage** (scene placeholder): `GamePanel` with title, captions, green CONTINUE, red close.
- **Result screen.** Title plaque (green "Completed!" / red "Almost there!"), `StarRow`, stat medallions with progress rings and `CountUp`, retry (round) and NEXT / LOCKED buttons.
- **Pause.** Pause is a gold round button. Paused: resume (green), restart (blue), exit (red) slide in; tempo choice becomes a row of small buttons, the current one gold.

## Motion rules

- Entrances ≤ 600 ms; staggers 60–220 ms; nothing blocks input longer than 300 ms.
- Respect `MediaQuery.disableAnimations`: entrance and loop animations jump to the end state.
- Menu animations never touch song time (rule 7): they run on their own controllers, outside the practice clock.

## Acceptance

- [x] `GameSkin` tokens with `classic` (default) and `playful` skins, switchable live from Settings
- [x] Widget kit in `app/lib/ui/game/` reads the skin
- [x] Home course map, info stage, result screen and pause bar use the kit
- [ ] Persist the skin choice (needs the settings store)
- [ ] Pick the initial skin from the onboarding audience (D12)
- [ ] Bundled OFL display font (follow-up)
- [ ] Sound effects on press / star (follow-up, needs audio engine)
