---
# piano-d72v
title: 'Methods library UI: card, library, method page'
status: todo
type: task
created_at: 2026-10-22T19:39:33Z
updated_at: 2026-10-22T19:39:33Z
parent: piano-bjig
---

## Context

Blocked by: none. Spec: docs/specs/methods.md, D35 (proposed). Today each method book is a numbered course card in the Learn tab; it will not scale to many methods and books.

## Higher Goal

Optional method repertoire that stays browsable as it grows, without crowding the main path.

## Acceptance Criteria

- [ ] `content/methods.json` + course `method` field; lint checks references; `methods` section removed from courses.json
- [ ] Learn tab: main path only, plus one Methods card (progress summary)
- [ ] Methods library screen: one card per method, level/skill filter
- [ ] Method page: description, books as collapsible sections, Continue button, region-locked pieces shown locked with reason
- [ ] Method courses get no module number and never lock
- [ ] Strings in 5 locales; widget tests; web check with screenshots

## Out of Scope

Region detection itself (piano-7os5), new method content, placement recommendations.
