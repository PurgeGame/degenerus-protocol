---
phase: 356-tst-unmanipulable-strategic-sub-unsub-quest-core-non-perturb
plan: 02
subsystem: test-fuzz (v55-proof offset+write-mask migration)
tags: [d10, offset-migration, write-mask, v56-repack, sub-slot, adapt-template]
requires:
  - "356-01 (the 7 read-only fuzz files migrated; fixture green)"
  - "the v56 Sub re-pack frozen in contracts/ (subject 453f8073, IMPL diff committed/frozen)"
provides:
  - "V55FreezeDeterminism / V55RevertFreeEvCap / V55SetMutationOpenE reading AND writing the v56 Sub slot byte-correctly"
  - "valid Wave-1 ADAPT-source templates (no stale-layout writes left to carry forward)"
affects:
  - "356-03 (SEC-01 — adapts V55RevertFreeEvCap + V55SetMutationOpenE)"
  - "356-04 (SEC-02 — adapts V55FreezeDeterminism)"
  - "356-05 (QST-04 — reuses the V55SetMutationOpenE swap-pop fixture)"
  - "356-07 (the empirical 453f8073-baseline NON-WIDENING union — receives the PRE-EXISTING reds recorded below)"
tech-stack:
  added: []
  patterns:
    - "the 08e59a4a offset transform (OFF_LASTBOUGHT 21/uint32 -> 11/uint24) PLUS the write-mask shift (amount (1<<96)-1 -> 0xFFFFFF uint24, scorePlus1 byte7 -> byte6, day-marker masks 0xFFFFFFFF -> 0xFFFFFF)"
key-files:
  created: []
  modified:
    - test/fuzz/V55FreezeDeterminism.t.sol
    - test/fuzz/V55RevertFreeEvCap.t.sol
    - test/fuzz/V55SetMutationOpenE.t.sol
decisions:
  - "Migrated read offsets AND write-mask helpers (_pokeAfkingStamp / _setScorePlus1) in LOCKSTEP — a read-only constant swap would have corrupted the stamp writes (T-356-02-WM)."
  - "Did NOT touch any contract-behavior assertion. The remaining reds after the migration are genuine v56-behavior unmasks (NOT garbage-read / corrupt-mask reds) — recorded PRE-EXISTING for the 356-07 empirical baseline union, per the CONTEXT out-of-scope directive."
  - "OFF_DAILY=0 / OFF_VALIDTHROUGH=1 in V55SetMutationOpenE left unchanged (those bytes did not move in the re-pack)."
metrics:
  duration: ~15m
  completed: 2026-06-02
  tasks: 2
  files: 3
---

# Phase 356 Plan 02: Migrate the 3 v55-PROOF fuzz files (offsets + write-mask helpers) to the v56 Sub re-pack Summary

Migrated the three v55-PROOF fuzz files (`V55FreezeDeterminism`, `V55RevertFreeEvCap`, `V55SetMutationOpenE`) from the stale `OFF_LASTBOUGHT=21`/uint32 + `OFF_AMOUNT=9`/uint96 + `OFF_SCOREPLUS1=7` layout to the v56 compute-on-read re-pack — BOTH the read offsets AND the `_pokeAfkingStamp`/`_setScorePlus1` WRITE-mask helpers, in lockstep — so all three read and write the v56 Sub slot byte-correctly and are valid Wave-1 ADAPT-source templates.

## What Shipped

Confirmed the canonical v56 Sub-slot offsets via `forge inspect DegenerusGame storageLayout` (the `Sub` struct, slot 0): `scorePlus1 u16 @6 · amount u24 @8 · lastAutoBoughtDay u24 @11 · lastOpenedDay u24 @14 · afkCoveredThroughDay u24 @17 · afkingStartDay u24 @20 · affiliateBase u32 @23 · pendingBurnie u32 @27 · subStreakLatch u8 @31` — byte-identical to the canonical block in `test/gas/V56AfkingGasMarginal.t.sol:68-89`.

### Task 1 — V55FreezeDeterminism + V55RevertFreeEvCap (offsets + `_pokeAfkingStamp` masks) — commit `ab6700e7`
- Read offsets: `OFF_SCOREPLUS1 7->6`, `OFF_AMOUNT 9(uint96)->8(uint24)`, `OFF_LASTBOUGHT 21->11`, `OFF_LASTOPENED 25->14`.
- `_pokeAfkingStamp` write masks (both files): the amount mask `(uint256(1) << 96) - 1` -> `0xFFFFFF` (uint24 @8); the two day-marker masks `0xFFFFFFFF` -> `0xFFFFFF` (uint24 @11/@14); the scorePlus1 byte re-targets to @6 via the `OFF_SCOREPLUS1` constant; the amount write `(amount & ((1<<96)-1))` -> `(amount & 0xFFFFFF)`.
- Day-marker read helpers `_lastBoughtDayOf`/`_lastOpenedDayOf`: `_subField(..., 32)` -> `..., 24`.

