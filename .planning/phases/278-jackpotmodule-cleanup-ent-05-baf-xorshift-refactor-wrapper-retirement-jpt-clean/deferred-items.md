# Phase 278 — Deferred Items

Out-of-scope discoveries logged during Phase 278 Plan 02 execution. NOT fixed
in this phase (scope boundary: only auto-fix issues directly caused by the
plan's own changes).

## test/fuzz/TicketLifecycle.t.sol — `setUp()` reverts (PRE-EXISTING)

- **Found during:** Plan 02 Task 1/3 affected-suite run.
- **Symptom:** `forge test --match-path 'test/fuzz/TicketLifecycle.t.sol'`
  fails with `[FAIL: EvmError: Revert] setUp() (gas: 0)` — the suite's
  `setUp()` reverts before any fuzz test runs.
- **Out-of-scope confirmation:** Verified PRE-EXISTING by stashing Plan 02's
  edit to this file (a comment-only touch at L802-804, decision 3) and
  re-running against the committed HEAD `92eea1d7` state — `setUp()` reverts
  identically. Plan 02's only change to this file is the
  `EntropyLib.entropyStep` → keccak-chain comment reword; a comment change
  cannot cause a `setUp()` EVM revert.
- **Disposition:** Not caused by Phase 278. Left untouched per the executor
  scope boundary. Candidate for a future fixture-maintenance phase.
