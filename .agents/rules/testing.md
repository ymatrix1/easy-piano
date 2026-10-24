# Testing

- **Every code change ships tests in the same PR.** New or changed behaviour (Dart, Rust, Kotlin, Python, tools) gets a test that fails without the change. Docs-only and generated-file changes are exempt.
- Platform code that can't run in CI (device APIs) still gets its logic tested: put parsing, mapping and state in pure functions or classes and unit-test those; test the Dart side of a platform channel with a mock channel handler. What only a device can show is listed in the PR as "not verified", never skipped silently.
- A bug fix starts with a test that reproduces the bug.
- No `skip`, `@Ignore` or deleted tests to get green. Flaky tests are fixed or removed with a bean, not retried.
- CI runs every suite listed in AGENTS.md "Checks before pushing" and fails the PR on any failure. Run the same commands before pushing.
- The PR description's Acceptance Criteria name the tests that cover each item.
- Coverage numbers are reported, not gated, until a threshold is agreed (bean piano-kwba).
