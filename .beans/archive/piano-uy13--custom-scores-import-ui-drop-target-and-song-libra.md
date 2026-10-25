---
# piano-uy13
title: 'Custom scores: import UI, drop target, and song library list'
status: completed
type: feature
priority: normal
created_at: 2026-10-24T20:13:41Z
updated_at: 2026-10-25T23:46:43Z
parent: piano-r9p5
blocked_by:
    - piano-gy3o
---

## Context
Users need an accessible and discoverable UI in the app to drag-and-drop or pick files (MusicXML, MIDI, ABC, LilyPond), organize them in their library, and choose whether to practice with scrolling or study with static pages.

## Higher Goal
Seamless song import UX inspired by sightread.dev and Simply Piano.

## Acceptance Criteria
- [x] File picker and drag-and-drop target in Flutter (file_selector, desktop_drop; drop on desktop and web)
- [x] Entry point in PracticeTab (Song library card)
- [x] Quick-access import button in TopBar
- [x] Library listing showing custom scores with search and delete
- [x] Widget tests for file drop and library interactions (overlay, supported-file filter, library search and delete, preview)

## Out of Scope
- Cloud sync across devices

## Summary of Changes
- `app/lib/custom/`: score model and library (`CustomScore`, `CustomScoreController` over `shared_preferences`), drop zone and overlay, preview dialog, library page.
- Entry points: Song library card in PracticeTab, TopBar import button, window drop target (desktop and web). Imported score opens its preview and plays as one play-along stage.
- `app/lib/home/home_page.dart`, `other_tabs.dart`, `content_repo.dart` (`stringsByLocale` getter) wired.
- Strings in English, German, Spanish, French, Portuguese and Portuguese (BR).
- Decision D41 (proposed). Not verified: a real drop on a desktop window and on web.
