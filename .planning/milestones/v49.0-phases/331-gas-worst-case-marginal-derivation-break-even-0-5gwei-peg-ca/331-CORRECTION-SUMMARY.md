---
phase: 331-gas-worst-case-marginal-derivation-break-even-0-5gwei-peg-ca
plan: correction-pass
subsystem: gas-calibration
tags: [gas, keeper-router, correction, buy-revert-catch, whale-pass, split-caps, faucet-floor, rngLock, doc+test]

# Dependency graph
requires:
  - phase: 331-gas-worst-case-marginal-derivation-break-even-0-5gwei-peg-ca
    plan: 01
    provides: "the original RouterWorstCaseGas.t.sol + 331-GAS-DERIVATION.md this pass corrects"
  - phase: 331-gas-worst-case-marginal-derivation-break-even-0-5gwei-peg-ca
    plan: 04
    provides: "the original 331-CALIBRATION.md (consumed the wrong buy marginal) this pass corrects"
provides:
  - "corrected test/gas/RouterWorstCaseGas.t.sol (buy verified via lootboxEthBase>0; whale-pass open test; 16.7M ceiling)"
  - "corrected 331-GAS-DERIVATION.md (buy ~262k / whale-pass ~5.4M / split-cap sizing) + 331-CALIBRATION.md (reward-ratio re-analysis; advance-6x still binding; buy under-reimbursement flag)"
  - "corrected 331-CONTEXT.md + flagged 331-01/331-04 SUMMARYs"
  - "the recommended split caps BUY_BATCH=50 / OPEN_BATCH=100 for the gated 331-05"
affects: [331-05-contract-gate, 332-TST, 333-TERMINAL]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "buy-land verification via lootboxEthBase[index][player] > 0 (NOT the lastAutoBoughtDay stamp, which survives a try/catch revert)"
    - "forced-boon measurement: brute-found rngWord pins the open-time seed keccak256(rngWord, player, day, amount) to a target boon (whale-pass type 28), asserted via the LootBoxWhalePassJackpot event topic"

key-files:
  created:
    - ".planning/phases/331-.../331-CORRECTION-SUMMARY.md"
  modified:
    - "test/gas/RouterWorstCaseGas.t.sol"
    - ".planning/phases/331-.../331-GAS-DERIVATION.md"
    - ".planning/phases/331-.../331-CALIBRATION.md"
    - ".planning/phases/331-.../331-CONTEXT.md"
    - ".planning/phases/331-.../331-01-SUMMARY.md"
    - ".planning/phases/331-.../331-04-SUMMARY.md"

key-decisions:
  - "BUY non-vacuity fixed: verify the buy LANDED via lootboxEthBase>0 (the correct first-deposit signal), not the lastAutoBoughtDay day-stamp (set in _autoBuy:744 before batchPurchase fires; a slice < LOOTBOX_MIN reverts in the per-player try/catch while the stamp falsely passes). Corrected LANDING buy marginal ~261,809 (clean N32 ~255,614); old 40,224 = the revert-catch path"
  - "Whale-pass open branch found + measured: the type-28 BOON_WHALE_PASS -> _activateWhalePass 100-iter loop (~5,396,350 gas/box, ~60x typical ~89k) is the true open worst case (rare). The >5 ETH LOOTBOX_CLAIM_THRESHOLD defer-branches are the JACKPOT/DECIMATOR payout paths, NOT the per-box open path"
  - "30M -> 16.7M effective ceiling everywhere; ~9M average target for the default box buy/open leg"
  - "DOWORK_BATCH=100 SPLIT into BUY_BATCH=50 (HARD: 50x262k~=13.1M < 16.7M; buys NEVER exceed 16.7M) + OPEN_BATCH=100 (~9M typical avg; all-whale-pass corner exceeds 16.7M, USER-accepted by boon rarity)"
  - "Reward-ratio re-analysis: buy is now the MOST expensive leg (inverting the buy-cheapest rationale); ratios STILL faucet-safe at the fixture B; advance-6x STILL the binding faucet ceiling (8.78e12 wei); buy faucet ceiling ROSE (less binding); buy UNDER-reimbursement keeper-incentive implication flagged. Ratio VALUES frozen (out of scope)"
  - "rngLock disposition (USER-resolved): buying during rngLock is FINE (batchPurchase has no rngLock guard by design, RD-2); opening is blocked. The batchPurchase docstring :1739 is STALE (folds into 331-05, comment-only); testBatchPurchaseRngLockedRejectsWholeBatchAtEntry asserts the unwanted abort + FAILS against the live contract (pre-existing baseline failure, flagged not fixed)"

