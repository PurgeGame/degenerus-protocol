---
phase: 327-tst-repro-same-results-no-arb-ev-regression-proofs
plan: 05
subsystem: testing
tags: [foundry, no-arb, salvage-swap, sDGNRS, jitter-ceiling, solvency, far-future, swap-pop]

# Dependency graph
requires:
  - phase: 325-spec-design-lock-call-graph-attestation-shared-surface-recon
    provides: "325-ATTEST-SWAP.md — locked no-arb ceiling figures (16.5%@d6, 21% acquisition floor, +4.5pp margin), BURNIE-can't-mint-far enumeration, swap-pop consumer table"
  - phase: 326-impl-the-one-batched-contract-diff-all-7-items
    provides: "applied SWAP contract diff (sellFarFutureTickets in MintModule, _quoteFarFutureSwap/_farFutureFractionBps in MintStreakUtils, previewSellFarFutureTickets view, _removeFarFutureTickets swap-pop)"
provides:
  - "test/fuzz/FarFutureSalvageSwap.t.sol — empirical proof of the SWAP no-arb ceiling + solvency + floors + array bound + swap-pop membership"
  - "SWAP-08 empirical: no-arb holds at the 110% jitter CEILING for ALL d in [6,100]; d6 binding margin +4.50pp; ceiling proven seed-reachable; BURNIE can't mint far (behavioral, no ffi)"
  - "SWAP-09 empirical: solvency claimablePool <= balance + stETH holds across the swap; ticket/ETH floors + len<=32 + swap-pop membership all enforced"
affects: [327-06-regression-gate, 328-terminal, v48-closure]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "No-arb proven at the JITTER CEILING (not the mean): search rngWordByDay[day-1] for the word that drives jitterMult to its 11000 (110%) max, then sweep every distance"
    - "Valuation proven via previewSellFarFutureTickets (shares _quoteFarFutureSwap with the executing path) so the asserted offer cannot drift from the paid offer"
    - "Far-future ticket seeding via vm.store into ticketsOwedPacked (packed = owed<<8|rem) + manual ticketQueue append (length slot + keccak data slot)"
    - "BURNIE-can't-mint-far proven BEHAVIORALLY (ffi disabled): snapshot all far queue lengths, drive purchaseCoin, assert no far queue grew"

key-files:
  created:
    - test/fuzz/FarFutureSalvageSwap.t.sol
  modified: []

key-decisions:
  - "No-arb proven empirically AT the 110% jitter ceiling via previewSellFarFutureTickets (shared valuation), swept over all d in [6,100]; d6 is the binding case at exactly 1650 bps (16.50% of face)"
  - "Reused the existing far-future seeding approach (vm.store into ticketsOwedPacked + ticketQueue) established by FarFutureIntegration.t.sol; storage slots confirmed via forge inspect (claimable=7, rngWordByDay=10, ticketQueue=12, ticketsOwedPacked=13)"
  - "BURNIE-can't-mint-far proven behaviorally (purchaseCoin has no level arg; a BURNIE mint never grows any far queue) — vm.ffi is disabled in foundry.toml, so no runtime source grep was used"

patterns-established:
  - "Jitter-ceiling no-arb pattern: derive the contract's exact jitter formula in the test, search for the ceiling seed, set rngWordByDay[day-1], then prove the worst-case payout fraction < the acquisition floor"
  - "Solvency-across-swap pattern: snapshot claimablePool vs (balance + stETH) before/after; ticket leg routes ETH into pools (slack gain), cash leg is a claimant relabel (neutral)"

requirements-completed: [SWAP-08, SWAP-09]

# Metrics
duration: 22min
completed: 2026-05-26
---

# Phase 327 Plan 05: SWAP No-Arb-at-Ceiling + Solvency Empirical Proofs Summary

**Made the load-bearing 325-ATTEST-SWAP paper proof EMPIRICAL: the salvage-swap no-arb floor holds at the 110% jitter CEILING for every distance d in [6,100] (d6 binding margin +4.50pp), the ceiling is proven seed-reachable, BURNIE cannot mint a far entry (behavioral, no ffi), and the swap is solvency-safe with all floors / the array bound / the swap-pop membership invariant enforced — all against the frozen Phase-326 diff.**

## Performance

