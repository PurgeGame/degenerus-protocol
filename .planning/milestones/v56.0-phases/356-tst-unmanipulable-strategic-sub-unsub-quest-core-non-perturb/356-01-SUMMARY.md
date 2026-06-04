---
phase: 356-tst-unmanipulable-strategic-sub-unsub-quest-core-non-perturb
plan: 01
subsystem: test-harness (forge fuzz, afking/keeper Sub-slot probes)
tags: [tst, offset-migration, v56-repack, non-widening, narrowing, fixture-gate]
requires:
  - "the v56 32-byte/13-field Sub slot frozen in DegenerusGameStorage.sol (uint24 day markers; OFF_LASTBOUGHT=byte 11)"
  - "the 08e59a4a gas-suite migration as the canonical mechanical transform"
  - "a green DeployProtocol forge fixture at setUp"
provides:
  - "7 read-only keeper/afking fuzz files reading the v56 Sub slot correctly (uint24/OFF_LASTBOUGHT=11)"
  - "a confirmed-green fixture (the proof waves are unblocked)"
  - "the 4 KeeperFaucetResistance unmasked-red names for the 356-07 baseline union"
affects:
  - "test/fuzz/AfKingConcurrency.t.sol"
  - "test/fuzz/AfKingFundingWaterfall.t.sol"
  - "test/fuzz/AfKingSubscription.t.sol"
  - "test/fuzz/KeeperRouterOneCategory.t.sol"
  - "test/fuzz/KeeperFaucetResistance.t.sol"
  - "test/fuzz/KeeperRewardRoutingSameResults.t.sol"
  - "test/fuzz/KeeperNonBrick.t.sol"
tech-stack:
  added: []
  patterns:
    - "Sub-slot direct-storage probing via vm.load >> (off*8) masked to field width (Pattern 2)"
    - "the 08e59a4a offset-migration transform (21/uint32 -> 11/uint24)"
    - "uint24() truncation on raw-shift day-marker reads (no explicit mask helper)"
key-files:
  created:
    - ".planning/phases/356-tst-unmanipulable-strategic-sub-unsub-quest-core-non-perturb/356-01-SUMMARY.md"
  modified:
    - "test/fuzz/AfKingConcurrency.t.sol"
    - "test/fuzz/AfKingFundingWaterfall.t.sol"
    - "test/fuzz/AfKingSubscription.t.sol"
    - "test/fuzz/KeeperRouterOneCategory.t.sol"
    - "test/fuzz/KeeperFaucetResistance.t.sol"
    - "test/fuzz/KeeperRewardRoutingSameResults.t.sol"
    - "test/fuzz/KeeperNonBrick.t.sol"
decisions:
  - "Migrated the FULL early-field re-pack (validThroughLevel uint24@1, reinvestPct@4, flags@5, scorePlus1@6, amount uint24@8), not just the two day markers, because the 7 files declare/use the early offsets too — the canonical v56 layout from DegenerusGameStorage.sol:1895 is authoritative."
  - "Narrowed write-masks 0xFFFFFFFF -> 0xFFFFFF on validThroughLevel/lastAutoBoughtDay clears so a uint24 field clear no longer clobbers the adjacent reinvestPct/lastOpenedDay byte (intent preserved, layout-correct)."
  - "Used uint24(packed >> (off*8)) truncation on the raw-shift reads in KeeperFaucetResistance/KeeperRewardRoutingSameResults instead of uint32(): with the v56 re-pack a uint32 cast would capture the low byte of the adjacent uint24 field (garbage)."
metrics:
  duration: ~11 min
  completed: 2026-06-02
  tasks: 2
  files_modified: 7
---

# Phase 356 Plan 01: Fixture-Sanity Gate + 7 Read-Only Keeper/AfKing Fuzz Offset Migration Summary

Confirmed the DeployProtocol forge fixture green at setUp, then migrated the 7 read-only keeper/afking fuzz files from the stale `OFF_LASTBOUGHT=21`/uint32 layout to the shipped v56 `11`/uint24 Sub re-pack (the exact `08e59a4a` mechanical transform), flipping the `6555125 != 3774873600` garbage-read reds green (a NARROWING) with zero test-logic change and zero `contracts/*.sol` mutation.

## What Was Built

