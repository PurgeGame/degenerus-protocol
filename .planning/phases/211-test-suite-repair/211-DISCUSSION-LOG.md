# Phase 211: Test Suite Repair - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-10
**Phase:** 211-test-suite-repair
**Areas discussed:** wXRP tests, vesting tests, setDecimatorAutoRebuy tests

---

## wXRP Scaling Mismatches (4 Hardhat failures)

| Option | Description | Selected |
|--------|-------------|----------|
| Fix scaling assertions | Debug whether v24.1 caused the mismatch and update expected values | |
| Delete wXRP tests entirely | Remove all WrappedWrappedXRP test interactions | ✓ |
| Document as pre-existing | Mark as known pre-existing and skip | |

**User's choice:** Delete wXRP tests entirely
**Notes:** User: "can we get rid of wwxrp scaling? just delete the whole interaction with wxrp"

---

## DegenerusStonk Vesting (8 Hardhat failures)

| Option | Description | Selected |
|--------|-------------|----------|
| Fix test setup | Ensure game.level() > 0 before claimVested calls | |
| Delete vesting tests | Remove DegenerusStonk-vesting tests entirely | ✓ |
| Document as pre-existing | Mark as known issue and skip | |

**User's choice:** Delete vesting tests entirely
**Notes:** User: "can delete both"

---

## setDecimatorAutoRebuy (2 Hardhat failures)

| Option | Description | Selected |
|--------|-------------|----------|
| Rewrite tests | Test the replacement path (vault-based decimator config) | |
| Delete tests | Remove tests for the removed function | ✓ |

**User's choice:** Delete tests entirely
**Notes:** User: "can delete both" (referring to vesting and setDecimatorAutoRebuy together)

---

## Claude's Discretion

- All Foundry failures (82) — mechanical slot/bit offset updates, no user input needed
- Remaining Hardhat failures (17) — mechanical assertion value updates
- Fix ordering and batching strategy

## Deferred Ideas

None.
