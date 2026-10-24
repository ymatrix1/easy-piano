---
# piano-l7f7
title: Listen-first demo uses the same piano sound as key presses
status: completed
type: task
created_at: 2026-10-24T18:03:16Z
updated_at: 2026-10-24T18:03:16Z
---

### Context
Pre-listen ("Listen first") demo sounded different from the piano the learner plays. Key presses use velocity 90 on the `live` bus; the demo used velocity 80 on the `piano` bus, which passes the band glue compressor and limiter. Blocked by: none.

### Higher Goal
One piano sound across the practice screen.

### Acceptance Criteria
- [x] Pre-listen notes use the same velocity and bus as learner key presses
- [x] practice_stage_demo_test passes; format and analyze clean

### Out of Scope
- Routing the learner's keys through the mix chain
- Injecting PianoSynth for a routing unit test

### Summary of Changes
- app/lib/practice/practice_stage.dart: demo notes scheduled via _schedulePianoKey (velocity 90, part live)
