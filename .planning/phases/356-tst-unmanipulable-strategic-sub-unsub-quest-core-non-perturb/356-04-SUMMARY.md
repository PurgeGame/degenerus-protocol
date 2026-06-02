---
phase: 356-tst-unmanipulable-strategic-sub-unsub-quest-core-non-perturb
plan: 04
subsystem: test-fuzz (SEC-02 — solvency invariant + RNG-freeze determinism, v56 frozen subject)
tags: [sec-02, d05, solvency-invariant, rng-freeze, stamp-not-resolve, two-block-determinism, adapt]
requires:
  - "356-02 (the v56-migrated V55FreezeDeterminism box-identity oracle + V55RevertFreeEvCap solvency reads)"
  - "the v56 Sub re-pack frozen in contracts/ (subject 453f8073, IMPL diff committed/frozen)"
provides:
  - "test/fuzz/V56FreezeSolvency.t.sol — the SEC-02 solvency invariant fuzz (leg 2) + RNG-freeze determinism fuzz (leg 3) + the leg-1 forge arm (debit == delivered value; BURNIE OFF the ETH/pool path)"
  - "the leg-1 byte-diff anchor handoff to 356-07: the SOLVENCY-01 debit two-liner is byte-frozen vs 453f8073"
affects:
  - "356-07 (the NON-WIDENING ledger — records the leg-1 git byte-diff anchor for GameAfkingModule.sol:663-664)"
  - "357 (the adversarial sweep — SEC-02 empirically closed here; the drainAffiliateBase unreachable-stub flag below)"
tech-stack:
  added: []
  patterns:
    - "the v56 funded-sub delivery harness (accumulating-`_t` warp + fulfill-first _settleGame/_settleClean/_fulfillPending + openBoxes(400)) reused from V56SecUnmanipulable (356-03)"
    - "the materialized-box byte-identity oracle (LOOTBOX_OPENED_SIG decode -> Box struct) adapted from the v56-migrated V55FreezeDeterminism"
    - "the claimablePool slot read (slot 1, byte 16, uint128) from the v56-migrated V55RevertFreeEvCap"
key-files:
  created:
    - test/fuzz/V56FreezeSolvency.t.sol
  modified: []
decisions:
  - "Leg 1 is proven via the BEHAVIOR (the forge arm asserts ΔafkingFunding == ΔclaimablePool across a delivered buy == the byte-frozen `afkingFunding[src] -= ethValue; claimablePool -= uint128(ethValue)` two-liner; plus the BURNIE claim leaves claimablePool byte-unchanged). The literal git byte-diff anchor vs 453f8073 is recorded by 356-07's ledger (per the plan's D-05 split)."
  - "The fixture holds plain ETH (no stETH minted to the game), so the solvency observable reads `address(game).balance + mockStETH.balanceOf(address(game)) >= claimablePool` — the stETH term is 0 but is read explicitly to stay faithful to the contract's invariant shape (DegenerusGame.sol:18)."
  - "The afking open is reached via mintBurnie() (the autoOpen selector was dropped — NOT re-exposed on the Game), per the plan's interfaces note. The two-block determinism perturbs prevrandao/coinbase/number/timestamp; the live level is held inside a sub-day window (the level is LIVE by design — the property under test is the SEED freeze)."
metrics:
  duration: ~25m
  completed: 2026-06-02
  tasks: 2
  files: 1
---

# Phase 356 Plan 04: SEC-02 — V56FreezeSolvency (solvency invariant fuzz + RNG-freeze determinism fuzz) Summary

Authored `test/fuzz/V56FreezeSolvency.t.sol` (`contract V56FreezeSolvency is DeployProtocol`) — the SEC-02 proof in three legs (D-05) against the FROZEN v56 subject. **7 tests, all green** (2 of them 1000-run seeded fuzz invariants). The v56 accrual/settle redesign is proven a BURNIE-emission-timing change only: it touches no frozen RNG-window slot, the ETH/`claimablePool` debit is byte-frozen, and the affiliate/quest rewards stay BURNIE flip-credit OFF the ETH path.

