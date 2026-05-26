---
phase: 327-tst-repro-same-results-no-arb-ev-regression-proofs
plan: 02
subsystem: testing
tags: [foundry, redemption, steth-fallback, invariant, solvency, sdgnrs, afking, RFALL, POOL]

# Dependency graph
requires:
  - phase: 326-impl-the-one-batched-contract-diff-all-7-items
    provides: "RFALL fix (pure-ETH-OR-pure-stETH pullRedemptionReserve, RFALL-01/02/03) + POOL receive() AF_KING relaxation (POOL-02/03) — the applied Phase-326 diff this plan proves"
  - phase: 325-spec-design-lock-call-graph-attestation-shared-surface-recon
    provides: "325-ATTEST-PFIX-RFALL §B anchors (pullRedemptionReserve, totalMoney 4-term base, _payEth fallback) + 325-ATTEST-KEEP-POOL receive() accounting-safety SPEC check"
provides:
  - "test/fuzz/RedemptionStethFallback.t.sol — 10 deterministic scenario tests (6 RFALL05 + 4 POOL04)"
  - "RedemptionHandler.action_toggleStethFallback lever + leg-attribution ghosts (drives the stETH leg / fail-closed branch in the bounded random walk)"
  - "invariant_RFALL05_SolvencyUnderFallback (balance+stETH >= claimablePool AND >= pendingRedemptionEthValue AND >= sum unresolved-day MAX(175%))"
  - "test_RFALL05Handler_ReachesStethLeg reach-proof (stETH leg + fail-closed branch provably exercised)"
affects: [327-06 full-suite regression gate, 328 TERMINAL delta-audit + adversarial sweep]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Branch-taken proof: each stETH-leg test asserts game ETH (or claimable) < maxIncrement BEFORE the pull AND claimable[SDGNRS]/claimablePool UNCHANGED AFTER — proving the stETH leg ran, not the ETH leg (mitigates T-327-02-FC1 false-confidence)"
    - "Non-widening fallback lever: pre-fund sDGNRS OWN ETH backing up front so the v47 ETH-only solvency invariant still holds while the stETH leg increments pendingRedemptionEthValue without an ETH move"
    - "Lever reach-proof: a deterministic standalone test asserts ghost_stethLegBurns > 0 AND ghost_failClosedReverts > 0, since invariant_* runs reset state and cannot expose ghost counters"

key-files:
  created:
    - "test/fuzz/RedemptionStethFallback.t.sol"
  modified:
    - "test/fuzz/handlers/RedemptionHandler.sol"
    - "test/invariant/RedemptionAccounting.t.sol"

key-decisions:
  - "stETH-leg lever drives the branch by draining the GAME's liquid ETH (so the ETH leg's address(game).balance >= amount check fails), NOT by starving sDGNRS — keeps the v47 ETH-only invariant valid while reaching the new branch"
  - "POOL-04 live-balance proof uses previewBurn delta == floor(credit*amount/supply) for the exactly-once check (a double-count would yield ~2x the delta)"
  - "fail-closed (d) seeds the submit base from claimable[SDGNRS] (totalMoney > 0 -> maxIncrement > 0) while game LIQUID ETH = 0 and sDGNRS stETH = 0 — proving claimable alone is NOT a coverage leg (the ETH leg also requires game liquid ETH)"

patterns-established:
  - "Deterministic per-branch redemption scenario harness (mirrors StakedStonkRedemption.t.sol seeding: vm.deal(game), slot-7 claimable[SDGNRS], slot-1 upper-128 claimablePool, MockStETH.mint(sdgnrs) for the fallback backing)"

requirements-completed: [RFALL-05, POOL-04]

# Metrics
duration: 38min
completed: 2026-05-26
---

# Phase 327 Plan 02: RFALL stETH-Fallback + POOL receive() Accounting-Safety Proofs Summary

**The F-47-02 pure-ETH-OR-pure-stETH redemption reservation preserves every v47 REDEEM-08 invariant under stETH coverage (mid-game ETH depletion + stETH donation + fail-closed), and the sDGNRS receive() AF_KING relaxation is proven accounting-safe — all against the applied Phase-326 diff with zero contract edits.**

