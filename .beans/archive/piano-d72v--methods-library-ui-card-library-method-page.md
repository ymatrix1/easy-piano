---
# piano-d72v
title: 'Methods library UI: card, library, method page'
status: completed
type: task
priority: normal
created_at: 2026-10-22T19:39:33Z
updated_at: 2026-10-23T14:09:54Z
parent: piano-bjig
---

## Context

Blocked by: none. Spec: docs/specs/methods.md, D35 (proposed). Today each method book is a numbered course card in the Learn tab; it will not scale to many methods and books.

## Higher Goal

Optional method repertoire that stays browsable as it grows, without crowding the main path.

## Acceptance Criteria

- [x] `content/methods.json` + course `method` field; lint checks references; `methods` section removed from courses.json
- [x] Learn tab: main path only, plus one Methods card (progress summary)
- [x] Methods library screen: one card per method, level/skill filter
- [x] Method page: description, books as collapsible sections, Continue button, region-locked pieces shown locked with reason
- [x] Method courses get no module number and never lock
- [x] Strings in 5 locales; widget tests; web check with screenshots

## Out of Scope

Region detection itself (piano-7os5), new method content, placement recommendations.

## Summary of Changes

- **Decision D35:** Accepted in `docs/DECISIONS.md`.
- **Content & Lint:**
  - Added `content/methods.json` with Mikrokosmos (Books 1–5), level range, focus skills, and author.
  - Tagged `mikrokosmos-1` through `5` with `"method": "mikrokosmos"` and removed `"methods"` section from `content/courses.json`.
  - Added method titles and descriptions in all 5 content locales (`en`, `de`, `es`, `fr`, `pt-BR`).
  - Added content CLI linting rules in `tools/content-cli/src/main.rs` verifying method references, course assignments, and enums.
- **Flutter UI & Models:**
  - Added `MethodDef` and `CourseDef.method` to `ContentRepo`.
  - Filtered Learn tab main path to exclude method courses, rendering a dedicated `_MethodsCard` at the bottom with total stars and method count.
  - Built `MethodsLibraryPage` with level/skill filter chips, method cards, and total star progress.
  - Built `MethodPage` with collapsible book expansion tiles (first unfinished book open by default), Continue button pointing directly to the next unplayed piece, star ratings per piece, and region-lock handling.
  - Extracted `TaskSheet` into `app/lib/home/task_sheet.dart` for reuse across Learn tab and Method page.
  - Added localizations in 5 locales (`en`, `de`, `es`, `fr`, `pt`).
- **Tests & Quality:**
  - Added unit test in `tools/content-cli` for methods linting.
  - Added Flutter widget test suite in `app/test/methods_ui_test.dart` and model test in `app/test/content_repo_test.dart`.
  - All 107 Rust core tests, 19 content-cli tests, and 81 Flutter tests pass with 0 analyze warnings and clean formatting.
