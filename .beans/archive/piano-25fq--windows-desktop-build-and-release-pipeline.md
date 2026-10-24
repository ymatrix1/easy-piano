---
# piano-25fq
title: Windows desktop build and release pipeline
status: completed
type: task
priority: normal
created_at: 2026-10-22T00:11:58Z
updated_at: 2026-10-22T00:22:05Z
parent: piano-v8sj
---

Context: Blocked by: none. Easy Piano uses Flutter with a Rust audio bridge, but Windows desktop builds were not covered by CI or release automation. Built on the platform support in PR #68.
Higher Goal: Make Windows desktop builds repeatable and publishable alongside web and Android.
Acceptance Criteria:
- [x] Windows release build is configured in GitHub Actions for pull requests and pushes to main; the release build also succeeds locally.
- [x] CI validates the executable, Rust bridge DLL and Flutter assets, then uploads a portable Windows ZIP artifact.
- [x] Version tags publish the Windows ZIP as a GitHub Release asset.
- [x] Architecture docs describe Windows prerequisites, build steps, artifact contents and release trigger.
Out of Scope: MSIX installer signing, auto-updates, Windows MIDI/microphone feature parity, and macOS/Linux desktop packaging.
Summary of Changes:
- Added a Windows x64 Flutter release build and validated portable ZIP packaging in GitHub Actions.
- Added GitHub Releases publishing on v-prefixed tags.
- Documented local Windows build setup, distribution requirements and release behavior.
- Verified the local Windows release build, package contents, workflow YAML and whitespace checks.
