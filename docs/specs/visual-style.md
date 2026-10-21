# Visual style and main menu

Status: draft (decision [D13](../DECISIONS.md#d13-one-polished-arena-style-theme-main-menu-with-nav-bar-and-two-level-course-trail), proposed). Applies to the main menu (top bar, tabs, nav bar), level info cards, result screen and pause bar. The staff band and keyboard keep the practice palette ([practice-screen.md](practice-screen.md)).

## Direction

One theme, polished like a modern battle-arena game menu: deep night-violet backdrop with a big glow and light beams, chamfered (cut-corner) cards and buttons, heavy uppercase display type, signal-yellow calls to action, electric-cyan accents, gold stars. Motion is quick and crisp (entrances 260–460 ms, light overshoot, press-sink on every tappable surface, glow pulse on the next thing to do).

Inspiration is the genre, not any one game. **No third-party assets**: no logos, fonts, characters, icons or screenshots from Fortnite, Clash of Clans, Simply Piano or any other app. All art is drawn in code (`ShapeDecoration`, gradients, `CustomPainter`, Material icons).

## Type

- Display (`GameText`, kickers, nav labels): **Audiowide** (SIL OFL 1.1), bundled at `app/assets/fonts/audiowide/` with its `OFL.txt`; uppercase, rendered at 0.9× size because it runs wide; caps nudged up 7% of the size to centre optically (the font reserves accent room above capitals).
- Body: platform sans, w500–w800.

## Content hierarchy

Validated against the reference app's structure (local teardown, structure only): **section → course box → journey nodes (each with a display name and several levels) → stages**. The reference has no named groups inside a journey; grouping above courses is by section (touch, basic, then main split into two tracks).

| Ours | Reference | Content file | UI |
|---|---|---|---|
| Section | `touchSection`, `basicSection`, `mainSection` tracks | `courses.json` `sections[]` (`id`, `title`) | Section header on the Learn tab |
| Module | Course box | `courses.json` `courses[]` (`section`, `status`) | Card on the **outer trail** |
| Submodule | Journey node (`displayName`, `levels`) | `journey.json` `nodes[]` | Row on the module's **inner trail** |
| Task | Level | `levels/*.json` | Row in the task sheet |

Modules with `status: "planned"` (Essentials I–III for now) are listed locked ("Coming soon") with no journey.

## Main menu

- **Top bar:** yellow chamfered logo tile + "EASY PIANO", star counter pill (total stars).
- **Nav bar** (bottom, dark glass): **Learn**, **Practice**, **Profile**. Active tab is a yellow chamfered tile with a glow; tabs cross-fade.
- **Learn tab**
  - **Continue card:** big violet-blue gradient card with the next submodule's name, its module, and a pulsing yellow PLAY that starts the first unplayed task.
  - Per section: header (yellow tick + title + fading rule), then the **outer trail**: numbered chamfered markers joined by a vertical rail (done = green check, current = yellow + glow, open = violet, planned = grey lock), each next to its module card.
  - **Module card:** gradient by position (blue, purple, green; grey when planned), "MODULE n" kicker, title, description, star progress bar `earned / nodes × 3`, chevron. Tap toggles the **inner trail** (animated expand/collapse; the current module starts open).
  - **Inner trail:** dark glass panel; one row per submodule with a chamfered node on a thin rail (done = green check, next = yellow + glow + PLAY button, others = kind icon), "KIND · n TASKS" kicker, numbered title, three stars.
  - **Task sheet:** bottom sheet panel with module kicker, submodule title, task rows (number, title, stars; next one outlined yellow) and a PLAY button.
- **Practice tab:** grid of mode cards (Free play — own screen: keyboard, held-note names, octave shift, glissando, MIDI status, sound toggle; Sight reading, Rhythm drills, Song library marked SOON).
- **Profile tab:** stat tiles (stars, tasks, modules) and developer tools (MIDI and staff spikes).

Progress rules (in memory until the progress store lands): submodule stars = lowest stars of its tasks; module stars = sum of its submodules; "next" = first submodule with 0 stars in the first unfinished module.

## Tokens (`app/lib/ui/game/game_theme.dart`)

| Token | Value | Use |
|---|---|---|
| `bgDeep` / `bgMid` / `bgGlow` | `#080726` / `#15104F` / `#4422C9` | Backdrop gradient and glow |
| `panel` / `panelHi` / `panelEdge` | `#1A1458` / `#261D78` / `#4A3CC0` | Glass panels and borders |
| `yellow` / `yellowDark` | `#FFD21F` / `#E09A00` | Primary CTA, active tab, current marker |
| `cyan` | `#2EE6FF` | Kickers, beams, accents |
| `gold` / `goldLight` / `goldDark` | `#FFC83A` / `#FFEA9A` / `#B86E00` | Stars |
| `success` / `danger` | `#3CE07A` / `#FF4D6D` | Done, exit |
| `GameTone` | gold, green, blue, purple, red, grey, wood (dark glass) | Top/bottom gradient + label colour |
| `chamfer(cut)` | Top-right and bottom-left corners cut at 45° | Every card, button, marker |

## Components (`app/lib/ui/game/game_widgets.dart`)

| Widget | Behaviour |
|---|---|
| `Pressable` | Shared feedback: hover lifts (2–5 px, smooth), brightens and ticks; press sinks and shrinks with a springy release; click fires a spark burst at the pointer and a sound; disabled surfaces buzz |
| `GameButton` | Chamfered CTA with dark base edge, gloss band, uppercase label |
| `GameRoundButton` | Square chamfered icon button (pause, retry, close) |
| `GameText` | Heavy uppercase display text with hard drop shadow |
| `GamePanel`, `GameRibbon` | Glass panel; skewed title banner |
| `GameProgressBar` | Rounded bar with glow, animates to its value |
| `GameStar`, `StarRow` | Rounded flat gold star (Material `star_rounded`; glow at ≥ 28 px; empty = dark socket), filled from the left; staggered pop with flash ring, glint and a bell chime per star |
| `ShineSweep` | Diagonal shine crossing a surface every few seconds (CTA buttons, continue card) |
| `CountUp`, `StarCounter` | Animated numbers; currency pill |
| `PopIn`, `SlideIn`, `Bob` | Entrances; glow pulse |
| `MenuBackground`, `ResultBackground` | Arena backdrop (beams + rising specks); with turning rays |

## Interaction and motion

| Surface | Hover | Click | Idle / state |
|---|---|---|---|
| Yellow CTA | lift 3 px, glow | confirm chime, burst | shine sweep, glow pulse (continue card) |
| Module card | lift 3 px, brighten | open / close whoosh, burst in card colour | chevron rotates; inner trail rows slide in staggered |
| Submodule row | colour wash, node grows 12%, chevron slides and turns yellow (layout never moves, so the rail stays continuous) | tap, cyan burst | next node pulses |
| Nav item | lift 2 px | tab blip | active icon pops (elastic) |
| Locked module / mode | — | low buzz | — |
| Outer rail | — | — | light pulses flow down the done/current part |
| Star counter | — | — | pulses when the total changes |
| Result | — | — | stars chime in sequence; win arpeggio or lose motif |

## Sound

`app/lib/ui/game/sfx.dart`: musical cues (tap, tab, confirm, locked, stars, win, lose) are short phrases on the app's sampled piano (Salamander, [D22](../DECISIONS.md)) through their own `sfx` mix bus; hover, open and close are filtered-noise ticks and whooshes. Until the piano samples decode, a small oscillator synth stands in. Web uses Web Audio (`sfx_web.dart`); other platforms are silent until the native audio engine lands (`sfx_stub.dart`). Kinds: hover, tap, confirm, open, close, tab, locked, star ×3, win, lose. Browsers start audio only after a user gesture, so hovers before the first click are silent. Profile → Settings → Sound effects mutes them (in memory). Menu sounds never touch the practice audio clock (rule 7).

## Motion rules

- Entrances ≤ 460 ms; staggers 60–220 ms; nothing blocks input longer than 300 ms.
- Respect `MediaQuery.disableAnimations`: entrance and loop animations jump to the end state.
- Menu animations never touch song time (rule 7): they run on their own controllers, outside the practice clock.

## Acceptance

- [x] One theme; tokens and widget kit in `app/lib/ui/game/`
- [x] Main menu: top bar, nav bar (Learn, Practice, Profile)
- [x] Learn: continue card, sections, outer module trail, collapsible inner submodule trail, task sheet
- [x] Content: `sections` and planned modules in `courses.json`, linted
- [x] Info stage, result screen and pause bar use the kit
- [x] Bundled OFL display font (Audiowide)
- [x] Hover / click / idle animations and menu sounds (sampled piano cues) with a mute setting
- [ ] Practice screen palette aligned with the menu (practice-screen spec)
- [ ] Practice modes beyond free play; persisted progress (settings/progress store)
- [x] Localised UI strings (gen-l10n, [i18n spec](i18n.md))
- [ ] Menu sounds on native platforms (needs the native audio engine)
