---
# piano-5v22
title: Add Windows and Android release assets
status: completed
type: task
priority: normal
created_at: 2026-10-23T20:44:58Z
updated_at: 2026-10-23T20:46:12Z
parent: piano-bqkw
---

Context: Blocked by: none. The tagged release workflow publishes only web builds. The app has a Windows Flutter target and Android APK build, but Android release signing currently uses the debug key.

Higher Goal: Publish versioned Windows and Android install packages alongside each web GitHub Release.

Acceptance Criteria:
- [x] Release workflow builds a Windows desktop package and an Android APK for supported devices.
- [x] Assets are versioned and attached to the same GitHub Release.
- [x] Android signing is documented; the APK is debug-signed for sideloading because no private release key is configured.
- [x] README and architecture docs describe all release assets.
- [x] Workflow validation passes.

Out of Scope: Microsoft Store / Google Play publishing, signing certificates managed outside the repository, and app-store rollout.

Summary of Changes:

## Summary of Changes

Expanded tagged releases to build web, Windows x64, and Android arm64 assets in parallel, then publish them together. Documented artifact names and the debug-signing limitation for Android.
