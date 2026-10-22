---
# piano-movl
title: 'Practice mode: web generator with verified model download'
status: completed
type: task
priority: normal
created_at: 2026-10-21T19:32:15Z
updated_at: 2026-10-21T20:23:29Z
parent: piano-c6v1
---


## Context
D28/D24: the model download is verified by sha256 against the release manifest and cached; inference runs in onnxruntime-web. Blocked by: none (develops against local model files; release melody-model-v1 not published).

## Higher Goal
Endless level-fit practice per node (epic piano-c6v1).

## Acceptance Criteria
- [x] melody.js grammar masks taught pitches per hand, max leap (semitones), chord size, no ties/fingering
- [x] app web module loads ORT + model with download progress, caches files, verifies sha256 before use
- [x] model URL configurable (dart-define), default same origin
- [x] test for the sha256 check
- [x] native platforms report not yet available

## Out of Scope
Publishing the release, native runtime.

## Summary of Changes

melody.js Grammar takes an optional taught-set mask (spellings per hand, max leap, polyphony, rest values, no ties/fingering; dead ends drop one candidate). ModelStore verifies sha256 for cached and fresh files; web runtime app/web/melody/practice.js; MELODY_MODEL_URL dart-define; stub generator on native. Tests in test_web.py and practice_mode_test.dart.
