---
# piano-7os5
title: 'App: hide songs restricted in the learner''s region'
status: todo
type: task
created_at: 2026-10-22T19:09:54Z
updated_at: 2026-10-22T19:09:54Z
parent: piano-bjig
---

## Context

Blocked by: none. Mikrokosmos songs carry `restricted_in: [{region: US, until: 2036-01-01}]` (D33, docs/research/mikrokosmos-import.md); the app ignores the field.

## Higher Goal

Ship protected-in-some-regions repertoire without offering it where it is still protected.

## Acceptance Criteria

- [ ] Region source decided (device locale, store country or build flavour) and recorded
- [ ] Songs, levels and nodes restricted in the learner's region are hidden or locked, with a test
- [ ] Web deploy strategy for restricted content documented

## Out of Scope

Legal review.
