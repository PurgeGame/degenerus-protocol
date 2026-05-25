# v48.0 Plan — Redemption ETH-Empty stETH Fallback (F-47-02)

**Status:** SCOPE-LOCKED, QUEUED for v48.0. Source: v47.0 Phase 324 TERMINAL adversarial sweep
(`/zero-day-hunter` B1), USER threat-model correction + fix shape locked (2026-05-25). Finding write-up:
`.planning/phases/324-terminal-delta-audit-3-skill-adversarial-sweep-closure/324-02-ADVERSARIAL-LOG.md` §4.2.

## Finding (F-47-02, MEDIUM — liveness/availability; no funds at risk)

At gambling-burn submit, `_submitGamblingClaimFrom` computes the ETH base proportional to sDGNRS's FULL backing —
`totalMoney = address(this).balance + steth.balanceOf(this) + claimable[SDGNRS] − pendingRedemptionEthValue`
(`StakedDegenerusStonk.sol:844-848`) — then segregates the MAX 175% reservation via `game.pullRedemptionReserve`
(`DegenerusGame.sol:1888-1899`), a CHECKED debit of `claimableWinnings[SDGNRS]` **alone**, fail-closed, with **no
fallback to sDGNRS's stETH/ETH balance.**

**USER threat-model correction:** sDGNRS backing cannot be stETH-dominant before game-over, and gambling burns are
blocked after game-over — so the sweep agent's "normal steady-state brick" prevalence is wrong. The genuine residual
case is **mid-game ETH depletion**: if the game's ETH runs out while still live, the ETH-side reservation has no
fallback and the submit bricks. Also surfaced (USER donation question): a freely-transferable **stETH donation** (or
`selfdestruct` ETH force-feed; `receive()` is `onlyGame`) inflates `totalMoney` → inflates the 175% reservation →
can brick the claimable-only pull. (Verified NOT a profit/inflation/underflow exploit: donation is -EV to the donor;
`depositSteth` mints no shares so no ERC-4626 inflation attack; genesis-minted supply never near 0; checked subtraction.)

## Fix — LOCKED shape: pure-ETH OR pure-stETH reservation, revert if neither covers

The redemption reservation/payout segregates the 175% MAX from **either pure ETH OR pure stETH** (no mix — keeps the
accounting simple), extending the existing game-over deterministic ETH→stETH fallback (REDEEM-04) to the mid-game
ETH-depletion case:
1. Try to cover the 175% reservation from the ETH side (claimable[SDGNRS] / game ETH) as today.
2. If ETH cannot cover it, fall back to segregating the reservation in **pure stETH** (sDGNRS already holds stETH;
   the payout at claim is then stETH).
3. If **neither pure-ETH nor pure-stETH alone** can cover the 175%, **revert** (fail-closed — the "neither covers"
   case is not a realistic scenario, so failing closed there is acceptable).
4. **Donation-robust:** check coverage against the **same asset basis the base is inflated by** — a stETH-inflated
   base must be coverable by the pure-stETH leg. Do NOT reintroduce a claimable-ETH-only chokepoint.

## Surface
- `contracts/StakedDegenerusStonk.sol` — `_submitGamblingClaimFrom` reservation segregation (the `maxIncrement`
  pull at `:880-887`); claim-time payout asset selection (`:622`/`:932` stETH-transfer paths already exist).
- `contracts/DegenerusGame.sol` — `pullRedemptionReserve` (`:1888-1899`): add the ETH-vs-stETH coverage branch.
- Possibly `pendingRedemptionEthValue` accounting if a stETH-denominated reservation is tracked separately
  (decide at SPEC: track a single value vs split ETH/stETH).

## Tests
- ETH-empty: fund sDGNRS ETH-poor / stETH-only, submit a gambling burn → asserts the stETH leg covers (no brick),
  claim pays stETH.
- Donation: send stETH to sDGNRS, then submit → assert the stETH-inflated base is covered (no brick).
- Neither-covers: contrive a state where neither pure-ETH nor pure-stETH covers the 175% → asserts revert (fail-closed).
- Regression: the v47 REDEEM-08 invariants (two-claimant, BURNIE-can't-block-ETH, conservation, balance ≥ pending)
  still hold under the fallback.

## Closure-verdict bearing
v47.0 closed with F-47-02 DEFERRED→v48 (the v46→v47 H-CANCEL-SWAP-MISS precedent). This plan resolves it in v48.0.
