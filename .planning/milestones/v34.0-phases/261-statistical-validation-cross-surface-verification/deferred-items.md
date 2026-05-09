# Phase 261 Deferred Items

Pre-existing issues discovered during execution but out-of-scope for the current plans.

---

## Pre-existing: Mocha file-unloader ESM bug — non-zero exit on clean test runs

**Discovered during:** Plan 261-03 Task 1 verification.

**Symptom:** `npx hardhat test <single-test-file>.test.js` reports test results
correctly (e.g., "3 passing, 1 pending, 0 failing") but exits with code 1 due to
an `Error: Cannot find module '<path>'` raised inside Mocha's `file-unloader.js`
during disposal. Reproduces on existing test files (e.g.,
`npx hardhat test test/stat/PackFeel.test.js`) so the issue is NOT caused by
Phase 261 test additions.

**Affected:** Single-file `npx hardhat test <path>` invocations under ESM
projects (`"type": "module"` in package.json). The bug surfaces only at the
disposal stage; all tests run and report results normally before the crash.

**Workaround used in Phase 261 verification:** Read the human-readable test
result block (e.g., "N passing") rather than relying on the process exit code
when running a single test file. `npm run test:stat` (multiple files) and
`npm test` (suite) are unaffected because the unloader path resolves correctly
when there are multiple files in scope.

**Out of scope for Phase 261** — does not affect correctness of the gold-solo
audit. Document for future Phase that addresses test infrastructure.
