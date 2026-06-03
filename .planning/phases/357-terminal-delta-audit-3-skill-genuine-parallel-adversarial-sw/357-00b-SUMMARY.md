---
phase: 357-terminal-delta-audit-3-skill-genuine-parallel-adversarial-sw
plan: 00b
subsystem: testing
tags: [foundry, hardhat, solidity, afking, advance-incentive, bounty-eligible, non-widening, regression-ledger]

requires:
  - phase: 357-00
    provides: "HEAD' ac5f1e03 (F-356-01 stub + D-11/D-12/D-13 subscribe hardening) — the first 357 contract gate"
  - phase: 357
    provides: "HEAD'' 61315ecd — the SECOND 357 contract gate (the advance-incentive redesign), committed by the orchestrator"
provides:
  - "HEAD'' = 61315ecd0d617e5ece386676aaf452282331ebdf re-confirmed as the CURRENT re-frozen audit subject (audited == shipped)"
  - "V56SubHardening advance-soft-gate proofs (11 → 17 GREEN): advanceGame liveness + bountyEligible truth table + mintBurnie eligible/ineligible pay + Vault/sDGNRS→mintBurnie routing"
  - "GovernanceGating GATE-01..04 rewritten to the soft pay-gate model (no MustMintToday — the error was removed)"
  - "REGRESSION-BASELINE-v56.md §9 reconciled to HEAD'' (567/133/99; live − union == ∅ HOLDS; SOLVENCY-01 leg-1 byte-anchor held)"
affects: [357-01, 357-02, 357-03, 357-04]

tech-stack:
  added: []
  patterns:
    - "soft pay-gate proof: assert game.bountyEligible(addr) tier truth table + the directional mintBurnie pay invariant (eligible→nonzero coinflipAmount, ineligible→zero) — the advance WORK runs regardless"
    - "liveness proof: a fresh non-DGVE EOA cranks advanceGame() with NO removed-gate revert; warp-to-day-boundary positions the 15/30-min bounty windows deterministically"

key-files:
  created: []
  modified:
    - test/unit/GovernanceGating.test.js
    - test/fuzz/V56SubHardening.t.sol
    - test/REGRESSION-BASELINE-v56.md

key-decisions:
  - "The 134→133 narrowing is run-variance within the documented non-deterministic Bucket A (VRF/RNG-window) + Bucket F (flaky invariant) + vm.assume-exhaustion cluster — NOT a deterministic gate-freed forge fixture; the MustMintToday hard-revert had a SINGLE consumer, the Hardhat GovernanceGating block (not in the forge tree)."
  - "The binding subset gate live − union == ∅ is verified empirically at HEAD'' (the 133 failing forge names ⊆ the §2 134-name 453f8073 union; empty set-diff) — NON-WIDENING HOLDS, zero new forge regression from the redesign."
  - "SOLVENCY-01 leg-1 byte-anchor holds: the advance-incentive redesign is liveness-only (advanceGame drops a VIEW-only gate) + BURNIE-bounty-only (mintBurnie soft pay-gate) — no ETH/claimablePool debit, no frozen RNG-window slot."

patterns-established:
  - "When a removed custom error had only a Hardhat consumer, the forge NON-WIDENING ledger narrows by run-variance; reconcile the Hardhat consumer (rewrite to the new model) AND record the narrowing as variance in the ledger — do not invent a phantom forge fixture."

requirements-completed: [AUDIT-01]

duration: ~20min
completed: 2026-06-03
---

# Phase 357 / Plan 00b: D-14 Test Reconciliation @ HEAD'' Summary

**Extended the 357-00b D-14 reconciliation to the SECOND contract gate HEAD'' = `61315ecd` (the advance-incentive redesign): rewrote the Hardhat GovernanceGating GATE-01..04 to the soft pay-gate model (MustMintToday removed), added 6 advance-soft-gate forge proofs to V56SubHardening (11→17 GREEN), and reconciled the NON-WIDENING ledger §9 to 567/133/99 with `live − union == ∅` HOLDING — the audit subject is re-frozen at HEAD'' with ZERO contract mutation in this plan.**

## Performance

- **Duration:** ~20 min
- **Completed:** 2026-06-03T12:02:37Z
- **Tasks:** 3/3
- **Files modified:** 3 (`test/unit/GovernanceGating.test.js`, `test/fuzz/V56SubHardening.t.sol`, `test/REGRESSION-BASELINE-v56.md`)

## HEAD'' (the CURRENT re-frozen subject)

```
61315ecd0d617e5ece386676aaf452282331ebdf
```

