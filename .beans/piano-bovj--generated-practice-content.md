---
# piano-bovj
title: Generated practice content
status: in-progress
type: epic
tags:
    - melody-gen
created_at: 2026-10-20T22:00:31Z
updated_at: 2026-10-20T22:00:31Z
---

## Context
Essentials I-III ship 54 levels; the reference course size is about E1 ~50, E2 ~41, E3 ~55 levels. Hand-writing every practice tune does not scale. Plan agreed with the user: generate original or public-domain-variation practice tunes that only use what the learner was taught, checked by a rubric and reviewed by a human. Phases: A foundations (skill specs, taught-set CLI, rubric, provenance, decision), B `compose-song` agent skill, C spike comparing methods (rules random walk, PD variations, LLM via the skill, Magenta.js, hand-written control) with a blind listening test, D production per course.

Sibling sessions work on tasks tagged `melody-gen` (similarity check against known melodies, listening-test page, Magenta.js feasibility); they will be linked to this epic as children.

Related: piano-bjig (Phase 4 content scale).
Blocked by: none

## Higher Goal
Reach reference course size with clean-room, CC0 practice material that teaches one new skill per node.

## Acceptance Criteria
- [ ] Phase A: skill specs, `content specs`, rubric in core, `generator` provenance, decision
- [ ] Phase B: `compose-song` skill
- [ ] Phase C: method spike with blind listening test
- [ ] Phase D: E1/E2/E3 reach target level counts

## Out of Scope
Generating content inside the app; copying any Simply Piano material.
