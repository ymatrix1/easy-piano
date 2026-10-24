---
# piano-j130
title: Automate tagged web releases
status: completed
type: task
priority: normal
created_at: 2026-10-23T20:24:46Z
updated_at: 2026-10-23T20:26:00Z
parent: piano-bqkw
---

Context: Blocked by: none. CI currently builds the Android APK as an expiring artifact and deploys web on main, but there is no tagged application release workflow. The roadmap's first release target is web (D9); mobile store distribution is later.

Higher Goal: Make the web app available as a versioned, downloadable GitHub Release when a version tag is pushed.

Acceptance Criteria:
- [ ] A version tag builds the production web app and attaches a zip artifact to a GitHub Release.
- [ ] The release notes are generated automatically and deployment-to-Pages behavior remains unchanged.
- [ ] Workflow documentation describes how to cut a release and required permissions.
- [x] Workflow YAML and any shell commands are validated.

Out of Scope: Mobile app store distribution; publishing to Cloudflare Pages from a release tag.

Summary of Changes:

## Summary of Changes

Added a tagged web-release workflow that builds Flutter + Rust/Wasm, packages a versioned zip, and publishes generated notes to GitHub Releases. Documented the process in README and architecture docs.