The SECOND `contracts/*.sol` commit of phase 357 (after HEAD' `ac5f1e03`) — the advance-incentive redesign (6 files): `advanceGame()` is PURE LIVENESS (the `MustMintToday` hard revert + the dead `_enforceDailyMintGate`/vault/caller args removed); the must-mint tier ladder is now the SOFT pay-gate `_bountyEligible(address)` in `DegenerusGameMintStreakUtils`; `mintBurnie()` reads it BEFORE the self-call and pays the advance bounty only when `mult>0 && eligible`; NEW `bountyEligible(address) external view`; `DegenerusVault.gameAdvance()` + `StakedDegenerusStonk.gameAdvance()` route through `mintBurnie()`. Everything downstream (357-01 delta-audit, 357-02 sweep, 357-03 FINDINGS, 357-04 closure) re-freezes against HEAD'' and is READ-ONLY against `contracts/`. **`git diff 61315ecd HEAD -- contracts/` is EMPTY.**

## Accomplishments

1. **GovernanceGating GATE-01..04 rewritten to the soft pay-gate model** — the blocks asserted the now-REMOVED `revertedWithCustomError(advanceModule, "MustMintToday")`; the error no longer exists in the contract surface, so those assertions were dropped and the block rewritten: GATE-01 same-day minter is `bountyEligible` AND advances; GATE-02 the 30-min window flips a non-minter eligible while the advance always works; GATE-03 the DGVE majority holder is always eligible; GATE-04 an ineligible keeper earns no bounty but the advance still runs. **6/6 GATE tests GREEN** (`npx hardhat test`).
2. **V56SubHardening extended with 6 advance-soft-gate proofs (11 → 17 GREEN)** — `testAdvanceGameLivenessFreshNonMinterNotGated`, `testBountyEligibleTruthTable`, `testMintBurnieEligibleKeeperEarnsAdvanceBounty`, `testMintBurnieIneligibleKeeperEarnsZeroButWorkRuns`, `testVaultGameAdvanceRoutesThroughMintBurnie`, `testSdgnrsGameAdvanceRoutesThroughMintBurnie`. `forge test --match-contract V56SubHardening` = 17 passed / 0 failed / 0 skipped.
3. **REGRESSION-BASELINE-v56.md §9 reconciled to HEAD''** — counts 567/133/99; the binding gate `live − union == ∅` HOLDS at HEAD'' (the 133 failing forge names ⊆ the §2 134-name `453f8073` union — empty set-diff, verified empirically against `/tmp/ft357.log`); the 134→133 narrowing recorded as run-variance in the non-deterministic Bucket A/F + `vm.assume`-exhaustion cluster; the SOLVENCY-01 leg-1 byte-anchor re-confirmed. Top banner updated to HEAD''.

## Task Commits

1. **Task 1: GovernanceGating GATE-01..04 soft-gate rewrite** — `056e78c8` (test)
2. **Task 2: V56SubHardening advance-soft-gate proofs** — `1d5fd872` (test)
3. **Task 3: REGRESSION-BASELINE-v56.md §9 reconcile to HEAD''** — `48fab561` (test)

## Files Created/Modified

- `test/unit/GovernanceGating.test.js` — GATE-01..04 rewritten to the soft pay-gate model (no MustMintToday assertions; covers `bountyEligible` + advanceGame liveness)
- `test/fuzz/V56SubHardening.t.sol` — +6 advance-soft-gate proofs (17 total GREEN) + a `_warpToDayBoundary` helper
- `test/REGRESSION-BASELINE-v56.md` — new §9 (HEAD'' reconciliation) + top banner updated to HEAD''

## Reconciled Forge Counts @ HEAD''

```
forge test (WHOLE tree, /tmp/ft357.log) → 567 passed / 133 failed / 99 skipped  (799 total)
live − union == ∅ (the 133 failing names ⊆ the §2 134-name 453f8073 union)  → NON-WIDENING HOLDS
```

## Decisions Made

- **The narrowed red is run-variance, not a deterministic gate-freed forge fixture.** The `MustMintToday` hard-revert had exactly ONE consumer — the Hardhat `GovernanceGating` GATE-01..04 block (a unit test, NOT in the forge tree / NOT in the §2 forge union). No forge `.t.sol` ever asserted the revert (`grep -rln MustMintToday test/ --include='*.t.sol'` → only the new V56SubHardening, which asserts it does NOT revert). So the 134→133 forge-count delta is variance within the documented non-deterministic Bucket A (VRF/RNG-window) + Bucket F (flaky `invariant_solvencyUnderDegenerette`) + `vm.assume`-exhaustion (`testFuzz_RngLockDeterminism_StakedStonkRedemption`) cluster that the ledger §4/§6 ⊆-gate rationale already accounts for. The binding subset gate is the load-bearing property and it HOLDS.
- **Used `ContractAddresses.CREATOR` for the vault-owner routing proof** — the forge fixture mints 100% DGVE to CREATOR (also a permanent deity holder → always bounty-eligible), so `vault.gameAdvance()` (owner-gated) is pranked as CREATOR; `sdgnrs.gameAdvance()` is permissionless.
- **The bountyEligible truth-table proof settles clean first** so `dailyIdx >= 1` — the `gateIdx == 0` first-day branch returns `true` for everyone (nothing to earn against yet), which would mask the per-tier checks.

## Deviations from Plan

The plan body was written against HEAD' (the first gate). The orchestrator EXTENDED it to cover HEAD'' (the second gate, the advance-incentive redesign). All three tasks were executed against HEAD'' per the orchestrator's extension brief. This is an execution-context extension, not a deviation in the auto-fix sense.

### Out-of-scope discovery (logged, NOT fixed)

**1. [Scope boundary] Pre-existing `GovernanceGating ADMIN-02` red — stale `gameSetAutoRebuy` fixture**
- **Found during:** Task 1 (running the GovernanceGating Hardhat suite)
- **Issue:** `ADMIN-02 > multiple vault-owner-gated functions all check DGVE majority` calls `vault.connect(alice).gameSetAutoRebuy(true)`, but `gameSetAutoRebuy` no longer exists on `DegenerusVault` → `TypeError: ... is not a function`. This is in the UNTOUCHED `ADMIN-02` block (my edits are at lines 446+); it fails independently of the GATE rewrite at HEAD''.
- **Action:** NOT fixed (SCOPE BOUNDARY — only auto-fix issues directly caused by the current task). Logged to `357.../deferred-items.md`. Hardhat tests are a separate runner, not part of the forge NON-WIDENING ledger, so this does not affect `live − union == ∅`.

---

**Total deviations:** 0 auto-fixed; 1 out-of-scope item logged to deferred-items.md.
**Impact on plan:** None on the NON-WIDENING gate or the contract freeze. All 3 tasks GREEN.

## Issues Encountered

- **`testBountyEligibleTruthTable` initially red** ("fresh non-minter <15min: ineligible" failed) — the test did not settle past the genesis day, so `dailyIdx == 0` made `_bountyEligible` return `true` via the first-day branch. Fixed by settling clean first (so `dailyIdx >= 1`) before the truth-table assertions. Re-ran → GREEN.
- **The HEAD'' `MustMintToday`-consumer question** — resolved by grep: the hard-revert was Hardhat-only (GovernanceGating), so the forge narrowing is variance, not a phantom fixture flip.

## Threat Flags

None. This plan introduces no contract code; the HEAD'' surface (advanceGame liveness + bountyEligible soft pay-gate + Vault/sDGNRS→mintBurnie) is PROVEN, not modified. The drainAffiliateBase reachability carried-finding (§7b) was RESOLVED at HEAD' (§8d) and stays GREEN at HEAD''.

## Next Phase Readiness

- The audit subject is re-frozen at HEAD'' `61315ecd`. 357-01 (delta-audit) ∥ 357-02 (sweep) run READ-ONLY against it.
- The NON-WIDENING ledger §9 + the V56SubHardening soft-gate proofs are the regression/behavior gate the downstream delta-audit consumes.
- The 357-01 delta-audit must attribute the HEAD'' redesign hunks (advanceGame liveness / `_bountyEligible` / mintBurnie soft-gate / `bountyEligible` view / Vault+sDGNRS→mintBurnie) NON-WIDENING vs `453f8073`, with SOLVENCY-01 byte-unchanged re-confirmed (§9f).

## Self-Check: PASSED

- `test/unit/GovernanceGating.test.js` — FOUND (modified; 6/6 GATE tests GREEN)
- `test/fuzz/V56SubHardening.t.sol` — FOUND (17/17 GREEN)
- `test/REGRESSION-BASELINE-v56.md` — FOUND (§9 reconciled to HEAD'')
- Commit `056e78c8` — FOUND
- Commit `1d5fd872` — FOUND
- Commit `48fab561` — FOUND
- `git diff 61315ecd HEAD -- contracts/` — EMPTY (subject re-frozen at HEAD'')

---
*Phase: 357-terminal-delta-audit-3-skill-genuine-parallel-adversarial-sw*
*Completed: 2026-06-03*
