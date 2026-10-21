---
# piano-movl
title: 'Practice mode: web generator with verified model download'
status: in-progress
type: task
created_at: 2026-10-21T19:32:15Z
updated_at: 2026-10-21T19:32:15Z
parent: piano-c6v1
---

## Context
D28/D24: the model download is verified by sha256 against the release manifest and cached; inference runs in onnxruntime-web. Blocked by: none (develops against local model files; release melody-model-v1 not published).

## Higher Goal
Endless level-fit practice per node (epic piano-c6v1).

## Acceptance Criteria
- [ ] melody.js grammar masks taught pitches per hand, max leap (semitones), chord size, no ties/fingering
- [ ] app web module loads ORT + model with download progress, caches files, verifies sha256 before use
- [ ] model URL configurable (dart-define), default same origin
- [ ] test for the sha256 check
- [ ] native platforms report not yet available

## Out of Scope
Publishing the release, native runtime.
