# v48.0 Plan — Presale-Box DGNRS Drain Fix (F-47-01)

**Status:** SCOPE-LOCKED, QUEUED for v48.0. Source: v47.0 Phase 324 TERMINAL adversarial sweep (`/contract-auditor`),
USER-adjudicated DEFER→v48 with fix mechanism locked (2026-05-25). Finding write-up:
`.planning/phases/324-terminal-delta-audit-3-skill-adversarial-sweep-closure/324-02-ADVERSARIAL-LOG.md` §4.1.

## Finding (F-47-01, MEDIUM — tokenomics misallocation)

The coin-presale closing box sweeps the entire remaining `Pool.PresaleBox` DGNRS to the single closing buyer
(`DegenerusGameLootboxModule.sol:678-693`, reads live `poolBalance` regardless of roll outcome). The design
(`PLAN-PRESALE-COIN-BOXES-RAKE-FREE.md:85`) assumed the swept remainder would be **"dust, not a windfall"** because
the DGNRS tier curve `[3.0,2.5,2.0,1.5,1.0]` over 5×10-ETH tiers (`base=poolStart/100`) drains the full 100B-DGNRS
pool (`PRESALE_BOX_POOL_BPS=1000` = 10% of supply) over 50 ETH — **but only if every box draws DGNRS.** The
resolution branch is **50% BURNIE / 40% DGNRS / 10% WWXRP** (`:644-676`) and the per-box draw
`(poolStart × tierTenths × amount)/(1000 × 1e18)` (`:720`) does NOT scale for the 40% hit-rate. So in expectation
only ~40% of the pool drains across box buyers; **~60% (~60B DGNRS ≈ 6% of total supply) is swept to one closing
buyer.** The USER's acceptance of the sweep was predicated on the dust assumption, which the 40% branch rate breaks.

## Fix — LOCKED mechanism (a): scale the draw by the branch rate

In `_presaleBoxDgnrsReward` (`DegenerusGameLootboxModule.sol:705-727`), change the divisor so each DGNRS draw is
2.5× larger (compensating for the ~40% realized DGNRS branch rate):

```solidity
// before:  uint256 dgnrsAmount = (poolStart * tierTenths * amount) / (1_000 * 1 ether);
// after:   uint256 dgnrsAmount = (poolStart * tierTenths * amount) / (  400 * 1 ether);
```

i.e. `base = poolStart/40` instead of `poolStart/100`. The realized ~40% DGNRS branch rate × the 2.5×-larger
curve drains the full pool over 50 ETH in expectation; the closing-box sweep then mops up only **variance dust**.
`transferFromPool` already clamps to the live pool balance, so a run of early DGNRS hits cannot over-draw (late
boxes simply draw less / the pool empties before close and the closing sweep is ~0). Tier ratios + the per-tier
3:1 early/late shape are unchanged (only the absolute scale moves).

## Surface
- `contracts/modules/DegenerusGameLootboxModule.sol` — `_presaleBoxDgnrsReward` divisor (1 line) + the inline
  comment at `:716-719` that derives `base = poolStart/100` → `poolStart/40`.
- ISOLATED — touches no other v48 work item's surface (independent of the redemption fallback fix F-47-02).

## Tests
- Drain test: simulate a realistic 50-ETH presale (random 50/40/10 outcomes across many boxes); assert the closing
  sweep transfers only dust (≤ a small bound, not ~60% of the pool); assert the pool ends ~empty.
- Tier-shape preserved: tier-1 buyer still gets 3× the DGNRS-per-ETH of tier-5.
- Edge: a run of early DGNRS hits empties the pool before close → closing sweep ≈ 0, no revert (clamp holds).

## Closure-verdict bearing
v47.0 closed with F-47-01 DEFERRED→v48 (the v46→v47 H-CANCEL-SWAP-MISS precedent). This plan resolves it in v48.0.