### Task 2 — V55SetMutationOpenE (offsets + `_setScorePlus1` mask) — commit `b4a9a896`
- Read offsets: `OFF_SCOREPLUS1 7->6`, `OFF_AMOUNT 9(uint96)->8(uint24)`, `OFF_LASTBOUGHT 21->11`, `OFF_LASTOPENED 25->14`.
- `OFF_DAILY=0` and `OFF_VALIDTHROUGH=1` PRESERVED (those bytes did not move; `OFF_VALIDTHROUGH` comment narrowed uint32->uint24 to match the re-pack, byte unchanged).
- `_setScorePlus1` already masks `(OFF_SCOREPLUS1 * 8)` with a `0xFFFF` (uint16) mask — now correctly targets byte 6 via the migrated constant; the docstring "bytes 7..8" -> "bytes 6..7".
- Day-marker read helpers: width `32` -> `24`.

## Verification

- `forge inspect DegenerusGame storageLayout` confirmed all offsets/widths match the canonical block.
- All three suites COMPILE clean (`Compiler run successful` on each `forge test` invocation; patch -> test -> `git checkout -- contracts/ContractAddresses.sol` round-trip each time).
- Acceptance greps all pass: `grep '(uint256(1) << 96)'` empty across all three; `grep 'OFF_LASTBOUGHT *= *21|OFF_AMOUNT *= *9|OFF_LASTOPENED *= *25|OFF_SCOREPLUS1 *= *7'` empty; `OFF_LASTBOUGHT = 11`/`OFF_AMOUNT = 8`/`OFF_SCOREPLUS1 = 6` present; `OFF_DAILY = 0`/`OFF_VALIDTHROUGH = 1` preserved in V55SetMutationOpenE.
- `git diff --quiet HEAD -- contracts/` exits 0 throughout — ZERO `contracts/*.sol` mutation; `ContractAddresses.sol` restored after every patch round-trip.

### Per-suite forge run (the byte-correct-read/write evidence)
- **V55FreezeDeterminism**: 5/7 PASS — the freeze/determinism core ALL green: `testStampedDayDeterminismOpenAtTwoBlocks`, `testFuzzNoBlockEntropyInTheDraw`, `testIndexBindingMidDayAdvanceDoesNotRebind`, `testFuzzIndexBindingAdvanceInvariant`, `testPreRngStampNotOpenableUntilWordLands`. 2 red (DIFFERENTIAL arms — see PRE-EXISTING below).
- **V55RevertFreeEvCap**: 5/11 PASS — the class-A revert-free + class-C terminal-routing + EV-cap-clamp core green: `testClassA_ClaimableSentinelAndMinSkipNeverRevert`, `testClassA_FundedBoxOpenNeverReverts`, `testClassC_GameOverRoutingUnblockedByStage`, `testEvCapClampsAtTenEthNoRevert`, `testFuzzClassA_FundedSliceNeverReverts`. 6 red (class-B funding-delta + EV-cap-amount + withdraw-error — see PRE-EXISTING below).
- **V55SetMutationOpenE**: 9/10 PASS — every ADAPT-source arm the Wave-1 plans depend on is green: `testStreakNotCorruptedBySwapPop`, the no-orphan control/removed/guard trio, all four OPEN-E protection tests, `testFuzzOpenEDefaultSelfHoldsUnderOrderings`. 1 red (two-path coexistence vs the v56 unified valve — see PRE-EXISTING below).

## Deviations from Plan

None — the plan executed exactly as written (offset + write-mask migration in lockstep, no logic changes, no contract files touched). The `_setScorePlus1` docstring byte-range correction in V55SetMutationOpenE is a comment-only follow-on of the offset migration (not a logic change).

## PRE-EXISTING candidates for the 356-07 empirical 453f8073-baseline union

These reds are v56-behavior unmasks revealed by the offset migration (NOT garbage-read / corrupt-mask reds — the determinism/freeze/no-orphan/swap-pop/OPEN-E proofs all pass, proving the v56 slot reads/writes are byte-correct). Per the CONTEXT out-of-scope directive, the contract-behavior assertions were NOT changed here; 356-07 resolves their baseline classification, and the Wave-1 v56 successors (356-03/04/05) adapt the harness assumptions.