**Task 1 — Fixture-sanity gate (no file mutation):** Ran `node scripts/lib/patchForFoundry.js` + `forge test --match-path test/gas/V56AfkingGasMarginal.t.sol`, restored `contracts/ContractAddresses.sol`. Result: `Suite result: ok. 5 passed; 0 failed` (setUp green); `git diff --quiet HEAD -- contracts/ContractAddresses.sol` exit 0. The 355-CONTEXT vanity-address down-state did NOT recur — the fixture is healthy and the proof waves are unblocked. No repair task was needed (the v55 351-01 precedent did not fire).

**Task 2 — Migrated the 7 read-only probe files** (`AfKingConcurrency`, `AfKingFundingWaterfall`, `AfKingSubscription`, `KeeperRouterOneCategory`, `KeeperFaucetResistance`, `KeeperRewardRoutingSameResults`, `KeeperNonBrick`). The mechanical transform per file:
- `OFF_LASTBOUGHT` 21 -> 11, `OFF_LASTOPENED` 25 -> 14 (both uint24, bytes 11..13 / 14..16).
- The early-field offsets re-derived to the v56 re-pack where the file declares them: `validThroughLevel` uint24 @1 (bytes 1..3), `reinvestPct` @4, `flags` @5, `scorePlus1` uint16 @6 (bytes 6..7), `amount` uint24 @8 (bytes 8..10). (`OFF_AMOUNT`/`OFF_SCOREPLUS1`/`OFF_REINVEST` are declared-but-unread in these files — values corrected for legibility regardless.)
- Every `_subField(who, OFF_<day-marker>, 32)` read narrowed to width `24`; the raw-shift reads in `KeeperFaucetResistance`/`KeeperRewardRoutingSameResults` changed `uint32(packed >> off*8)` -> `uint32(uint24(packed >> off*8))` (a bare `uint32` would now capture the adjacent uint24 field's low byte).
- The `0xFFFFFFFF` clear-masks on `lastAutoBoughtDay`/`validThroughLevel` (in `AfKingConcurrency._setValidThroughLevel`, `AfKingFundingWaterfall`/`AfKingSubscription._forceCrossingDue`) narrowed to `0xFFFFFF` so a uint24 field clear no longer overlaps the adjacent byte.
- Inline byte-range comments updated to match. Test LOGIC untouched (layout-read fix only).

Verified the 7 files carry NO `_setStamp`/`_setScorePlus1` write-mask helpers (grep-confirmed before editing) — pure read-only probes, so the pure offset + read-width swap was sufficient. The 3 v55-proof files (`V55FreezeDeterminism`, `V55RevertFreeEvCap`, `V55SetMutationOpenE`) that DO carry write masks are correctly left at the stale offset for 356-02.

## Verification Results

- `forge build` EXIT 0 after the migration.
- `grep -L 'OFF_LASTBOUGHT *= *11' <the 7 files>` -> empty (all 7 migrated).
- `grep -rn 'OFF_LASTBOUGHT *= *21' test/fuzz/AfKing*.t.sol test/fuzz/Keeper*.t.sol` -> empty.
- No `_subField(..., 32)` day-marker reads remain in the 7 files.
- Suite runs (after patchForFoundry, before restore): the 3 AfKing suites GREEN (8 / 14 / 12 passed); `KeeperRouterOneCategory` GREEN (7); `KeeperRewardRoutingSameResults` GREEN (7); `KeeperNonBrick` GREEN (14).
- `git diff --quiet HEAD -- contracts/` exit 0 after every patch round-trip (ContractAddresses.sol restored each time).

## The KeeperFaucetResistance NARROWING (the headline)

At HEAD (pre-migration), `KeeperFaucetResistance` had **3 failures, ALL the `6555125 != 3774873600` garbage-read reds** (the exact stale-layout symptom — `testFuzz_RouterOpenRoundTripNonPositiveAcrossGasPrices`, `testRouterOpenSelfKeeperRoundTripNonPositiveAboveKnee`, `testRouterOpenSelfKeeperRoundTripNonPositiveBelowKnee`). After the migration those 3 garbage-read reds are GONE (resolved -> a NARROWING, never a widening). The migration unmasked **4 different, PRE-EXISTING v56-behavior reds** (the tests now run past the previously-failing garbage assertion and reach the next assertion):

| Unmasked red | Cause (NOT a layout error) |
|--------------|----------------------------|
| `testCancelThenWithdrawAlwaysSucceeds` | `funding credited by subscribe msg.value: 2990000000000000000 != 3000000000000000000` — the v56 0.01-ETH subscribe fee |
| `testSolvencyUnderflowFailsLoudOnWithdraw` | same 0.01-ETH funding delta (4 ETH case) + the dropped `withdraw` two-step (affiliate single-step claim, per `affiliate-claim-single-step-direct-mint`) |
| `testFuzzSolvencyUnderflowFailsLoud(uint96,uint96)` | `E() != panic 0x11` — revert-selector expectation vs v56 contract behavior |
| `testFuzz_CancelWithdrawNeverStrandsEth(uint96,uint96)` | `E()` — same revert-selector expectation vs v56 |

These 4 are **recorded as PRE-EXISTING for the 356-07 empirical baseline union** (the `453f8073`-vs-HEAD reconciliation), NOT new regressions: my diff to the file is purely the offset constants + the two day-marker read-width casts (verified by `git diff`), and the 4 failing tests do not reference the migrated `_lastAutoBoughtDayOf`/`_lastOpenedDayOf` symbols. Proven by temporarily reverting the file to HEAD and re-running (3 garbage reds present; my edits flip them green). The migration is a strict NARROWING for this file; the unmasked reds belong to the v56 contract-behavior reconciliation 356-07 owns.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Narrowed write-masks to match uint24 field widths**
- **Found during:** Task 2 (AfKingConcurrency._setValidThroughLevel, AfKingFundingWaterfall/AfKingSubscription._forceCrossingDue)
- **Issue:** The stale files cleared 32-bit (`0xFFFFFFFF`) masks at `OFF_VALIDTHROUGH`/`OFF_LASTBOUGHT`. In the v56 re-pack those fields are uint24 with an adjacent packed field one byte above, so a 32-bit clear would clobber the neighbor (`reinvestPct` / `lastOpenedDay` low byte).
- **Fix:** Narrowed the masks to `0xFFFFFF` (24-bit) matching the actual field widths; intent (clear exactly that field) preserved.
- **Files modified:** test/fuzz/AfKingConcurrency.t.sol, test/fuzz/AfKingFundingWaterfall.t.sol, test/fuzz/AfKingSubscription.t.sol
- **Commit:** 27981370

**2. [Rule 1 - Bug] uint24() truncation on raw-shift reads (KeeperFaucetResistance / KeeperRewardRoutingSameResults)**
- **Found during:** Task 2
- **Issue:** Those two files read the day marker via `uint32(packed >> off*8)` with NO mask (the old uint32 day field was captured exactly by the uint32 cast). With the v56 uint24 day field plus an adjacent uint24 field above it, the bare `uint32` cast captures the neighbor's low byte (garbage).
- **Fix:** Changed to `uint32(uint24(packed >> off*8))` — truncate to the exact 24-bit field width.
- **Files modified:** test/fuzz/KeeperFaucetResistance.t.sol, test/fuzz/KeeperRewardRoutingSameResults.t.sol
- **Commit:** 27981370

No architectural changes (Rule 4) were needed; no packages installed (Rule 3 exclusion N/A); no authentication gates.

## Known Stubs

None. These are read-only probes against a frozen contract; no stub/placeholder data was introduced.

## Threat Flags

None. The migration touches only test-harness Sub-slot reads (the T-356-01-FG test-integrity boundary the plan exists to close). No new contract surface, endpoint, auth path, or schema change was introduced.

## Self-Check: PASSED

- test/fuzz/AfKingConcurrency.t.sol — FOUND (OFF_LASTBOUGHT=11)
- test/fuzz/AfKingFundingWaterfall.t.sol — FOUND (OFF_LASTBOUGHT=11)
- test/fuzz/AfKingSubscription.t.sol — FOUND (OFF_LASTBOUGHT=11)
- test/fuzz/KeeperRouterOneCategory.t.sol — FOUND (OFF_LASTBOUGHT=11)
- test/fuzz/KeeperFaucetResistance.t.sol — FOUND (OFF_LASTBOUGHT=11)
- test/fuzz/KeeperRewardRoutingSameResults.t.sol — FOUND (OFF_LASTBOUGHT=11)
- test/fuzz/KeeperNonBrick.t.sol — FOUND (OFF_LASTBOUGHT=11)
- Commit 27981370 — FOUND (git log)
- contracts/ clean vs HEAD — CONFIRMED (zero contract mutation)
