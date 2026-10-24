---
# piano-byw0
title: Fix pause and resume during pre-listen demo mode
status: completed
type: bug
priority: normal
created_at: 2026-10-24T01:49:30Z
updated_at: 2026-10-24T01:53:41Z
---

### Context\nIn pre-listen (listenFirst demo) mode, clicking pause stops the audio synth via stopAll(), but the ticker continues advancing _demoIndex, beam, and page because tick() only early returns on _paused, but wait... wait!\n\n### Acceptance Criteria\n- [x] Pausing in pre-listen mode halts beam and song progress\n- [x] Resuming in pre-listen mode continues from where it was paused\n- [x] Audio reschedules remaining notes and plays seamlessly\n\n### Out of Scope\n- Redesigning the pre-listen UX\n

## Summary of Changes
- Shift `_demoStartMs` on `_resume()` by the paused duration so the beam and note progression pause and resume at the exact point they stopped.
- Reschedule remaining demo notes starting from the current beat on `_resume()` via `_scheduleDemo(fromBeat: currentBeat)`.
- Added widget test verifying pause halts demo progression and resume continues until completion.
