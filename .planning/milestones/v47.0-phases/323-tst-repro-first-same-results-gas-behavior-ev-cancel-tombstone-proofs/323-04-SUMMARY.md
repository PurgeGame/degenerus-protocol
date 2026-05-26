---
phase: 323-tst-repro-first-same-results-gas-behavior-ev-cancel-tombstone-proofs
plan: 04
subsystem: testing
tags: [foundry, forge, degenerette, dgas, dspin, same-results, gas-worst-case, write-batching, event-replay]

requires:
  - phase: 322-impl-the-one-batched-contract-diff-all-7-items
    provides: "the frozen v47.0 DegeneretteModule subject at fb29ed51 (resolveBets cross-bet ResolveAcc write-batching; per-currency spin caps ETH 25 / BURNIE 15 / WWXRP 5)"
  - phase: 323-tst-repro-first-same-results-gas-behavior-ev-cancel-tombstone-proofs
    plan: 01
    provides: "a compiling foundry tree + the classified v47 baseline (the precondition for this proof plan)"
provides:
  - "DGAS-05 same-results proof: the Degenerette write-batching is payout byte-identical to a per-spin baseline (Tier-1 additive + Tier-2 running-pool-local cap on the IDENTICAL spin + per-betId lootbox + per-spin DGNRS)"
  - "DSPIN-02 derived-then-measured 25-spin ETH worst case (485,089 gas) + max mixed-currency batch (619,349 gas) — both absorbed far under the 30M mainnet block gas limit; absorption proven (25-spin < 2.5x the 10-spin)"
  - "Grep-verified re-classification of the 7 failures 323-01 speculatively tagged DGAS/DSPIN: 6 are presale/rake economics + 1 is redemption, all OUTSIDE R5 / this plan's file scope"
affects: [324-terminal]

tech-stack:
  added: []
  patterns:
    - "Event-replay same-results proof: the per-spin baseline is computed IN THE TEST from the contract's own per-spin FullTicketResult events (the raw per-spin payout), replaying ONLY the arithmetic the batching changed (3-tier ETH split + running-pool-local cap) — the per-N payout TABLES are unchanged by the batching and are NOT recomputed (avoids a fragile re-derivation)"
    - "Snapshot equivalence for the resolution-batch-invariant: vm.snapshotState/revertToState resolves the SAME placed bets one-call vs two-call to prove the lootbox is per-betId (one-call == two-call ETH credited), without a circular `new`-self instance"
    - "Identical-spin cap mapping: a PayoutCapped immediately follows the spin's FullTicketResult it caps (DegeneretteModule:690-712), so a single log pass maps the ON-CHAIN cap-flip set to spin indices and asserts it == the off-chain running-pool-local replay"
    - "Per-spin (path-dependent) DGNRS draining proof: _awardDegeneretteDgnrs reads poolBalance fresh per spin -> the per-spin sum is strictly < a single-read batch sum; the strict-less assertion proves it was NOT folded into the cross-bet flush"
    - "Derive-then-measure worst case with statistical-reachability fallback: all-25-win on a single fixed ticket is unreachable, so the search MAXIMIZES the winning-spin count (21/25); the 25-iteration loop is the structural gas driver regardless"

key-files:
  created:
    - .planning/phases/323-.../323-04-SUMMARY.md
  modified:
    - test/fuzz/DegeneretteFreezeResolution.t.sol
    - test/gas/CrankResolveBetWorstCaseGas.t.sol
    - .planning/phases/323-.../deferred-items.md

