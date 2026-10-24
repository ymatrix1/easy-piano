---
# piano-7y0r
title: Package Windows release as a portable single EXE
status: completed
type: task
priority: normal
created_at: 2026-10-23T21:54:50Z
updated_at: 2026-10-23T22:00:48Z
parent: piano-bqkw
---

Context: Blocked by: none. Flutter's Windows release bundle contains an executable plus Flutter/Rust DLLs and data files. The tagged release currently publishes the bundle as a ZIP. Enigma Virtual Box can embed the bundle into a portable single-file executable and supports command-line packaging.

Higher Goal: Offer a portable, single-file Windows executable alongside the ordinary ZIP bundle.

Acceptance Criteria:
- [x] Windows release packaging downloads Enigma Virtual Box 11.30 from the official source and verifies its SHA-256 and publisher signature before execution.
- [x] A generated Enigma project embeds the Flutter Release directory in the launcher executable and builds a single-file output; CI checks the artifact exists and is larger than the launcher.
- [x] The tagged release workflow publishes a versioned portable EXE and preserves the ZIP fallback.
- [x] README and architecture docs describe the portable executable and compatibility caveats.
- [x] Workflow YAML and packaging scripts are validated.

Out of Scope: Replacing the ZIP fallback; code signing; Microsoft Store packaging.

Summary of Changes:

- Added a hash-pinned, signature-checked Enigma Virtual Box installer helper and a locked Node generator for the Enigma project file.
- Windows CI and tagged release builds package the Flutter bundle into a portable single-file EXE, retaining the regular ZIP.
- Documented Visual C++ runtime and unsigned executable warning caveats.
