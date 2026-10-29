---
# piano-uy13
title: 'Custom scores: import UI, drop target, and song library list'
status: completed
type: feature
priority: normal
created_at: 2026-10-24T20:13:41Z
updated_at: 2026-10-25T23:46:43Z
parent: piano-kxi3
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

## Rework after review (PR #116)
- [x] An imported song plays: the core's strict content lint rejected every imported song (license `user-provided`, no source URL), so Practice ended on a blank screen. `Song::validate_playable` waives those two rules for `source: custom`; tests in `core/src/song.rs` and `app/rust/src/api/practice.rs`.
- [x] Every failure shows plain language and a next step, per file, in a game-style results dialog; no raw exception, no stock snackbar (`import_problem.dart`, `import_results_dialog.dart`).
- [x] Empty, oversize (2 MB), corrupt, no-notes, unsupported-music and duplicate files are handled; the picker takes several files.
- [x] Storage: writes are awaited, a refused write rolls back and reports `storageFull`, library capped at 100 scores and 3 million characters, imports and deletes serialised.
- [x] Preview: staff of the first two bars, key, tempo, meter, bars, hands, estimated level, rights notice, working Practice.
- [x] Library page and delete confirmation use the game kit; import button in the header and the empty state; checked at 320, 375 and wide widths.
- [x] Locales: new strings in en, de, es, fr, pt, pt-BR; pt used "arquivo" in three strings, now "ficheiro" (pt-BR keeps "arquivo"); tests per locale.
- [x] Docs: spec 5.6, D41 (still proposed), ROADMAP Phase 3 split; bean re-parented from Phase 2 to Phase 3 (`piano-kxi3`).
- Still not verified: a real OS drop on desktop and web, an Android device run.

## Out of Scope
- Cloud sync across devices

## Summary of Changes
- `app/lib/custom/`: score model and library (`CustomScore`, `CustomScoreController` over `shared_preferences`), drop zone and overlay, preview dialog, library page.
- Entry points: Song library card in PracticeTab, TopBar import button, window drop target (desktop and web). Imported score opens its preview and plays as one play-along stage.
- `app/lib/home/home_page.dart`, `other_tabs.dart`, `content_repo.dart` (`stringsByLocale` getter) wired.
- Strings in English, German, Spanish, French, Portuguese and Portuguese (BR).
- Decision D41 (proposed). Not verified: a real drop on a desktop window and on web.