## Performance

- **Duration:** ~38 min
- **Tasks:** 3 (all autonomous)
- **Files modified:** 3 (1 created, 2 extended)

## Accomplishments
- **RFALL-05 scenario proofs (6 tests)** that DRIVE each `pullRedemptionReserve` branch and re-assert solvency throughout.
- **RFALL-05 invariant extension** — a stETH-fallback lever in the bounded random walk + a new solvency invariant that holds under the fallback, with all v47 INV-01..13 + 3 REDEEM-08 invariants preserved (non-widening), green at `FOUNDRY_PROFILE=deep` (1000 runs × 256000 calls).
- **POOL-04 accounting-safety proofs (4 tests)** — live-balance read (no running counter), exactly-once counting, non-GAME/non-AF_KING revert, and zero-pool-token-safe gameover recovery.

## Branch each RFALL05 test proved was taken

| Test | Branch driven | Branch-taken proof |
|------|---------------|--------------------|
| `test_RFALL05_EthLeg_HappyPath` | **ETH leg** | claimable[SDGNRS] AND claimablePool each debited by EXACTLY maxIncrement; maxIncrement ETH lands in sDGNRS balance |
| `test_RFALL05_StethFallback_MidGameEthDepletion` | **stETH leg** | game ETH = 0 < maxIncrement BEFORE the pull; claimable[SDGNRS]/claimablePool/game-ETH/sDGNRS-ETH UNCHANGED after; pendingRedemptionEthValue +maxIncrement; **claim pays stETH** (ethPaid == 0, stethPaid > 0; sDGNRS stETH decreases by exactly the direct payout) |
| `test_RFALL05_DonationRobust_StethForceFeed` | **stETH leg (donated basis)** | 500-ETH stETH donation force-fed to sDGNRS; submit does NOT brick with claimable = 0 and game ETH = 0; no ledger debit; coverage checked against `steth.balanceOf(SDGNRS)` |
| `test_RFALL05_FailClosed_NeitherLegCovers` | **fail-closed revert** | game liquid ETH = 0 + sDGNRS stETH = 0 + claimable seeds a positive base → `vm.expectRevert`; claimablePool / claimable[SDGNRS] / pendingRedemptionEthValue / sDGNRS supply all byte-identical (no leaked state, burn unwound) |
| `test_RFALL05_TwoSamePeriodClaimants_BothPaid` | **ETH leg (A) + stETH leg (B), same period** | A debits claimable; B (game drained between submits) leaves claimable/pool at 0 with no underflow; both claim a positive rolled payout; no wrap of claimable/pool |
| `test_RFALL05_BurnieCannotBlockEth` | **stETH leg + depleted coinflip** | `claimCoinflipsForRedemption` mock returns 0 (BURNIE delivers nothing) yet the ETH-value (stETH) claim still pays the player |

Every RFALL05 test asserts `address(sdgnrs).balance + steth.balanceOf(sdgnrs) >= claimablePool` AND `>= pendingRedemptionEthValue` at each step.

## Donation / force-feed mechanism
`MockStETH.mint(address(sdgnrs), amount)` directly credits sDGNRS's stETH share balance (the mock's test helper), simulating both a held-stETH backing (b/e/f) and a donation/selfdestruct-style force-feed (c, 500 ETH). The donation-robustness check is against `steth.balanceOf(SDGNRS)` — the same basis the donation inflated, so the inflated base can never brick submit.

## New invariant name + preserved INV count
- New: **`invariant_RFALL05_SolvencyUnderFallback`** — asserts (1) `balance + stETH >= pendingRedemptionEthValue`, (2) `claimablePool >= claimableWinnings[SDGNRS]`, (3) `backing >= sum of unresolved-day MAX(175%) reservations`, after every handler action.
- Preserved: **13 INV-01..13 + 3 pre-existing REDEEM-08 invariants** (incl. the v47 ETH-only `invariant_balanceCoversPendingRedemptionEth`) — all still green, none weakened or deleted. Deep profile result: **18 passed / 0 failed** (17 invariants + 1 reach-proof).
- Reach-proof: **`test_RFALL05Handler_ReachesStethLeg`** asserts `ghost_stethLegBurns > 0` AND `ghost_failClosedReverts > 0`, proving the lever exercises the stETH-fallback AND fail-closed branches (not only the ETH leg).