patterns-established:
  - "Correction-pass discipline: re-measure the load-bearing number, reproduce the WRONG number + explain its mechanism, re-derive downstream, mark every superseded conclusion with an inline banner"

requirements-completed: []

# Metrics
duration: ~90min
completed: 2026-05-27
---

# Phase 331 Correction Pass: BUY revert-catch fix + whale-pass open branch + 16.7M ceiling + split caps + reward-ratio re-analysis

**Re-measured the keeper-router BUY + OPEN legs with a fixed harness: the committed buy marginal (40,224) was the REVERT-CATCH path (forced-lootbox keeper buy on a sub-LOOTBOX_MIN slice reverts in batchPurchase's per-player try/catch while AfKing's lastAutoBoughtDay stamp falsely passes), corrected to ~261,809 verified via lootboxEthBase>0; found + measured the omitted whale-pass open branch (the type-28 boon's 100-iter _activateWhalePass loop, ~5,396,350 gas/box, the true open worst case); corrected the 30M ceiling to 16.7M (~9M avg target); sized split caps BUY_BATCH=50 / OPEN_BATCH=100; re-analysed the reward ratios (buy is now the most expensive leg, advance-6x still the binding faucet ceiling, buy under-reimbursement flagged); and noted the rngLock disposition (buy-fine / open-blocked) with the stale batchPurchase docstring + test flagged. TEST + DOC ONLY — no contracts/*.sol touched.**

## What was wrong (the two load-bearing errors)

### Error 1 — BUY measured the revert-catch path (~40,224 → ~261,809)
The original `RouterWorstCaseGas.t.sol` buy tests asserted "the buy landed" via AfKing's
`lastAutoBoughtDay` day-stamp (`AfKing.sol:744`). That stamp is written in `_autoBuy`'s accounting
loop BEFORE the batched `IGame.batchPurchase` fires, and `batchPurchase` wraps each per-player slice
in `try this._batchPurchaseUnit{value: slice}() catch {}` (`DegenerusGame.sol:1773-1780`). The keeper
buy is lootbox-only (`_purchaseFor(player, 0, slice, "DGNRS", payKind)`, ticketQuantity=0,
`DegenerusGame.sol:1806`), so the mint module's `lootBoxAmount < LOOTBOX_MIN (0.01 ether)` guard
(`DegenerusGameMintModule.sol:1011`) REVERTED every slice below 0.01 ether inside the try/catch — a
reverted (skipped+refunded) buy that LEFT THE DAY-STAMP SET. The original funding shape (drain-first
reinvest, claimable mp/2) produced a `Combined`-mode slice of ~mp/2 ≈ 0.005 ETH < LOOTBOX_MIN, so
EVERY buy reverted; `40,224` was the revert-catch cost.

**Diagnosed empirically:** with the old shape, `lootboxEthBase[index][player]` stays 0 after autoBuy
(the buy reverted). With a DirectEth qty-1 sub (cost = mp = 0.01 ether == LOOTBOX_MIN, passes the
strict `<` guard), `lootboxEthBase` becomes 0.01 ETH (the buy LANDED). Corrected marginals:
- whole-set N=32 (incl. 2 deploy subs): **261,809** / whole leg 8,377,899
- clean N=32 (deploy subs parked): **255,614**; gradient N1=484,194 → N8=269,222 → N32=255,614 (~1.89x)

BUY is therefore the MOST expensive per-item leg (~262k > advance 210k > typical-open 89k), inverting
331-04's "buy cheapest → richest 1.5x" justification.

### Error 2 — OPEN omitted the whale-pass branch (the gap)
A box-open's probabilistic boon roll (`_rollLootboxBoons`) can select the whale-pass boon (type 28,
`BOON_WHALE_PASS`), which runs `_activateWhalePass` (`DegenerusGameLootboxModule.sol:1240-1261`) — a
**100-iteration `_queueTickets` loop**. Measured at **~5,396,350 gas for a single box** (~60x the
typical ~89,288 marginal). Forced deterministically by brute-finding an rngWord that pins the
open-time seed `keccak256(rngWord, player, day, amount)` to the type-28 outcome (asserted via the
`LootBoxWhalePassJackpot` event topic). The >5 ETH `LOOTBOX_CLAIM_THRESHOLD` "defer to claim" branches
(`DegenerusGameJackpotModule.sol:1966/2029`, `DegenerusGameDecimatorModule.sol:583`) are the
JACKPOT/DECIMATOR payout paths, NOT the per-box `autoOpen` path; the inline whale-pass boon is the
heavy branch reachable from a keeper box-open.

