---
# piano-tpud
title: 'Mikrokosmos: add the fingering and dynamic letters the dataset lacks'
status: todo
type: task
created_at: 2026-10-23T12:25:38Z
updated_at: 2026-10-23T12:25:38Z
parent: piano-bjig
---

## Context

Blocked by: piano-boat for the dynamic letters (needs the notation). The dataset XML has no fingering and no dynamic letters (p, f), but the printed pages have both (No. 56: f, fingering 5 and 1; No. 31: f, 2 and 4). Fingering is part of the lesson for beginners.

## Higher Goal

Finger hints on every Mikrokosmos piece, as in the Essentials courses.

## Acceptance Criteria

- [ ] User decides the source: our own fingering (preferred, original work) versus transcribing Bartók's printed fingering and dynamics (composer's own marks, protected in the US until 2036)
- [ ] Fingering added to the imported pieces as a documented patch (importer or hand-made overlay), lint checks finger counts
- [ ] Dynamic letters added once piano-boat lands

## Out of Scope

Hairpins, accents, slurs and pedal the XML already carries (piano-boat).