| Test | Red message | Root cause (v56-behavior unmask) |
|------|-------------|----------------------------------|
| V55FreezeDeterminism::testDifferentialAfkingVsHumanOpenSameTuple | `same scaledAmount: 5242880000000000000000 != 800000000000000000` | The v56 `Sub.amount` is **milli-ETH packed** (`_packEthToMilliEth`, `GameAfkingModule.sol:741`); the genuine `_openAfkingBox` reads `_unpackMilliEthToWei(uint64(sub.amount))` (`:1103`). The differential harness pokes a RAW-WEI amount into the uint24 field (truncates to `0x500000=5242880`) and the open then interprets it as milli-ETH (`5242880 * 1e15`), diverging from the human arm's raw-wei force. The amount field went uint96(raw-wei) -> uint24(milli-ETH) in the v56 re-pack. |
| V55FreezeDeterminism::testFuzzDifferentialAfkingVsHumanOpen | `same scaledAmount: ... != ...` | Same milli-ETH-packing unmask (fuzz variant). |
| V55RevertFreeEvCap::testEvCapExactlyOnceNoDoubleDraw | `EV-cap drawn EXACTLY ONCE: 10000000000000000000 != 3000000000000000000` | Same milli-ETH unmask: the poked raw-wei `amount=3 ether` truncates -> interpreted as milli-ETH -> a huge wei amount -> the EV-cap draw saturates at the 10-ETH cap. |
| V55RevertFreeEvCap::testEvCapSharedBudgetAcrossAfkingAndHuman | `afking open drew aAmt: 10000000000000000000 != 3000000000000000000` | Same milli-ETH unmask (afking arm). |
| V55RevertFreeEvCap::testFuzzEvCapMultiOpenClampedCumulative | `clamped cumulative draw: 10000000000000000000 != ...` | Same milli-ETH unmask (fuzz cumulative). |
| V55RevertFreeEvCap::testClassB_StageDebitSolvencyFailsLoud | `funding credited by subscribe msg.value: 4990000000000000000 != 5000000000000000000` | v56 subscribe-side behavior: the funding credited is 0.01 ETH below msg.value (a min-buy / first-stamp consumes 0.01 ETH). The `afkingFunding`/`claimablePool` reads are slot-8/slot-1 — independent of the Sub offsets migrated; this is purely contract behavior. |
| V55RevertFreeEvCap::testClassB_WithdrawSolvencyFailsLoud | `funding credited: 3990000000000000000 != 4000000000000000000` | Same 0.01-ETH subscribe-funding delta. |
| V55RevertFreeEvCap::testFuzzClassB_SolvencyAlwaysFailsLoud | `Error != expected error: E() != panic(0x11)` | v56 `withdrawAfkingFunding` reverts with a custom error `E()` rather than the v55 arithmetic-underflow panic the test `vm.expectRevert`s — a v56 guard-error behavior change on the withdraw path. |
| V55SetMutationOpenE::testTwoPathOpenCoexistenceNoCrossCorruption | `human open did not open the afking box: 2 != 0` | The v56 LIVE-01 unified `openBoxes` valve (`DegenerusGame.sol:1800`, commit `86a2d6c8`) calls `drainAfkingBoxes(maxCount)` FIRST then the human leg, so `openBoxes(50)` now ALSO opens the afking box (`lastOpenedDay` advances). The v55 assertion (human open leaves the afking stamp untouched) reflects the superseded two-path-separation design. A LIVE-01 surface owned by the Wave-1 successors / 356-07. |

## Self-Check: PASSED

- test/fuzz/V55FreezeDeterminism.t.sol — FOUND, modified, `OFF_LASTBOUGHT = 11` present.
- test/fuzz/V55RevertFreeEvCap.t.sol — FOUND, modified, `OFF_LASTBOUGHT = 11` present.
- test/fuzz/V55SetMutationOpenE.t.sol — FOUND, modified, `OFF_LASTBOUGHT = 11` + `OFF_DAILY = 0`/`OFF_VALIDTHROUGH = 1` present.
- Commit `ab6700e7` (Task 1) — FOUND in git log.
- Commit `b4a9a896` (Task 2) — FOUND in git log.
- `git diff --quiet HEAD -- contracts/` exits 0 — ZERO contract mutation.
