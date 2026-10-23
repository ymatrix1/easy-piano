---
# piano-m6oc
title: 'Two-button modal: Train (continuous into Play Along) and Play Along directly'
status: completed
type: task
priority: normal
created_at: 2026-10-23T13:35:24Z
updated_at: 2026-10-23T14:12:31Z
parent: piano-eeut
---

## Context

Blocked by: none. Levels in courses and methods (such as Mikrokosmos and repertoire songs) currently only show a single 'PLAY' button in the task sheet modal. Players who already know the piece are forced through note-by-note wait stages every time, while players wanting to practice cannot distinguish between note-by-note training and full play-along.

## Higher Goal

Allow learners and players to choose between practicing (Train: note-by-note wait mode, hands separate, flowing continuously into Play Along) and performing (Play Along: jumps directly to the full tempo play-along stage).

## Acceptance Criteria

- [x] When a level contains both wait stages and play_along stages, the task sheet modal renders two action buttons: 'PRACTICE' (or 'TRAIN') and 'PLAY ALONG'.
- [x] If 'TRAIN' / 'PRACTICE' is selected, it starts at the first stage (stage 0), runs through training stages, and flows directly into the play-along stage without returning to the menu.
- [x] If 'PLAY ALONG' is selected, it starts directly at the play_along stage.
- [x] Levels with only one mode/stage continue to display a single appropriate primary button.
- [x] Localized labels for practice / play along buttons across supported locales (en, pt-BR, de, es, fr).
- [x] Tests in app/test pass.

## Summary of Changes

- Updated \_TaskSheet\ in \pp/lib/home/learn_tab.dart\ to detect if a target level has both training (\wait\) and performance (\play_along\) stages:
  - If both exist, renders two side-by-side buttons: **PRACTICE** (purple \GameTone.purple\ with dumbbell icon) and **PLAY ALONG** (gold with play icon).
  - Tapping **PRACTICE** launches stage 0 (note-by-note training) and naturally flows through subsequent training stages directly into play-along.
  - Tapping **PLAY ALONG** launches directly into the target level's \play_along\ stage index.
  - Tapping individual level rows passes stage 0 as well.
  - Levels with only a single mode continue to show a single full-width **PLAY** button.
- Updated \LevelPage\ in \pp/lib/practice/level_page.dart\ and \_playLevel\ in \pp/lib/home/home_page.dart\ to accept an optional \initialStageIndex\ (defaults to 0).
- Updated \docs/specs/visual-style.md\ to document the two-button task sheet behavior.
- Updated widget test in \pp/test/home_page_test.dart\ verifying both buttons appear and are interactable.

## Out of Scope

- Redesigning the entire task sheet or pause menu.