- **Duration:** ~22 min
- **Started:** 2026-05-26T09:33Z
- **Completed:** 2026-05-26
- **Tasks:** 2
- **Files modified:** 1 (created)

## Accomplishments

- **SWAP-08 no-arb at the CEILING (the milestone's economic-security headline):** drove the jitter to its 110% maximum (jitterMult = 11000) for the seller and swept EVERY distance d in [6,100]. At each d the salvage payout fraction (via `previewSellFarFutureTickets`, which shares `_quoteFarFutureSwap` with the executing path) is strictly below the 21%-of-face acquisition floor. The binding case is d6 at exactly **1650 bps (16.50% of face)**, margin **+4.50pp** (>= the +4.0pp gate). Any violation FAILS the test (no band-widen) — the `## STOP` rule is wired into the assertion message.
- **SWAP-08 ceiling reachability (anti-false-confidence):** proved the 110% ceiling is the TRUE seed-reachable maximum — across a 50k-seed band the jitter multiplier never exceeds 11000 and DOES reach 11000 (and the 70% floor is reachable too). So the no-arb ceiling proven above is a value the contract actually produces, not an unreachable bound.
- **SWAP-08 base-fraction margin:** the base `fractionBps(d)` (mean/100% jitter) equals 15%/10%/5% at d6/d20/d100 and keeps >= 10% margin below the far ticket's present EV (full face); even the 110% ceiling d6 (16.5%) leaves 83.5% below present EV.
- **SWAP-08 BURNIE-can't-mint-far (behavioral, no ffi):** snapshot all far-future queue lengths (current+6 .. current+100), drive a BURNIE `purchaseCoin` mint (which takes NO level/distance arg), and assert NO far queue grew and the buyer holds zero far entries at every distance. Proven by exercised behavior + the absence of any BURNIE-funded far entrypoint — never by a runtime source grep (`vm.ffi` is disabled in `foundry.toml`).
- **SWAP-09 solvency-across-swap:** with the ticket leg explicitly exercised (a 100-ticket d6 bundle, `ticketWei > 0`), `claimablePool <= address(game).balance + stETH` holds before AND after the swap; `claimablePool` moved 50.000 ETH → 49.828 ETH (ticket leg routed ETH into pools = gained slack vs 5000 ETH backing; cash leg is a claimant-to-claimant relabel). The seller received a cash residual and SDGNRS claimable dropped by the budget.
- **SWAP-09 floors + array bound + swap-pop:** ticket floor (too-small budget reverts; clearing it mints >= 1 whole ticket); >= 1 ETH redemption-desk floor (underfund reverts, exactly budget+1 ETH succeeds and leaves >= 1 ETH); `len==33` and mismatched lengths revert, `len==32` is accepted (32 distinct far lines all clear); swap-pop maintains `membership <=> packed != 0` (full sell-out pops, partial does not), the far-future sampler returns only live holders after the pop, and a stale `queueIndex` (`q[idx] != player`) reverts the line.

## Task Commits

Both tasks author one shared test file (Task 2 reuses Task 1's harness + slot helpers), committed atomically:

1. **Task 1 (SWAP-08) + Task 2 (SWAP-09): FarFutureSalvageSwap.t.sol** — `1a19fdbf` (test)

**Plan metadata:** _(this SUMMARY + STATE/ROADMAP/REQUIREMENTS)_ committed separately.

## Files Created/Modified

- `test/fuzz/FarFutureSalvageSwap.t.sol` — 9 Foundry tests: 4 SWAP-08 (no-arb ceiling sweep, ceiling reachability, base-fraction margin, BURNIE-can't-mint-far) + 5 SWAP-09 (solvency, ticket floor, ETH floor, array bound, swap-pop membership). Uses an `FFKeyHarness` (inherits `DegenerusGameStorage`) to expose `_tqFarFutureKey` and `vm.store` to seed far-future tickets / claimable / the prior-day jitter word.

## No-Arb Margin Table (empirically derived, 110% jitter CEILING)

| distance d | fractionBps(d) | max payout (bps of face) @ 110% | acquisition floor | margin |
|-----------|----------------|---------------------------------|-------------------|--------|
| 6 (binding) | 1500 (15.00%) | **1650 (16.50%)** | 2100 (21%) | **+4.50pp** |
| 7 | 1465 | 1611 | 2100 | +4.89pp |
| 20 | 1000 | 1100 | 2100 | +10.00pp |
| 100 | 500 | 550 | 2100 | +15.50pp |

The worst (binding) case across the full sweep is d6 at exactly 16.50% of face; the margin only widens for larger d. **No `## STOP — NO-ARB MARGIN VIOLATED` block — the no-arb floor HOLDS at the band ceiling for all d in [6,100].**

## Ceiling-Reachability Proof

Jitter multiplier `jitterMult = 7000 + (seed % 4001)` (seed = `keccak256(player, rngWordByDay[day-1])`). Across a 50k-seed band the realized multiplier stayed in `[7000, 11000]`, hit `11000` (110% ceiling) and `7000` (70% floor) — so the no-arb ceiling proven above is a genuinely reachable value, not an artifact.

## BURNIE-Can't-Mint-Far Behavioral-Probe Result

`purchaseCoin(buyer, ticketQuantity)` carries NO level/distance argument — the caller cannot direct the mint at a far level. A pranked BURNIE mint grew ZERO of the 95 far-future queues (current+6 .. current+100) and left the buyer with zero far entries at every distance, whether the mint landed or reverted. No BURNIE-funded entrypoint can place a d>=6 entry (the v47 BURNIE-lootbox→future path was removed in Phase 326). Proven BEHAVIORALLY — `vm.ffi` is disabled; no runtime source grep used.

## Solvency Before/After Deltas (SWAP-09(a))

- claimablePool before: **50.000 ETH** → after: **49.828 ETH** (ticket leg routed ~0.172 ETH of player claimable into prize pools = gained slack)
- backing (balance + stETH) after: **5000.000 ETH** — invariant `claimablePool (49.828) <= backing (5000)` holds with enormous headroom
- seller cash residual credited; SDGNRS claimable dropped by the full budget (claimant-to-claimant relabel = pool-neutral)

## Decisions Made

- No-arb proven via `previewSellFarFutureTickets` (the shared-valuation view) rather than executing the full swap for every distance — the view shares `_quoteFarFutureSwap` exactly with `sellFarFutureTickets`, so the asserted offer cannot drift from the paid offer, and it isolates the no-arb math cleanly across all 95 distances.
- Reused the established far-future seeding approach (vm.store into `ticketsOwedPacked` + manual `ticketQueue` append) from `FarFutureIntegration.t.sol`; storage slots confirmed via `forge inspect`.

## Deviations from Plan

None - plan executed exactly as written. The plan called for both tasks to modify the single file `test/fuzz/FarFutureSalvageSwap.t.sol`; Task 2's tests reuse Task 1's harness and slot helpers, so the file was authored as one unit and committed atomically (both task acceptance criteria are independently satisfied — all 9 tests pass).

## Issues Encountered

- Initial compile errors (3): a `try` on an internal function (changed the BURNIE mint to a low-level `address(game).call` after `vm.prank` so the buyer is the real `msg.sender`), and two `uint32`→`uint24` implicit conversions on `levels[i]` (added explicit `uint24(...)`). All resolved; no contract edits.

## Authentication Gates

None.

## Known Stubs

None — this is a test-authoring plan; no production stubs introduced.

## Next Phase Readiness

- SWAP-08 + SWAP-09 are proven EMPIRICALLY; the load-bearing no-arb attestation is now backed by a passing Foundry suite (9/9), not just the paper proof.
- Wave 1 of Phase 327 is the parallel test-authoring set; this plan (327-05 SWAP) is complete. Remaining: Wave 2 327-06 full-suite regression gate (which owns the cross-phase closure of the RED HERO-04 byte-reproduce gate from 327-04).
- No blockers from this plan. Zero `contracts/*.sol` (mainnet) modifications — subject FROZEN at the Phase-326 diff.

## Self-Check: PASSED

- FOUND: `test/fuzz/FarFutureSalvageSwap.t.sol`
- FOUND: `.planning/phases/327-tst-repro-same-results-no-arb-ev-regression-proofs/327-05-SUMMARY.md`
- FOUND: commit `1a19fdbf`
- `forge test --match-path test/fuzz/FarFutureSalvageSwap.t.sol` → 9/9 PASS, exit 0
- `git diff --name-only -- 'contracts/*.sol'` → empty (zero mainnet contract edits)

---
*Phase: 327-tst-repro-same-results-no-arb-ev-regression-proofs*
*Completed: 2026-05-26*
