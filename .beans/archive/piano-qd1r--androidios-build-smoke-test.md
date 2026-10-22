---
# piano-qd1r
title: Android build smoke test
status: completed
type: task
priority: normal
created_at: 2026-10-16T02:59:06Z
updated_at: 2026-10-21T23:37:33Z
parent: piano-bqkw
---


## Context
Split from piano-l3rl (docs/research/web-midi-spike.md). Blocked by: none. User's Android APK crashed on a Samsung S23 Ultra. iOS split to piano-38oj.
## Higher Goal
Close D9/D2 gates.
## Acceptance Criteria
- [x] Result recorded in docs/research/web-midi-spike.md
- [x] APK launches to the home screen on an arm64 phone (S23 Ultra)
- [x] CI builds the arm64 APK and boots the app on an emulator
## Out of Scope
iOS (piano-38oj). Native MIDI and mic input (separate session).
## Summary of Changes
- Root cause: sideloaded APK only had x86_64 libs (emulator build). Documented arm64 build.
- `app/rust/build.rs` links NDK `c++_static` + `c++abi` (Oboe needed `__cxa_pure_virtual`).
- `MainActivity` + `app/rust/src/android.rs` init ndk-context so cpal can open AAudio.
- App label, launcher icon, splash use the brand.
- `integration_test/app_smoke_test.dart`; CI job `android` (APK artifact + emulator smoke, cached).
