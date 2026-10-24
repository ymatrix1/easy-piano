# Testing

- **Every code change ships tests in the same PR.** New or changed behaviour (Dart, Rust, Kotlin, Python, tools) gets a test that fails without the change. Docs-only and generated-file changes are exempt.
- Platform code that can't run in CI (device APIs) still gets its logic tested: put parsing, mapping and state in pure functions or classes and unit-test those; test the Dart side of a platform channel with a mock channel handler. What only a device can show is listed in the PR as "not verified", never skipped silently.
- A bug fix starts with a test that reproduces the bug.
- No `skip`, `@Ignore` or deleted tests to get green. Flaky tests are fixed or removed with a bean, not retried.
- CI runs every suite listed in AGENTS.md "Checks before pushing" and fails the PR on any failure. Run the same commands before pushing.
- The PR description's Acceptance Criteria name the tests that cover each item.
- Coverage numbers are reported, not gated, until a threshold is agreed (bean piano-kwba).
- **Enforced in CI by `tools/check_tests.py`** (job "Every source file has a unit test"). Per language, a source file is covered when:
  - Rust (`*.rs` under `src/`): the same file has a `#[test]`. Declaration-only files (`lib.rs`: modules, re-exports, cfg attributes) are exempt.
  - Python (`tools/**/*.py`): a test file (`tests/` or `test_*.py`) imports the module.
  - Dart (`app/lib/**/*.dart`): a file under `app/test/` imports it by path.
  - Kotlin (`app/android/app/src/main/**/*.kt`): a file under `src/test/` names the class.
  - Generated files are exempt (`frb_generated*`, `*.g.dart`, `l10n/`, `src/rust/` in Dart, files marked `GENERATED` / `DO NOT EDIT` in the first lines).
- **Ratchet:** existing gaps are listed in `tools/test-baseline.txt`. The check fails on a new untested file, and on a baseline entry that is now covered or removed (delete the line). The list may only shrink. Regenerate with `python tools/check_tests.py --update-baseline` only to remove lines; never to hide a new file.
- The check tests presence, not quality. Quality stays with review and the rules above.