key-decisions:
  - "Same-results baseline computed from the contract's own per-spin FullTicketResult events (not a re-derivation of the per-N payout tables) — the batching only changed the AGGREGATION, so the proof replays exactly the aggregation arithmetic to the wei"
  - "All-25-spin-win is statistically unreachable for a single fixed customTicket (25 independent random result tickets) -> the 25-spin worst case MAXIMIZES winning+cap-flip spins (21/25 achieved); the full 25-iteration loop is the structural gas driver, the achieved cap count is asserted for non-vacuity"
  - "The 3 stale FIX-04 freeze tests were repaired non-widening (v47 always-on hero: 0xFF -> 0; packedTraitsFromSeed -> packedTraitsDegenerette) — same freeze-routing intent against the v47 signature"
  - "The 7 failures 323-01 tagged DGAS/DSPIN re-classified via grep: 6 (5 solvency invariants + VRFLifecycle) are presale/rake prize-pool economics with ZERO Degenerette refs; 1 (RngLockDeterminism StakedStonkRedemption) is REDEEM-08/323-03. Outside this plan's file scope per the SCOPE BOUNDARY rule; logged to deferred-items.md, not touched"

patterns-established:
  - "Prove a gas-only refactor on real-money payout logic by replaying the contract's OWN per-spin emissions through the changed aggregation arithmetic — proves byte-identical output without trusting (or recomputing) the unchanged payout core"

requirements-completed: [DGAS-05, DSPIN-02]

metrics:
  duration: ~2h
  tasks: 2
  files: 2
completed: 2026-05-25
---

# Phase 323 Plan 04: DGAS-05 Same-Results + DSPIN-02 Worst-Case Gas Summary

**Proved the v47 Degenerette `resolveBets` write-batching is payout byte-identical to a per-spin baseline (DGAS-05) and that the raised 25-spin ETH cap's worst case (485,089 gas) is absorbed far under the 30M block limit (DSPIN-02) — subject FROZEN at `fb29ed51`, zero `contracts/*.sol` edits, no defect surfaced.**

## Performance
- **Duration:** ~2h
- **Tasks:** 2/2
- **Files modified:** 2 foundry test files (`test/**` only; zero `contracts/*.sol` mainnet edits)

## DGAS-05 — same-results (byte-identical to per-spin), `test/fuzz/DegeneretteFreezeResolution.t.sol`

The per-spin baseline is computed IN THE TEST from the contract's own per-spin `FullTicketResult`
events (the raw per-spin payout the contract computed), replaying ONLY the arithmetic the
batching changed (the 3-tier ETH split + the running-pool-local cap). The per-N payout TABLES
are unchanged by the batching, so they are NOT recomputed — the proof targets the AGGREGATION,
which is the only thing R5 touched. Any divergence by one wei would be surfaced, never adjusted.

| Test | What it proves | Result |
|------|----------------|--------|
| `testBatchedPayoutEqualsPerSpinExpectation_Tier1` | **Tier-1 additive**: mixed-currency batch (ETH 4-spin + BURNIE 3-spin + WWXRP 2-spin). BURNIE mint delta == Σ BURNIE-spin payouts; WWXRP mint delta == Σ WWXRP-spin payouts; ETH claimable delta == Σ ETH-spin ethShare; **claimablePool moved by exactly the ETH sum** (additive, disjoint slot). Byte-identical (==). 0 PayoutCapped (large pool). | PASS |
| `testEthCapBindsOnIdenticalSpin_Tier2` | **Tier-2 unfrozen**: small pool, 6-spin ETH bet. ETH credited == Σ per-spin capped shares against the shrinking running-pool local; **PayoutCapped fires on the IDENTICAL spin set** the off-chain replay predicts (2/6 spins capped). | PASS |
| `testFrozenSolvencyRevertsOnIdenticalSpin_Tier2` | **Tier-2 frozen**: trims `pendingFuture` below the first spin's ethShare -> the frozen solvency check reverts `E()` on the IDENTICAL (first) spin the replay predicts; live future untouched. | PASS |
| `testLootboxSummedPerBetIdNotAcrossBets` | **DGAS-03 per-betId**: two same-index single-spin bets. One-call resolve (2 FullTicketResolved + 2 PayoutCapped) == two-call resolve ETH credited (snapshot/revert). The box is per-betId, never pooled across bets (a summed-across box would diverge — the box roll is non-linear in `amount`). | PASS |
| `testDgnrsAwardStaysPerSpin` | **DGAS-04 per-spin**: all-6+-match ETH bet. sDGNRS gain == the per-spin DRAINING sum (pool read fresh + decremented each spin) AND **strictly < a single-read batch sum** — proving the DGNRS award was NOT folded into the cross-bet flush. | PASS |

