---
# piano-hyle
title: 'Spike: flutter_rust_bridge wasm on web (D2)'
status: completed
type: task
priority: normal
created_at: 2026-10-16T02:59:06Z
updated_at: 2026-10-16T03:11:38Z
parent: piano-bqkw
---

## Context
Split from piano-l3rl (docs/research/web-midi-spike.md). Blocked by: none.
## Higher Goal
Close D9/D2 gates.
## Acceptance Criteria
- [x] Result recorded in docs/research/web-midi-spike.md
## Out of Scope
Production code.

## Summary of Changes

- New pure crate `core/` (`easy_piano_core`) with pitch parsing + 5 tests.
- flutter_rust_bridge integrated: bridge crate `app/rust`, generated Dart in `app/lib/src/rust`, integration test `app/integration_test/simple_test.dart`.
- `tools/serve_web.py` dev server with COOP/COEP headers.
- Verified in browser: Rust wasm (92 KB) loads, sync calls work, page cross-origin isolated. Results in `docs/research/web-midi-spike.md`.