## POOL-04 double-count assertion result
`test_POOL04_AfKingCreditNotDoubleCounted`: after a 10-ETH AF_KING-gated `receive()` credit, the `previewBurn` ethOut delta equals **exactly** `floor(credit × BURN_AMOUNT / totalSupply)` (the credit's single proportional share). A double-count (counter + balance both read) would yield ~2× this delta — assertion `assertEq(actualDelta, expectedDelta)` PASSED, confirming the credit is counted once. `test_POOL04_ReceiveReadsLiveBalance_NoRunningCounter` independently confirms the submit base MOVES with the credit (live read, not a stale counter).

## Task Commits

1. **Task 1 (RFALL-05 scenario) + Task 3 (POOL-04) tests** — `141244c3` (test) — both live in `test/fuzz/RedemptionStethFallback.t.sol` (single file per the plan).
2. **Task 2: RFALL-05 invariant extension** — `a83b5ca4` (test) — handler lever + new invariant + reach-proof.

## Files Created/Modified
- `test/fuzz/RedemptionStethFallback.t.sol` — 10 deterministic tests (6 RFALL05 branch-drivers + 4 POOL04 accounting-safety).
- `test/fuzz/handlers/RedemptionHandler.sol` — `action_toggleStethFallback` lever, `MockStETH` wiring (`setStethMock`), leg-attribution + fail-closed ghost counters.
- `test/invariant/RedemptionAccounting.t.sol` — `invariant_RFALL05_SolvencyUnderFallback`, 6th selector registration, `test_RFALL05Handler_ReachesStethLeg` reach-proof, `_sdgnrsSteth` reader.

## Decisions Made
See key-decisions in frontmatter. No architectural decisions; all within the test-authoring envelope.

## Deviations from Plan
None - plan executed exactly as written. No contract defects surfaced; every branch behaves as the Phase-326 diff and 325 attestation specified.

## Issues Encountered
None. The only non-obvious design point was keeping the v47 ETH-only solvency invariant (`invariant_balanceCoversPendingRedemptionEth`) valid while adding the stETH-leg lever: solved by draining the GAME's liquid ETH (not sDGNRS's) to fail the ETH leg, and pre-funding sDGNRS's OWN ETH backing so its balance always covers `pendingRedemptionEthValue` regardless of which leg ran.

## Verification

- **Gate 1:** `forge test --match-path test/fuzz/RedemptionStethFallback.t.sol` → 10 passed / 0 failed (exit 0).
- **Gate 2:** `FOUNDRY_PROFILE=deep forge test --match-path test/invariant/RedemptionAccounting.t.sol` → 18 passed / 0 failed (exit 0); new fallback invariant present + all INV-01..13 preserved.
- **Gate 3:** stETH leg / fail-closed revert / donation force-feed / two-same-period-claimant cases each explicitly proven to be the branch taken (table above + reach-proof).
- **Gate 4:** `git status --porcelain contracts/ | grep -v '/test/'` → empty (zero mainnet `contracts/*.sol` modifications).

## Threat Flags
None — no new security-relevant surface introduced (test-authoring only; subject FROZEN at the Phase-326 diff).

## Known Stubs
None — no placeholder/stub patterns; all tests drive live contract paths with real assertions.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- RFALL-05 + POOL-04 fully proven; ready to feed the 327-06 full-suite regression gate and the Phase 328 TERMINAL delta-audit + adversarial sweep.
- No blockers. HERO-04 contract-landing decision (327-04) is unrelated to this plan.

## Self-Check: PASSED
- Files: test/fuzz/RedemptionStethFallback.t.sol, test/fuzz/handlers/RedemptionHandler.sol, test/invariant/RedemptionAccounting.t.sol, 327-02-SUMMARY.md — all FOUND.
- Commits: `141244c3` (Task 1+3), `a83b5ca4` (Task 2) — both FOUND.

---
*Phase: 327-tst-repro-same-results-no-arb-ev-regression-proofs*
*Completed: 2026-05-26*