Plus the 3 pre-existing FIX-04 freeze-routing tests (repaired non-widening): all PASS.
**8/8 in this file.** RNG/freeze untouched is implicit in the byte-identical Tier-1/Tier-2 payouts
(the per-spin result seed feeds the `FullTicketResult.payout` the replay consumes).

Tier-1 evidence (logged): `tier1_eth_claimable_delta = 727993896480000000000` (== claimablePool
delta), `tier1_burnie_delta = 19361539800000000000000000`, `tier1_wwxrp_delta = 193615398000000000000000`.
Tier-2 evidence: `tier2_eth_credited = 95000000000000000`, `tier2_spins_capped = 2`.
Per-betId: `perbetid_eth_one_call == perbetid_eth_two_calls = 95000000000000000`.
DGNRS: `dgnrs_per_spin_sum = 9.2e27 < dgnrs_batched_hypothetical = 9.5e27`.

## DSPIN-02 — derived-then-measured worst case, `test/gas/CrankResolveBetWorstCaseGas.t.sol`

**DERIVED in writing (Test C NatSpec, before measuring):** the single most expensive `resolveBets`
item is ONE ETH bet at `ticketCount == MAX_SPINS_ETH == 25` where every winning spin flips into the
lootbox branch (25 PayoutCapped + one per-bet `_resolveLootboxDirect` on the summed share) — 2.5×
the old 10-spin roll work. Offsetting savings: the single end-of-call flush replaces up to 25
per-spin `_addClaimableEth` + 25 prize-pool writes with ONE of each, and the box rolls once per bet.
Plus a max mixed-currency batch (ETH 25 + BURNIE 15 + WWXRP 5 = 45 spins, 3 currencies, one call).

**MEASURED:**

| Test | Spins | Measured gas | % of 30M | Result |
|------|-------|--------------|----------|--------|
| `testWorstCaseResolveBet25SpinAllMatchFitsBlockGasLimit` | 25 ETH (21 winning + cap-flip) | **485,089** | 1.6% | PASS |
| `testWorstCaseMixedCurrencyBatchGas` | 45 (25+15+5) | **619,349** | 2.1% | PASS |
| (reference) legacy 10-spin all-win | 10 ETH | 197,183 | 0.7% | PASS |

**Absorption proven:** `485,089 < 2.5 × 197,183 (= 492,958)` — the 25-spin cost is below a naive
2.5× of the 10-spin worst case, demonstrating the single-flush write savings absorb the raised cap.
~62× headroom under the 30M block limit. **No block-limit overflow → no finding.**

