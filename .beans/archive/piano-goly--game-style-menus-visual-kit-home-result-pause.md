---
# piano-goly
title: 'Game-style menus: visual kit, home, result, pause'
status: completed
type: task
priority: normal
created_at: 2026-10-16T14:50:17Z
updated_at: 2026-10-16T15:02:13Z
parent: piano-eeut
---

## Context
Menus look like stock Material. User wants them beautiful like a game with animations (Clash-of-Clans-like art direction, original style only). Blocked by: none.

## Higher Goal
Motivating, playful first impression for the first playable (Phase 1).

## Acceptance Criteria
- [x] docs/specs/visual-style.md and proposed decision in docs/DECISIONS.md
- [x] Shared theme + widget kit (beveled buttons, outlined title text, panels, star burst, count-up)
- [x] Home course map, result screen, pause bar and info stage use the kit with entrance/press animations
- [x] flutter analyze clean, flutter test passes, web build screenshots

## Out of Scope
Rive mascot, sound effects, real progress store, practice staff colours.

## Summary of Changes
- docs/specs/visual-style.md + D13 (proposed).
- app/lib/ui/game/: GameColors/GameTone tokens; GameButton, GameRoundButton (press squash + elastic release), GameText (outlined), GamePanel, GameRibbon, GameStar/StarRow (staggered pop + sparkles), CountUp, StarCounter, PopIn/SlideIn/Bob, SkyBackground (drifting clouds, hills), RaysBackground.
- Home: sky course map with winding trail, bobbing next node, star counter. Info stage: wood panel. Result: rays, ribbon, star row, count-up medallions. Pause bar: chunky round buttons, gold tempo pills.
- test/game_widgets_test.dart.
- Follow-up (user feedback "too childish"): added `GameSkin` with `classic` (default, grown-up) and `playful` skins, switchable from the home Settings gear; all kit widgets and screens read the skin. Spec and D13 updated.
- Follow-up 2 (user: "polished like Fortnite, one theme, main menu with nav bar, modules → submodules → tasks with outer and inner trails, collapsible"): replaced skins with one arena-style theme; tabbed shell (Learn, Practice, Profile); Learn with continue card, sections, outer module trail, collapsible inner submodule trail and task sheet; `sections` + planned modules in content and linter; spec, D13 and content-format updated; home_page widget test.
