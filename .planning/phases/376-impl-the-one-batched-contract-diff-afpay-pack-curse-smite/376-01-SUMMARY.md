---
phase: 376-impl-the-one-batched-contract-diff-afpay-pack-curse-smite
plan: 01
subsystem: payments
tags: [solidity, storage-packing, claimable, afking, solvency, delegatecall]

# Dependency graph
requires:
  - phase: 375
    provides: SPEC-V61-DESIGN-LOCK (D-01 accessor-first order, re-attested anchors, AFPAY waterfall map)
provides:
  - PACK accessor layer in DegenerusGameStorage (_claimableOf/_afkingOf/_creditClaimable/_debitClaimable/_creditAfking/_debitAfking)
  - balancesPacked mapping [afking:high128 | claimable:low128] folding the old claimableWinnings + afkingFunding mappings into one slot
  - Generalized _settleShortfall(buyer, shortfall, allowClaimable) -> (claimableUsed, afkingUsed)
  - AfkingSpent event (declared in Storage) emitted at every afking debit
  - afking-as-payment tier across _processMintPayment + lootbox + presale + 3 whale sites + Degenerette ETH bet + affiliate split
affects: [376-03, 377-gas, 378-tst-sec]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Pure-packing accessors (USER-approved deviation): the 6 balance accessors are balance-only; the claimablePool solvency pairing stays at the CALL SITES (every existing claimablePool +=/-= kept verbatim)."
    - "Naive half-word accessor math (USER-approved deviation): credits use `+= weiAmount` (low half) / `+= weiAmount << 128` (high half); safe by the per-player supply bound (<= ~1.2e26 wei << 2^128) so a credit never carries into the other half. _debitClaimable carries an explicit low-half guard (`if (uint128(slot) < amt) revert E()`); _debitAfking is naturally fail-loud via 0.8 high-half underflow."

key-files:
  created: []
  modified:
    - contracts/storage/DegenerusGameStorage.sol
    - contracts/DegenerusGame.sol
    - contracts/modules/DegenerusGameMintModule.sol
    - contracts/modules/DegenerusGameWhaleModule.sol
    - contracts/modules/DegenerusGameDegeneretteModule.sol
    - contracts/modules/DegenerusGamePayoutUtils.sol
    - contracts/modules/DegenerusGameGameOverModule.sol
    - contracts/modules/DegenerusGameLootboxModule.sol

key-decisions:
  - "PACK = pure-packing Option A (USER-approved): accessors balance-only, claimablePool pairing at call sites; Jackpot/Advance/Decimator untouched (already used _creditClaimable + keep their pool lines)."
  - "Accessor math = naive +=/-= (USER-approved), not the SPEC's split/recombine; supply-bound safe."
  - "AfkingSpent emitted at EACH afking debit (D-02 broad option) — both _processMintPayment AND _settleShortfall; deliberate asymmetry vs silent claimable spends (headline transparency signal)."

patterns-established:
  - "Single solvency-invariant statement home: `claimablePool == Σ (claimable + afking halves of balancesPacked[*])` documented at Storage:358; each debit/credit site pairs the matching claimablePool delta."

requirements-completed: [PACK-01, PACK-02, AFPAY-01, AFPAY-02, AFPAY-03, AFPAY-04, AFPAY-05, AFPAY-06, AFPAY-07]

# Metrics
duration: ~session (prior)
completed: 2026-06-06
---

# Phase 376-01: PACK accessor layer + folded balances mapping + AFPAY afking-as-payment waterfall

**Two balance mappings folded into one `balancesPacked` slot behind six accessors, and a generalized `_settleShortfall` waterfall that lets a player's prepaid afking principal cover mint/lootbox/presale/whale/Degenerette shortfalls as fresh-ETH-equivalent, with `AfkingSpent` emitted at every afking draw.**

## Accomplishments
- **PACK-01/02** — Accessor layer in `DegenerusGameStorage`; `claimableWinnings[]` + `afkingFunding[]` folded into ONE `mapping(address => uint256) balancesPacked` `[afking:high128 | claimable:low128]` (`:418`). Every raw mapping access routed through `_claimableOf`/`_afkingOf`/`_creditClaimable`/`_debitClaimable`/`_creditAfking`/`_debitAfking` (verified zero raw access outside accessor bodies). gameOver claim-merge preserves the afking half (debits only the claimable half).
- **AFPAY-01/07** — `_settleClaimableShortfall` generalized to `_settleShortfall(buyer, shortfall, allowClaimable) -> (claimableUsed, afkingUsed)` (`Storage:857`): claimable to the 1-wei sentinel (only if `allowClaimable`), then the remainder from afking (to 0), revert if both short, every debit pairs `claimablePool -=`. `event AfkingSpent(address indexed player, uint256 amount)` declared in Storage (`:552`), emitted at each afking debit.
- **AFPAY-02..06** — afking tier in `_processMintPayment` (all 3 pay-kinds; `prizeContribution = ethUsed + claimableUsed + afkingUsed`); lootbox shortfall via `_settleShortfall(…, payKind != DirectEth)` (DirectEth-revert lifted); presale + 3 whale sites via the shared helper; Degenerette ETH bet afking tier inline (keeps `InvalidBet()`); affiliate fresh/recycled split (`freshEth = costWei − claimableUsed`, so afking lands in the fresh-rate leg; byte-identical for no-afking cases).

## Files Created/Modified
- `contracts/storage/DegenerusGameStorage.sol` — accessor layer, `balancesPacked`, `_settleShortfall`, `AfkingSpent`, solvency invariant comment (`:358`).
- `contracts/DegenerusGame.sol` — `_processMintPayment` afking tier; `depositAfkingFunding`/`withdrawAfkingFunding`/`afkingFundingOf` via accessors.
- `contracts/modules/DegenerusGameMintModule.sol` — lootbox + presale + affiliate-split AFPAY wiring.
- `contracts/modules/DegenerusGameWhaleModule.sol` — 3 pass sites via `_settleShortfall`.
- `contracts/modules/DegenerusGameDegeneretteModule.sol` — ETH-bet afking tier.
- `contracts/modules/DegenerusGamePayoutUtils.sol` — claimable credits via `_creditClaimable`.
- `contracts/modules/DegenerusGameGameOverModule.sol` — gameOver zeroing preserves afking half.
- `contracts/modules/DegenerusGameLootboxModule.sol` — accessor routing.

## Decisions Made
See key-decisions frontmatter. The two PACK deviations (pure-packing accessors; naive half-word math) and the broad `AfkingSpent` emission are USER-approved departures from the literal SPEC; rationale recorded there and in the handoff.

## Deviations from Plan
- **PACK pairing at call sites, not inside accessors** (USER-approved). Deviates from the must_have "pairing inside the accessor"; SOLVENCY-01 still holds and is re-proven at SEC-02/378.
- **Naive `+=`/`-=` accessor math** (USER-approved), not split/recombine; supply-bound safe with a low-half guard on `_debitClaimable`.
- **Benign:** deity-refund + sDGNRS→player relabel routed through `_creditClaimable` add a `PlayerCredited` emit where raw writes were silent (zero state/solvency change) — flagged for hand-review.

## Issues Encountered
None (build-cleanliness + EIP-170 handled in 376-03).

## Next Phase Readiness
- Contracts compile; the diff is HELD at the contract-commit boundary (see 376-03). SEC-02 (378) re-proves SOLVENCY-01 at the accessor-layer home.

---
*Phase: 376-impl-the-one-batched-contract-diff-afpay-pack-curse-smite (plan 01)*
*Completed: 2026-06-06*
