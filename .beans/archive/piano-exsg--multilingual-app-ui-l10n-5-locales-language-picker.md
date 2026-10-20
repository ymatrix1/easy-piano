---
# piano-exsg
title: 'Multilingual app: UI l10n, 5 locales, language picker'
status: completed
type: feature
priority: normal
created_at: 2026-10-16T19:25:13Z
updated_at: 2026-10-16T19:36:51Z
---

## Context
UI strings are hard-coded English in app/lib; content strings only exist for en and pt-BR and the locale is picked once at startup. Blocked by: none.

## Higher Goal
Learners use the app in their own language (PRD: global open-source course).

## Acceptance Criteria
- [x] Every user-facing string in app/lib comes from gen-l10n ARB files (dev spike pages excepted)
- [x] Locales en, pt-BR, es, fr, de for UI and content strings
- [x] Language picker in Profile; default from device locale; remembered per device
- [x] Content strings resolve per locale with English fallback; content lint warns on missing keys
- [x] Test that every locale has every key (ARB and content)
- [x] Spec docs/specs/i18n.md incl. note naming per locale; proposed decision in DECISIONS.md
- [x] flutter analyze, flutter test, cargo test, content lint pass; web build switches language live

## Out of Scope
RTL languages, pluralization beyond ICU basics, translated song titles in song files, solfege on the staff.

## Summary of Changes
- UI strings moved to gen-l10n ARB files (`app/lib/l10n/app_{en,pt,pt_BR,es,fr,de}.arb`), with `flutter_localizations`/`intl`.
- `AppLanguage`/`AppLocale` (`app/lib/l10n/app_locale.dart`): device-locale default, picker in Profile, choice stored with `shared_preferences`, live switch keeping state.
- `ContentRepo` holds all `content/strings/*.json`; resolves active tag → base language → English. New `es.json`, `fr.json`, `de.json`.
- Keyboard middle-C label per locale (C / Dó / Do).
- content-cli warns on untranslated/stale locale keys (errors on non-text values); unit test added.
- `test/l10n_test.dart`: ARB key parity, language coverage, fallback, live switch widget test.
- Docs: `docs/specs/i18n.md` (incl. note naming), D16 (proposed), ROADMAP/visual-style/content-format updated.
