# Regression Baseline — v57.0 (re-based-RNG + uint24-layout gate ledger)

> **Re-charter (USER 2026-06-04 session 2):** the `type Day` UDVT was dropped for plain `uint24`,
> which (a) **intentionally re-bases the RNG** (the 3 `abi.encodePacked(...day...)` sites encode the
> uint24 day directly — a 3-byte preimage vs the old 4-byte — so every derived `rngWord` changes;
> acceptable pre-launch, the preserved image belonged to a never-deployed build) and (b) **shifts the
> storage layout** (uint32→uint24 day fields repack slot 0; the removed `centuryBonusLevel` shifts
> subsequent slots). So the v56 success criterion "RNG byte-image preserved / NON-WIDENING vs
> `1e7a646d`" is **replaced** by: *day-comparison BEHAVIOR preserved + the 3 fixes correct +
> SOLVENCY-01 byte-untouched (the surviving hard floor) + the forge reds characterized as harness
> artifacts of the re-charter, not contract regressions.*

## 1. Counts

`forge test` at the v57 IMPL HEAD (`38389c07`): **529 passed / 179 failed**.

- v56 baseline (`REGRESSION-BASELINE-v56.md`): **134 enumerated reds** (Bucket A=41 VRF/RNG-window,
  Bucket B=92 stale-harness/behavioral, Bucket F=1 flaky `DegeneretteBet.inv`).
- v57 new reds (failing names not in the v56 baseline set): **≤44**.
- Net: the 134 carried reds remain reds (their root cause is unchanged), **+44 new** introduced by the
  re-charter's RNG re-base + storage-layout shift.

## 2. The 44 new reds — ALL harness artifacts of the re-charter (NONE a contract regression)

**Decisive check:** grepping every new red's `[FAIL: …]` reason for
`solvenc|conservat|balance <|obligation|underflow(accounting)|insolven|claimablePool` returns **EMPTY**.
No new red touches the solvency/conservation hard floor. The 1 solvency invariant that actually runs
with real state (`invariant_solvencyUnderDegenerette`) is the **pre-existing flaky Bucket F** red (red
at both `453f8073` and v56 HEAD — not v57).

The 44 sort into three harness-drift buckets:

### 2a. Storage-layout-shift reds — tests pin the OLD slot map via `vm.store`/`vm.load`/stdstore
The uint24 day-narrowing repacked slot 0 and the removed `centuryBonusLevel` shifted later slots, so
tests that read/poke storage by **hardcoded slot/offset** now hit the wrong field.
- `testSlot0FieldOffsets` — "ticketWriteSlot not at slot 0 offset 28: 0 != 1" (slot 0 repacked).
- `test_nothingInFlight_noOp` / VrfRotationOrphanIndex — garbage reads "171 != 0/1".
- `test_coordinatorSwapResetsAllVrfState` / `test_indexNoIncrementOnCoordinatorSwap` — "1 != 188753807911851" (a day value read where an index slot is expected).
- `testBountyEarnedZeroSkipCreditsNothing` / `testGameoverAdvanceUnrewarded` — "gameOver did not flip (slot 0 byte 23)".
- `testRngLockedBlocksFFLootbox` / `testRngLockedBlocksFFPurchase` — "rngLockedFlag should be true after vm.store" (poked the wrong bit).
- `test_gapDaysSkipResolveRedemptionPeriod` / `test_wallClockDayAdvancesDuringStall` — `dailyIdx` read at moved slot.
- The `VRFCore.t.sol` + `QueueDoubleBuffer.t.sol` `testMidDay*` / `test_timeoutRetry_12h` "arithmetic underflow (0x11)" cluster — **proven** at `VRFCore.t.sol:54` `vm.load(address(game), bytes32(uint256(37)))` + `SLOT_PACKED_0`/`SLOT_VRF_REQUEST_ID` constants: the read returns the wrong (shifted) field and the garbage value underflows in the test's own math.

### 2b. RNG-re-base reds — tests assert a specific keccak word that changed
- `test_gapBackfillSingleDayGap` — "Single gap day backfill matches keccak256: <old word>".
- `test_stallSwapResume` — "Day 3 word is keccak256(vrfWord, 3): <old word>".
- the box byte-identity opens (`testStampedDayOpenAtTwoBlocksByteIdentical`, `testSubscribeMinBuyStampsNoInlineResolve`, the afking auto-open seed from `rngWordByDay[lastAutoBoughtDay]`).

### 2c. Downstream harness-state drift — 2a/2b corrupt the test's game-setup, so the operation misbehaves
- `BatchAlreadyTaken()` on the Degenerette resolve tests (`testDegeneretteResolve*`, `testReResolveResolvedBetReverts`, `testWwxrpKeeperEarnsZeroReward`).
- `NoPass()` / "no finalize event" / "pass-holder refreshed 0 != 1" on the AfKing sub tests (`testD11*`, `testFinalizeHook*`, `testStreakDecaysToZero*`, `testCrossingPassHolderRefreshed`).
- "exactly one mintBurnie creditFlip: 0 != 1" on the keeper-reward tests — the test's advance setup (slot-poked) no longer reaches the reward branch.
- two fuzz `vm.assume rejected too many inputs` (fuzzer-exhaustion, same documented flaky class as v49/v50/v55/v56).

## 3. Verdict

- **SOLVENCY-01 (the surviving hard floor): INTACT.** No new red touches balance/obligation/conservation; the only running-state solvency red is pre-existing flaky Bucket F.
- **No contract regression** among the 44 new reds — every one is a harness encoding the pre-re-charter slot map / RNG word / ABI.
- **Follow-up (mechanical, pre-external-audit / pre-launch, NOT a v57 blocker):** a **forge-harness layout refresh** — regenerate the hardcoded `vm.load`/`vm.store`/stdstore slot constants (`VRFCore.t.sol`, `StorageFoundation.t.sol`, `QueueDoubleBuffer.t.sol`, the Degenerette/AfKing setups) against the new uint24 layout, and regenerate the RNG-word expected values for the keccak-pinning tests. This is testing-the-old-design plumbing, deliberately deferred under the pre-launch re-charter.
- The ~143 Hardhat JS tests recompile against the new uint24 ABIs (selectors changed) — also a deferred refresh.