**Statistical-reachability note:** an all-25-win single fixed ticket is statistically unreachable
(25 independent random result tickets), so the worst case MAXIMIZES the winning-spin count (21/25
achieved + all 21 cap-flip). The full 25-iteration spin loop is the structural gas driver regardless
of per-spin win/loss; the achieved cap count is asserted for non-vacuity. The legacy 10-spin Test A
(all-win) + Test B (per-1-spin marginal, the Phase-319 CRANK_RESOLVE_BET_GAS_UNITS calibration
target) are kept intact as references; this plan MEASURES only (no peg calibration — Phase 319's job).

## In-scope v47-delta failures — resolved + re-classified

**Resolved (in my file scope):** the 3 stale FIX-04 freeze tests in
`DegeneretteFreezeResolution.t.sol` were failing with `InvalidBet()` (v47 always-on hero rejects
`heroQuadrant == 0xFF`; `_findWinningCombo` used the wrong trait derivation `packedTraitsFromSeed`
instead of `packedTraitsDegenerette`). Repaired non-widening (same freeze-routing intent against the
v47 signature) + fixed stale slot docstrings. All 3 PASS.

**Re-classified (OUTSIDE my file scope — grep-verified, logged to `deferred-items.md`):** 323-01
speculatively tagged 7 failures "DGAS/DSPIN (323-04)". On inspection their root cause is the v47
**rake-removal / presale-box prize-pool economics** (6) or **redemption** (1), NOT the Degenerette
write-batching (R5). All six non-`DegeneretteBet` files have **ZERO** `Degenerette/resolveBets`
references; `VRFLifecycle` has 7 presale/prizePool refs. Since the DGAS-05 proof shows the batching
is byte-identical (changes no payout), these solvency/economic failures cannot stem from it.

| Failure | Real owner |
|---------|-----------|
| `EthSolvency` / `MultiLevel` / `VaultShareMath` / `WhaleSybil` (5 solvency invariants, incl. `DegeneretteBet::invariant_solvencyUnderDegenerette` — fail driver is `GameHandler::advanceGame`) | PRESALE/rake economics re-verify (Phase 324 sweep) |
| `RngLockDeterminism::testFuzz_RngLockDeterminism_StakedStonkRedemption` (sStonk burn assume-window) | REDEEM-08 / 323-03 |
| `VRFLifecycle::test_vrfLifecycle_levelAdvancement` (presale lootbox-split prize-pool accumulation) | PRESALE economics re-verify |

Per the SCOPE BOUNDARY rule (only auto-fix issues directly caused by the current task's changes),
these files OUTSIDE `files_modified` were not touched.

## Contract defects surfaced
**None.** The write-batching is byte-identical to the per-spin baseline (Tier-1 additive + Tier-2
identical-spin cap, unfrozen + frozen), the lootbox is per-betId, the DGNRS award is per-spin, and
the 25-spin worst case fits the block limit with ~62× headroom. No `contracts/*.sol` (mainnet) file
was edited; the subject stays frozen at `fb29ed51`. No assertion was weakened to dodge a divergence;
no expected value was adjusted to match the batched output.

## Task Commits
1. **Task 1 — DGAS-05 same-results proof** — `39807240` (test)
2. **Task 2 — DSPIN-02 25-spin worst-case gas** — `b74ff527` (test)

## Deviations from Plan

### In-scope failure handling (plan coverage_target 3)
- **[Repair] 3 stale FIX-04 freeze tests** in `DegeneretteFreezeResolution.t.sol` — the plan's
  Task 1 added 4 new tests to this file; running the file surfaced that its 3 PRE-EXISTING tests
  failed against v47 (always-on hero `0xFF` + wrong trait fn). Repaired non-widening as part of
  authoring the file (the file must be green end-to-end). Attributable to v47 deltas.
- **[Re-classification, not repair] 7 speculatively-tagged failures** — the plan's coverage_target 3
  said "update OR surface" the in-scope v47-delta failures. After grep-verifying these 7 are
  presale/rake economics (6) or redemption (1) — NOT R5 DGAS/DSPIN and OUTSIDE `files_modified` —
  they were re-classified to their true owners and logged to `deferred-items.md` rather than touched
  (SCOPE BOUNDARY rule). None is a contract defect.

### Approach note
- The same-results baseline is computed from the contract's own per-spin `FullTicketResult` events
  (replaying only the changed aggregation arithmetic), NOT by re-deriving the per-N payout tables.
  This is the rigorous way to prove a gas-only AGGREGATION refactor is byte-identical without
  trusting/recomputing the unchanged payout core — and it makes a one-wei divergence impossible to
  hide (the assertion is `==`, against the contract's own emitted per-spin payouts).

## Self-Check: PASSED
- `test/fuzz/DegeneretteFreezeResolution.t.sol` exists — verified (8/8 PASS).
- `test/gas/CrankResolveBetWorstCaseGas.t.sol` exists — verified (4/4 PASS).
- Both task commits exist (`39807240`, `b74ff527`) — verified in `git log`.
- Zero `contracts/*.sol` (mainnet) modifications — verified (`git status` shows only test files).
- All 12 tests across both files PASS; no regression in Degenerette/crank contracts.