## What Shipped

One new forge fuzz suite (579 lines) reusing the v56 funded-sub delivery harness from the 356-03 `V56SecUnmanipulable` (accumulating-`_t` warp + fulfill-first settle + `openBoxes(400)` open), the materialized-box byte-identity oracle from the v56-migrated `V55FreezeDeterminism`, and the `claimablePool` slot read from the v56-migrated `V55RevertFreeEvCap`. The v56 Sub-slot offset block (`OFF_AMOUNT=8`/milli-ETH, `OFF_LASTBOUGHT=11`/uint24, `OFF_PENDINGBURNIE=27`/uint32) is copied verbatim from `V56AfkingGasMarginal:68-89`.

### Task 1 — leg 2 (solvency invariant) + leg 1 forge arm — commit `f3ab23b6`
- `testFuzzSolvencyInvariantUnderChurn` (1000 runs): `game.balance + steth.balanceOf(game) >= claimablePool` holds after EVERY action in a fuzzed {sub, unsub, buy, accrue, claimAfkingBurnie} sequence (an anchor buy guarantees non-vacuity; the unsub branch is guarded on an active sub — a real user can't cancel a non-existent sub).
- `testSolvencyHoldsBuyThenBurnieClaim`: a delivered buy debits `claimablePool` by its fresh-ETH spend; the subsequent `claimAfkingBurnie` leaves the pool byte-unchanged; the invariant holds across both.
- `testDebitEqualsDeliveredEthValueExactly` (leg 1 forge arm): `ΔclaimablePool == ΔafkingFunding[player]` across a single delivered buy — the debit is the SAME `ethValue` on both ledgers (the byte-frozen v55 SOLVENCY-01 two-liner `afkingFunding[src] -= ethValue; claimablePool -= uint128(ethValue)`).
- `testBurnieClaimLeavesClaimablePoolUnchanged` (leg 1 forge arm): the BURNIE accrue + claim is OFF the ETH/pool path — the pool is byte-identical before/after the claim (an exact equality), and the BURNIE is paid via `creditFlip` (`coinflipAmount` rises by `owed * 1e18`), never an ETH move.

### Task 2 — leg 3 (RNG-freeze determinism) — commit `cc529ad2`
- `testSubscribeMinBuyStampsNoInlineResolve`: the subscribe min-buy + the STAGE buy emit ZERO `LootBoxOpened` (the box is STAMPED, not resolved pre-RNG); non-vacuous (a box WAS stamped and pending, and the deferred open DOES emit `LootBoxOpened`).
- `testStampedDayOpenAtTwoBlocksByteIdentical`: open the SAME stamp twice at DIFFERENT blocks (perturbed prevrandao/coinbase/number/timestamp via snapshot/revert) → byte-identical materialized box; the box's `day` field is the FROZEN stamp day.
- `testFuzzTwoBlockOpenNoBlockEntropy` (1000 runs): any two random perturbed open-block contexts agree → the single-roll open + `pendingBurnie` credit consume ONLY the frozen `rngWordByDay[stampDay]` (the seed `keccak256(abi.encode(rngWordByDay[stampDay], player, stampDay, amount))` carries no block.* entropy).

## Verification

- `node scripts/lib/patchForFoundry.js && forge test --match-contract V56FreezeSolvency`: **7 passed, 0 failed** (`testFuzzSolvencyInvariantUnderChurn` + `testFuzzTwoBlockOpenNoBlockEntropy` at 1000 seeded runs each).
- `forge build` EXIT 0.
- `git diff --quiet HEAD -- contracts/` exits 0 throughout — ZERO `contracts/*.sol` mutation; `ContractAddresses.sol` restored after every patch round-trip.

### Leg-1 byte-diff anchor (handoff to 356-07's ledger)
`git diff 453f8073 HEAD -- contracts/modules/GameAfkingModule.sol` shows the SOLVENCY-01 debit two-liner re-added VERBATIM (only the surrounding code/comments relocated): the literal statements `afkingFunding[src] -= ethValue;` + `claimablePool -= uint128(ethValue);` are byte-identical between `453f8073` (was `:709-710`) and HEAD (`:663-664`). The forge arm proves the matching behavior empirically; 356-07 records the literal git anchor in `REGRESSION-BASELINE-v56.md`.

## Deviations from Plan

**1. [Rule 1 - Bug] Fuzz non-vacuity guard tripped on a no-buy action stream**
- **Found during:** Task 1 (first forge run)
- **Issue:** `testFuzzSolvencyInvariantUnderChurn` asserted `delivered > 0`, but a fuzzed `seq` with `rounds=0` (n=3) could select no `buy` action across all rounds → `delivered == 0` (a harness flaw, NOT a solvency breach — every `_assertSolvent` passed).
- **Fix:** Deliver one anchor buy up front (always exercises the invariant against a pool a real buy moved), `delivered = 1`.
- **Files modified:** test/fuzz/V56FreezeSolvency.t.sol
- **Commit:** `f3ab23b6`

**2. [Rule 1 - Bug] Unsub action reverted `NotSubscribed()` on an already-cancelled sub**
- **Found during:** Task 1 (second forge run)
- **Issue:** the unsub action (`subscribe(_,0)`) reverts `NotSubscribed()` when the target isn't an active sub (already unsubbed, or STAGE-reclaimed). A real user can't cancel a non-existent sub either.
- **Fix:** guard the unsub branch on `_subscriberIndexOf(a) != 0 && _dailyQtyOf(a) != 0`; re-sub `b` before a funding top-up if a reclaim deleted its slot.
- **Files modified:** test/fuzz/V56FreezeSolvency.t.sol
- **Commit:** `f3ab23b6`

**3. [Stale line reference, no code change] The plan's interface cited the SOLVENCY-01 debit at `GameAfkingModule:744-745`; at HEAD it is at `:663-664`.** `:744-745` is the mode-agnostic BURNIE accrue block at HEAD (the file shifted ~80 lines vs the plan's snapshot). The behavior is unchanged; the forge arm + the byte-diff anchor target the correct debit site `:663-664`. No deviation in logic — only a corrected line anchor.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: unreachable-stub | test/fuzz/V56FreezeSolvency.t.sol | The affiliate base (`drainAffiliateBase`) is NOT routed through any of this suite's solvency assertions — and (flagged by 356-03) `DegenerusGame` may lack a `drainAffiliateBase` dispatch stub in the forge fixture. This suite proves the storage-level property instead: the affiliate base is BURNIE flip-credit OFF the ETH/pool path (the `claimablePool` is byte-unchanged across the only BURNIE legs this suite touches — `claimAfkingBurnie`), so the affiliate pull never affects `claimablePool` solvency regardless of when/whether it is pulled. The unreachable-stub observation is carried for Phase 357. |

## Known Stubs

None — the suite drives the genuine shipped surface (real `subscribe`/`depositAfkingFunding`/`advanceGame`/`mintBurnie`/`openBoxes`/`claimAfkingBurnie`); the only `vm.store` pokes are the deity-pass bit (standard fixture setup) — there is no hardcoded data flowing to an assertion.

## Self-Check: PASSED

- test/fuzz/V56FreezeSolvency.t.sol — FOUND (579 lines; `contract V56FreezeSolvency is DeployProtocol`; 7 tests green; forge build EXIT 0).
- Commit `f3ab23b6` (Task 1) — FOUND in git log.
- Commit `cc529ad2` (Task 2) — FOUND in git log.
- `git diff --quiet HEAD -- contracts/` exits 0 — ZERO contract mutation.
