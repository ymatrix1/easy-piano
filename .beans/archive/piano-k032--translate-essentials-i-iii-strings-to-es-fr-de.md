---
# piano-k032
title: Translate Essentials I-III strings to es, fr, de
status: completed
type: task
created_at: 2026-10-20T21:42:00Z
updated_at: 2026-10-20T21:42:00Z
parent: piano-id7r
---

## Context

Essentials I–III (#24–#26) landed with en and pt-BR content strings only. The multilingual work (#23) added es, fr and de, so `content lint` warned that 104 Essentials keys fell back to English in those locales. Blocked by: none.

## Higher Goal

Every supported language can take the whole main path (Piano Basics + Essentials I–III) without English fallbacks.

## Acceptance Criteria

- [x] `es.json`, `fr.json`, `de.json` contain every key in `en.json` (129/129)
- [x] `cargo run -- lint ../../content` reports no "untranslated string(s)" warnings
- [x] Note naming follows `docs/specs/i18n.md` (es `Do`, fr lower-case `do`, de `H`/`B`, `Fis`)
- [x] Song titles stay as proper names unless the locale has a common traditional title
- [x] All `app_*.arb` files have every `app_en.arb` key (`app_pt_BR.arb` is a regional override over `app_pt.arb`)
- [x] `flutter analyze` and `flutter test` pass

## Out of Scope

- Native-speaker review (welcome via PR, per the i18n spec)
- Translating `songs/*.json` titles (proper names by spec)
- New locales or UI (ARB) string changes

## Summary of Changes

- Added 104 translations each to `content/strings/es.json`, `fr.json`, `de.json`: Essentials node titles, level titles and scene captions. Informal register (tú / tu / du), matching the existing strings.
- Traditional titles where common: es "Estrellita, ¿dónde estás?", "Martinillo", "Al mundo paz"; fr "Ah ! vous dirai-je, maman", "Vive le vent", "Ce n'est qu'un au revoir"; de "Funkel, funkel, kleiner Stern", "Bruder Jakob", "Freue dich, Welt". Others (When the Saints, London Bridge, Amazing Grace, Greensleeves…) unchanged.
- Music terms: corcheas / croches / Achtelnoten, sostenido·bemol·becuadro / dièse·bémol·bécarre / Kreuz·b·Auflösungszeichen, compás de 3/4 / mesure à 3/4 / 3/4-Takt; German uses B for B♭ and H for B natural.
- Key order in each locale file now follows `en.json`.
