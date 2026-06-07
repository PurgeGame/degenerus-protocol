---
phase: 376-impl-the-one-batched-contract-diff-afpay-pack-curse-smite
plan: 03
subsystem: infra
tags: [eip-170, forge, solidity, delegatecall, code-size, solvency]

# Dependency graph
requires:
  - phase: 376-01
    provides: PACK accessors + repacked balances mapping + generalized _settleShortfall + AfkingSpent event
  - phase: 376-02
    provides: curse counter field + MintStreakUtils curse helpers + decurse/smite host module
provides:
  - Full v61.0 batched contracts/*.sol diff applied, compiling clean (forge build exit 0), HELD at the contract-commit boundary for USER hand-review
  - EIP-170 reclaim: DegenerusGame back under the 24,576-byte ceiling (24,342 B) via two surgical function relocations
  - contracts/test/ build-cleanliness sweep complete (full forge build incl. tests compiles)
affects: [377-gas, 378-tst-sec]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "EIP-170 reclaim via de-view+relocate: move an off-chain-only read getter (zero on-chain callers) into a module behind a delegatecall stub, dropping its `view` (invisible to eth_call) — and, when the getter is the SOLE referencer of a large inherited helper, the helper drops from the Game bytecode too (the high-yield lever)."
    - "De-duplication reclaim: a Game function that re-implements logic already living in a module + interface collapses to a thin delegatecall stub at zero behavior cost."

key-files:
  created: []
  modified:
    - contracts/DegenerusGame.sol
    - contracts/modules/DegenerusGameMintModule.sol
    - contracts/interfaces/IDegenerusGameModules.sol
    - contracts/test/SettleClaimableShortfallTester.sol

key-decisions:
  - "EIP-170 reclaim approach = de-view read getters (USER-selected 2026-06-06), NOT the handoff's afking deposit/withdraw move (tiny fns, ~150-240 B, net-negative once stub overhead is counted)."
  - "decClaimable de-duplicated to its existing DecimatorModule impl (interface + module impl already present; Game copy had no internal callers); orphaned _unpackDecWinningSubbucket deleted."
  - "previewSellFarFutureTickets relocated to MintModule (its sellFarFutureTickets execution twin's home, where _quoteFarFutureSwap/_quoteFarFutureBurnieSplit already live); the Game stub drops those helpers from the Game bytecode — the bulk of the reclaim."
  - "Two hero-getter relocations (getDailyHeroWinner/getDailyHeroWager → Degenerette) were APPLIED then REVERTED: measured ~40 B Game reclaim for +463 B Degenerette churn — unnecessary once previewSell cleared the gap. Final diff is the minimal 2 moves."

patterns-established:
  - "Measure, don't estimate: stub overhead (~120-180 B) cancels small/medium getter bodies; only large-body or helper-dropping relocations reclaim meaningfully."

requirements-completed: [AFPAY-01, PACK-01, PACK-02]

# Metrics
duration: ~session
completed: 2026-06-06
---

# Phase 376-03: Build-Cleanliness + EIP-170 Reclaim + Contract-Commit-Boundary HOLD

**Full v61.0 batched diff compiles clean (contracts + tests, forge build exit 0); DegenerusGame brought back under EIP-170 (24,342 B) via decClaimable de-dup + previewSellFarFutureTickets relocation; the contracts/*.sol diff is HELD for USER hand-review.**

## Accomplishments
- **Test compile sweep complete.** Full `forge build` (contracts + all `test/`) exits 0. The prior session's fixes (`SettleClaimableShortfallTester` + `YieldSurplusSolvency`/`JackpotSingleCallCorrectness`/`StakedStonkRedemption` fuzz tests) plus the storage repack were sufficient — no remaining test compile breaks from the removed `afkingFunding` mapping / shifted slots.
- **EIP-170 BLOCKER resolved.** DegenerusGame was 25,205 B (629 B over). Now **24,342 B** (234 B under). Reclaim = two surgical relocations.
- **Batched diff HELD.** All 17 reqs (Track A + Track B) + the reclaim are applied and compiling; NOT committed. Held for USER hand-review per the contract-commit boundary.

## EIP-170 Reclaim Detail

The handoff's premise (move afking `deposit`/`withdraw` → GameAfkingModule, ~240 B) proved wrong: those are tiny functions whose delegatecall stubs nearly equal their bodies. Investigation against the v55 reclaim menu showed `claimAffiliateDgnrs` (the 1.3 KB win) was already spent and `playerActivityScore` (953 B) is off-limits (5 on-chain callers incl. the sDGNRS redemption snapshot `StakedDegenerusStonk:932`). USER selected **de-view the off-chain read getters**.

Empirical lesson (measured): stubbing small/medium getters nets ~nothing (decClaimable + 2 hero getters = only −40 B Game). The reclaim came from:

1. **`decClaimable` → delegatecall stub** (de-duplication). DecimatorModule already implements `decClaimable` (`:367`), the interface already declares it (`:162`), and the Game copy had no internal callers. Verified the module path (`decClaimable`→`_decClaimable`→`_decClaimableFromEntry`) is **guard-for-guard identical** to the old Game inline impl, incl. `amountWei = (poolWei * uint256(entryBurn)) / totalBurn`. The orphaned Game-private `_unpackDecWinningSubbucket` was deleted.
2. **`previewSellFarFutureTickets` → MintModule** (the high-yield move). It is the Game's SOLE referencer of `_quoteFarFutureSwap`/`_quoteFarFutureBurnieSplit` (inherited from MintStreakUtils). Converting the Game copy to a stub drops those helpers from the Game's deployed bytecode (~862 B total reclaim). The impl moved to MintModule alongside its execution twin `sellFarFutureTickets`, where the helpers already exist (so MintModule grows only by the wrapper).

| Contract | Before | After | Margin vs 24,576 |
|---|---|---|---|
| DegenerusGame | 25,205 | **24,342** | 234 B under |
| DegenerusGameMintModule | 24,055 | **24,356** | 220 B under |

All de-viewed getters verified to have **zero on-chain callers** (off-chain `eth_call` is unaffected by dropping `view`).

## Hand-Review Evidence (gate Task 2)

1. **`forge build`** (full, contracts + tests): **exit 0**. Tail shows only pre-existing `forge lint` unsafe-typecast warnings (not errors).
2. **`forge build --sizes`**: DegenerusGame **24,342 < 24,576** ✅; MintModule **24,356 < 24,576** ✅; "nothing over EIP-170."
3. **Contract diff scope** (`git diff --stat -- contracts/`): 13 files, +550/−242 (12 mainnet .sol + SettleClaimableShortfallTester). Per-REQ-ID summary: see 376-01-SUMMARY (PACK/AFPAY) and 376-02-SUMMARY (CURSE/SMITE); this plan adds only the EIP-170 reclaim moves above.
4. **RNG-freeze spot-check**: `git diff -- contracts/ | grep '^+' | grep -iE "rngword|rngWordByDay|rawFulfill|VRF"` → **CLEAN**, no new rngWord/VRF read introduced anywhere in the diff. (The reclaim moves are pure reads; SEC-01 proves the full surface at 378.)
5. **SOLVENCY-01 spot-check**: every afking credit/debit pairs a `claimablePool` delta —
   - `depositAfkingFunding`: `_creditAfking` (1630) + `claimablePool +=` (1631)
   - `withdrawAfkingFunding`: `_debitAfking` (1647) + `claimablePool -=` (1648)
   - `_processMintPayment` afking tier: `_debitAfking` (1135) + `claimablePool -=` (1150) + `emit AfkingSpent` (1151)

   **NOTE — supersession:** the plan's how-to-verify item 5 ("pairing inside the accessor … recombine `(uint256(afking) << 128) | claimable`, no naive full-word +=") describes the ORIGINAL SPEC. The USER-approved deviations (see below) moved the pairing to the CALL SITES and use naive `+=`/`-=` accessor math (supply-bound safe). The spot-check above reflects the AS-BUILT call-site pairing. SEC-02 (378) re-proves the identity empirically.

## Deviations from Plan

### Issue: the diff did NOT fit under EIP-170 as delivered (BLOCKER, resolved)
- **Found during:** Task 2 (the size guardrail check).
- **Issue:** DegenerusGame was 25,205 B (629 B over). v61's mandatory new Game code exceeded the baseline's headroom.
- **Fix:** USER-selected de-view-read-getters reclaim → the two relocations above. Game now 24,342 B.
- **Verification:** `forge build --sizes` (nothing over EIP-170); behavior-equivalence of `decClaimable` verified against the module impl.

### Benign deviations to FLAG at hand-review (document — do not "fix")
- Routing `GameOverModule` deity-refund + `MintModule` sDGNRS→player relabel through `_creditClaimable` adds a `PlayerCredited` emit where the raw writes were silent. Arguably-correct consistency; zero state/solvency change.
- The de-viewed read getters (`decClaimable`, `previewSellFarFutureTickets`) are no longer `view` in the Game ABI (delegatecall stubs can't be `view`); behavior is unchanged for off-chain `eth_call` (the only callers).

**Total deviations:** 1 blocker resolved (EIP-170 reclaim) + 2 benign-to-flag. No scope creep — the reclaim is the minimal set that clears the ceiling.

## Issues Encountered
- The two hero-getter relocations were applied, measured at ~40 B net, then reverted as unnecessary churn once `previewSell` alone cleared the gap (kept the hand-review diff to the minimal 2 moves).

## User Setup Required
None.

## Next Phase Readiness
- **The contract-commit boundary HOLD is active.** The batched `contracts/*.sol` diff is applied + compiling + under EIP-170, and is HELD for USER hand-review. The executor did NOT commit any `contracts/*.sol` and did NOT set any bypass.
- **To commit (USER's gated action):** `mv .git/hooks/pre-commit .git/hooks/pre-commit.bak` → commit → restore. The hook blocks any staged `contracts/` path.
- **377 (gas-neutrality)** and **378 (TST-01..06 + SEC-01/02)** follow after approval. The reclaim added a delegatecall hop to two OFF-CHAIN read getters only — no hot-path gas impact for 377.

---
*Phase: 376-impl-the-one-batched-contract-diff-afpay-pack-curse-smite (plan 03)*
*Completed: 2026-06-06*
