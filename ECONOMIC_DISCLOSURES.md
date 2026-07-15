# Economic Disclosures

For a gambling protocol, economic transparency matters as much as contract transparency.
**Every figure below cites the exact contract line that defines it.** Nothing here is
marketing math — verify each number against the frozen subject (`contracts/` tree
`2dc4a67b`, tag `degenerus-c4a`).

The code is **not yet deployed**. There are no live token prices. Figures are on-chain
constants and formulas, not projected returns.

---

## 1. Value flow — the non-negotiables

- **No rake after presale.** Every wei of ticket ETH goes into prize pools and recirculates
  to players. There is no operator fee.
- **No admin withdrawal.** There is no privileged function that moves player ETH/stETH. The
  protocol has no proxy, no upgradeability, and no configurable privileged addresses — every
  cross-contract authority is a compile-time constant in `ContractAddresses.sol`. The bounded
  authority of each trusted role is enumerated in [`SECURITY.md`](SECURITY.md).
- **The creator's economic interest is via token holdings (§2), not a withdrawal path.** Those
  tokens redeem through the *same* gambling-burn redemption every holder uses — no privileged
  drain.

## 2. Creator allocations at deploy (sourced)

| Token | Creator allocation at deploy | Source |
|---|---|---|
| **DGVE** (vault governance/admin share) | **100%** of `INITIAL_SUPPLY` | `DegenerusVault.sol:213,238-243` |
| **DGVF** (vault yield/flip share) | **100%** of `INITIAL_SUPPLY` | `DegenerusVault.sol:213,238-243` |
| **sDGNRS** (soulbound reserve token) | **20%** of `INITIAL_SUPPLY` (`CREATOR_BPS = 2000`) | `sDGNRS.sol:302,308,385` |
| **DGNRS** (transferable sDGNRS wrapper) | **50B** at deploy, then vesting (§3) | `DGNRS.sol:95,113-117` |

Both vault share classes are instances of the same share-token contract, whose constructor mints
the full `INITIAL_SUPPLY` to `CREATOR` (`DegenerusVault.sol:238-243`). DGVE carries admin authority
(§4); DGVF is the yield/flip share.

The remaining **80%** of sDGNRS `INITIAL_SUPPLY` funds game pools, not the creator
(`sDGNRS.sol:311-315,385-395`):

| Pool | Share | Constant |
|---|---|---|
| Affiliate | 30% | `AFFILIATE_POOL_BPS = 3000` |
| Lootbox | 20% | `LOOTBOX_POOL_BPS = 2000` |
| Whale | 10% | `WHALE_POOL_BPS = 1000` |
| Reward | 10% | `REWARD_POOL_BPS = 1000` |
| Presale box | 10% | `PRESALE_BOX_POOL_BPS = 1000` |
| *(Creator)* | *20%* | *`CREATOR_BPS = 2000`* |

Sum = 10,000 bps (100%); any rounding dust is retained by the reserve (`sDGNRS.sol:395`).

## 3. Creator DGNRS vesting

Level-gated, defined in `DGNRS.sol:95-97,199-206`:

```
vested = CREATOR_INITIAL + level × VEST_PER_LEVEL,  capped at CREATOR_TOTAL
       = 50B          + level × 5B,                capped at 200B
```

- `CREATOR_INITIAL = 50_000_000_000e18` — released at deploy.
- `VEST_PER_LEVEL  = 5_000_000_000e18` — one increment per game level advanced.
- `CREATOR_TOTAL   = 200_000_000_000e18` — hard cap; `claimVested()` reverts once reached.

The creator cannot claim ahead of level progression — vesting tracks the game actually
advancing, which requires real player activity.

## 4. Governance / who controls what

- **Admin authority follows >50.1% of DGVE.** Because the creator holds 100% of DGVE at deploy
  (§2), the creator is the **initial admin**. DGVE is an ERC-20 share class; authority moves
  with the token.
- **Admin powers are narrowly scoped** and cannot touch player funds: VRF-coordinator swaps
  (sDGNRS-governed, behind a VRF-stall death clock), ETH→stETH liquidity conversion, the
  lootbox RNG threshold, and LINK price-feed configuration. Full matrix and bounds:
  [`SECURITY.md`](SECURITY.md).
- **Community path:** 0.5%+ sDGNRS holders can propose a VRF-coordinator swap after a 7-day VRF
  stall.

## 5. Referral economics

- `MAX_KICKBACK_PCT = 25` — a referral code returns at most 25% of rewards to referred players
  (`DegenerusAffiliate.sol:183,324-329`).
- Commissions are paid as **FLIP coinflip credits, not direct ETH** — this filters mercenary
  referral farmers (see README, "Affiliate network").

## 6. What is negative-EV (honesty about the gamble)

- **Tickets are honestly −EV** and provably fair — jackpots pay trait-matched holders by VRF
  (README, "Tickets").
- **Lootboxes / passes** EV depends on activity score and level velocity; they *fund* prize
  pools and receive future-level tickets in return (README, "Lootboxes and passes").
- Coinflip / Degenerette RTP calibration and other by-design economics are enumerated with
  their exact mechanisms in [`KNOWN-ISSUES.md`](KNOWN-ISSUES.md).

## 7. Terminal value (game over)

On a liveness-guard game-over (`modules/DegenerusGameGameOverModule.sol`):

1. Deity-pass refunds (≤20 ETH each, budget-capped, if game ends before level 10).
2. 10% to Decimator death-bet holders, 90% to the phase-correct terminal ticket cohort.
3. Any uncredited remainder and, after a **30-day** final sweep, all unclaimed balances are
   split **three ways** between the vault, sDGNRS, and GNRUS (GNRUS absorbs rounding dust)
   (`GameOverModule:199-228`).

---

### What is deliberately *not* stated here

- **No ETH return projections.** sDGNRS/DGNRS are game tokens redeemable via gambling-burn for
  a proportional reserve share — not ETH-pegged instruments. Any ETH figure depends on player
  activity that does not exist pre-deploy.
- **No production deployment manifest / bytecode hashes.** Those are added at mainnet launch
  (see README, "Deployment"); the committed addresses are the deterministic test set.
