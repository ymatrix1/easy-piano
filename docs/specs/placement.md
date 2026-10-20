# Placement: detect the learner's level

Status: draft, not scheduled. Bean: piano-vg8h. Open question: [OQ9](../OPEN-QUESTIONS.md). Until a decision is accepted, every course and node stays open and star gates never lock.

## Goal

People who already play skip what they know. Beginners get a guided start. The app suggests a start node; it never blocks the learner from going elsewhere.

## Signals

| Signal | How | Cost | Reliability |
|---|---|---|---|
| Self-report | Onboarding asks "never played / some / read music / play songs" | None | Low, people misjudge |
| Placement test | 3–6 short pieces, one per rung (C position, both hands, reading, rhythm, accidentals, chords), adaptive: stop at the first clear fail | 2–5 min | High |
| Free-play sniffing | Listen to 30 s of free playing over MIDI/mic: range, both hands, chords, speed, accidentals | Needs analysis | Medium, good as a hint |
| Ongoing evidence | Results from normal play: three stars at first try on a level → offer to skip ahead | None | High over time |

## Proposed flow

1. Onboarding asks experience (self-report). "Never played" → start at Piano Basics 1, no test.
2. Anything else → offer the placement test, skippable.
3. The test uses the rubric in [song-import research](../research/song-import.md) (notes, hands, rhythm values, keys and accidentals per level). Each item is a normal wait or play-along stage graded by the session engine (`core`), so grading and timing stay in Rust.
4. Adaptive: start mid-ladder; pass → harder rung, fail → easier; stop after two decisions at the same boundary.
5. Result: a start node in the course map. The "Continue" card points there. Earlier nodes are shown as "tested out" (no stars), still playable.
6. Ongoing: if a learner earns three stars on the first attempt in several levels in a row, suggest jumping ahead (a "skip test" for the next part).

## Data

- Placement result stored with progress: `placement: {node_id, at, method: self|test|sniff}`.
- Test items are regular song files with license fields, tagged `placement` and a rung index.

## To decide

- Does "tested out" count for gates and XP? Proposed: no XP, gates treat it as passed.
- Kids vs adult profiles (D12): same ladder, different songs.
- Mic users: test items must stay inside mic-detectable material (monophonic or simple chords) until mic polyphony is proven.

## Follow-ups

- piano-vg8h: write the proposed decision, then the test items and UI.