## Corrected measured marginals (7/7 PASS, --isolate, harness commit 322fd972)

| Calibration input | Corrected gas | Old (wrong) |
|-------------------|---------------|-------------|
| buy per-player marginal (LANDED) | **261,809** (clean N32 255,614) | 40,224 (revert-catch) |
| open per-box (TYPICAL) | 89,288 | 89,287 (correct, unchanged) |
| open whale-pass box (RARE WORST CASE) | **5,396,350** | not modeled (the gap) |
| advance marginal | 210,689 | 210,689 (unchanged) |
| dispatch overhead (real landing buy) | 568,870 | 228,084 (folded a revert-catch buy) |

## Split-cap sizing (for the gated 331-05)

| Constant | Recommended | Rule |
|----------|-------------|------|
| `BUY_BATCH` | **50** | HARD ≤ 16.7M: 50 × 261,809 ≈ 13.1M (~22% headroom); 100 = ~26M over ceiling |
| `OPEN_BATCH` | **100** | ~9M typical avg: 100 × 89,288 ≈ 8.93M; all-whale-pass corner (100×5.4M) exceeds 16.7M — USER-ACCEPTED |

## Reward-ratio re-analysis (correction #5)

- (a) The frozen ratios (1.5/1.0/2.0, knee=5) STILL avoid a faucet at the current fixture
  `BOUNTY_ETH_TARGET = 885,000,000` wei: every leg round-trip ≤ 0 at the 0.5 gwei reference AND at all
  market prices (the corrected, higher buy cost only WIDENS the buy leg's negative round-trip).
- (b) Advance-6x is STILL the binding faucet ceiling (`8,778,708,333,333 wei`). The buy faucet ceiling
  ROSE from ~12.66e12 (at the wrong 37,986) to ~85.2e12 (at the corrected 255,614) — a more expensive
  leg absorbs more `BOUNTY_ETH_TARGET` before round-trip flips positive — so the buy leg is now far
  from binding, exactly as predicted.
- Buy UNDER-reimbursement FLAGGED: buy is the most expensive leg but carries the cheapest ratio
  relative to gas, so it is the most under-incentivized leg per gas. If the USER tunes `BOUNTY_ETH_TARGET`
  upward for keeper viability, the buy leg (~262k × market gas) is the binding INCENTIVE consideration —
  and its incentive floor (~170e12) sits ~20x ABOVE the advance-6x faucet ceiling (~8.78e12). The two
  cannot both be satisfied with a single shared B; the trade-off is the USER's economic call. Ratio
  VALUES are frozen (329 SPEC D-07; out of scope) — not changed, only re-analysed + flagged.

## rngLock disposition (correction #6, USER-resolved)

- BUYING lootboxes during rngLock is FINE (commit-before-reveal; `batchPurchase` has NO rngLock guard
  by design — only `AF_KING` + `gameOver` at `:1762-1763`; RD-2 freeze-safe buys).
- OPENING is blocked (autoOpen `:1671` no-op, openLootBox `:2162` revert, the `:1683` word-gate).
- The `batchPurchase` docstring `:1739` is STALE (falsely claims an rngLock entry pre-check) → comment-
  only fix folds into the gated 331-05 (diff specified in 331-CALIBRATION §8).
- `testBatchPurchaseRngLockedRejectsWholeBatchAtEntry` (`CrankNonBrick.t.sol:360`) asserts the unwanted
  rngLock whole-batch abort and FAILS against the live contract (it `vm.expectRevert(RngLocked())`; the
  live `batchPurchase` correctly does NOT revert). FLAGGED for correction — NOT fixed in this pass (it
  asserts behavior the contract correctly does not have; it is a pre-existing baseline failure, and the
  test-fix belongs with the 331-05 docstring change or a dedicated test pass).

## Verification

- `forge build` — GREEN (lint notes only, no errors).
- `forge test --match-path test/gas/RouterWorstCaseGas.t.sol --isolate` — **7/7 PASS**.
- **Failure-delta vs baseline:** zero NEW failures introduced. The only RouterWorstCaseGas changes are
  mine (commit `322fd972`); they all pass. The pre-existing `testBatchPurchaseRngLockedRejectsWholeBatchAtEntry`
  failure (`CrankNonBrick.t.sol`, untouched by me) is part of the known ~58-failure baseline and is the
  test correction #6 flags — not a regression from this pass.
- **No `contracts/*.sol` edited** (`git diff --name-only -- contracts/` empty).

## Files changed

- `test/gas/RouterWorstCaseGas.t.sol` (commit `322fd972`) — buy tests verify landing via
  `lootboxEthBase>0`; new `testOpenLegWhalePassBoxMarginalIsTheRareWorstCase`; 16.7M ceiling; dispatch
  test uses a landing sub; dead helpers removed.
- `331-GAS-DERIVATION.md` — §0 correction banner; §1 LANDING-vs-revert + corrected prediction; §2
  whale-pass branch; §5 corrected marginals table + gradient; new §5.1 split-cap sizing; 30M→16.7M.
- `331-CALIBRATION.md` — §0 correction banner; §2 corrected relative marginals + new §2.1 buy
  under-reimbursement flag; §3 corrected faucet table (buy ceiling rose, advance-6x still binds); §4/§5
  corrected one-shot framing + buy-vs-faucet tension; §8 split-cap diff + stale-docstring fix; §9 table;
  new §11 correction summary.
- `331-CONTEXT.md` — `<corrections>` block.
- `331-01-SUMMARY.md` / `331-04-SUMMARY.md` — superseded-in-part banners.

## Self-Check: PASSED

- `test/gas/RouterWorstCaseGas.t.sol` — FOUND (commit `322fd972`)
- `331-GAS-DERIVATION.md` / `331-CALIBRATION.md` / `331-CONTEXT.md` — FOUND (corrected)
- `331-CORRECTION-SUMMARY.md` — FOUND
- `forge test --match-path test/gas/RouterWorstCaseGas.t.sol --isolate` — 7/7 PASS
- `git diff --name-only -- contracts/` — EMPTY (no contract mutation)
- stash@{0} `331-05-partial-abandoned...` — UNTOUCHED (no `git stash` run)

---
*Phase: 331-gas-worst-case-marginal-derivation-break-even-0-5gwei-peg-ca*
*Correction pass completed: 2026-05-27*
