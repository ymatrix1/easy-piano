---
# piano-16vk
title: Implement two voices per hand (RH2/LH2)
status: completed
type: task
priority: normal
created_at: 2026-10-22T19:28:39Z
updated_at: 2026-10-22T20:11:18Z
parent: piano-bjig
---



## Context

Blocked by: none. Spec: docs/specs/content-format.md#two-voices-per-hand-rh2-lh2, D34 (proposed). 69 of 147 Mikrokosmos pieces need it.

## Higher Goal

Play real piano repertoire where one hand holds a line while it plays another.

## Acceptance Criteria

- [x] core: `RH2`/`LH2` and `s:` spacer parse; lint rules (voice sums, voice 2 needs voice 1, same-pitch overlap error); `TimedNote.voice`; tests
- [x] Grading and wait mode treat both voices of a hand as one target stream; tests
- [x] Staff: stem directions, voice-2 rest offset, spacers hidden, unison noteheads; widget/golden test
- [x] Difficulty feature `two_voice_bars_per_bar`; rubric flag `two_voices`
- [x] melody-model converter reads/writes two voices; Mikrokosmos importer accepts them; tests
- [x] Schema and spec status updated to implemented

## Out of Scope

Three or more voices, cross-staff, meter/key changes, tuplets, importing new pieces (piano-s1iz).

## Summary of Changes

- **Core (`core`)**:
  - Implemented `Event::Spacer { dur: Dur }` for spacer syntax `s:<dur>`.
  - Added `RH2` and `LH2` support in `Song` and `HANDS` validation. Enforced voice 2 requires voice 1 in the same bar, and disallowed overlapping sounding instances of the same pitch across voices with different onsets.
  - Added `voice: u8` to `TimedNote`.
  - In `core/src/session.rs`, merged voices per hand into target streams:
    - Target stem directions: `stem_downs` and `two_stems` (for unison noteheads with stems in both directions).
    - Unison notes at the same onset are combined into a single target and single notehead.
    - Wait mode and play-along companion routing seamlessly handle multi-voice hands.
  - Added `two_voice_bars_per_bar` difficulty feature in `core/src/difficulty.rs`.
  - Added `two_voices` boolean rubric flag in `core/src/rubric.rs` to validate curriculum prerequisites.
- **Flutter & Staff UI (`app`)**:
  - Extended flutter_rust_bridge TargetView with `stemDowns` and `twoStems`.
  - Updated `StaffNote` and `StaffPainter` to support:
    - Separate stem directions per note based on voice/engine target.
    - Two stems on unison noteheads sharing the same pitch and onset.
    - Hidden spacers (`isSpacer`).
    - Offset voice-2 rests (`+2 * space` for RH2, `-2 * space` for LH2).
  - Added comprehensive widget test in `app/test/staff_painter_test.dart`.
- **Content & Schema (`content`, `tools/content-cli`)**:
  - Added `RH2` and `LH2` to `content/schema/song.schema.json`.
  - Verified content linter passes across all content.
- **Melody Model (`tools/melody-model`)**:
  - Added spacer `s:<dur>` token parsing and formatting in `notation.py`.
  - Updated MusicXML converter `convert.py` to support up to 2 voices per part using `m21.stream.Voice` and `hideObjectOnPrint` spacers.
  - Updated Mikrokosmos validator in `mikrokosmos.py` to allow pieces with up to two voices per hand.
- **Docs & Specs (`docs/`)**:
  - Updated `docs/specs/content-format.md` status to implemented.
