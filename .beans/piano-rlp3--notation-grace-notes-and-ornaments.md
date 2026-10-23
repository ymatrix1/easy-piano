---
# piano-rlp3
title: 'Notation: grace notes and ornaments'
status: todo
type: feature
created_at: 2026-10-23T12:25:39Z
updated_at: 2026-10-23T12:25:39Z
parent: piano-bjig
---

## Context

Blocked by: none. The song format has no grace notes. The converter drops them (Mikrokosmos Nos. 62 and 134: 4 notes lost), and the Soloist course Advanced I (PR #76) works around ornaments. Not covered by piano-boat or piano-h90n.

## Higher Goal

Play the notes the composer wrote.

## Acceptance Criteria

- [ ] Proposed decision: syntax for acciaccatura, appoggiatura, trill, mordent, turn (written out versus marked); effect on bar length and grading
- [ ] core parser, lint, staff drawing (small notehead and slash) and playback; tests
- [ ] Converter keeps them; Mikrokosmos Nos. 62 and 134 re-imported
- [ ] Teaching lesson (scene, drill, song) for grace notes and for trills and mordents

## Out of Scope

Expression marks (piano-boat).
