# Economic Disclosures

For a gambling protocol, economic transparency matters as much as contract transparency.
**Every figure below cites the exact contract line that defines it.** Nothing here is
marketing math — verify each number against the frozen subject (`contracts/` tree
`2dc4a67b`, tag `degenerus-c4a`).

The code is **not yet deployed**. There are no live token prices. Figures are on-chain
constants and formulas, not projected returns.

---

## 1. Value flow — the non-negotiables

- **No rake on gameplay.** Every wei of ticket and lootbox ETH goes into prize pools and
  recirculates to players — no operator fee is skimmed from play. The creator's up-front funding is a
  **bounded initial coin offering** (the presale box, ≤40 ETH to the creator) — a primary sale of
  coin, not a rake (§2c).
- **No admin withdrawal.** There is no privileged function that moves player ETH/stETH. The
  protocol has no proxy, no upgradeability, and no configurable privileged addresses — every
  cross-contract authority is a compile-time constant in `ContractAddresses.sol`. The bounded
  authority of each trusted role is enumerated in [`SECURITY.md`](SECURITY.md).
- **The creator's economic interest is the vault and token holdings in §2 — not a privileged
  withdrawal path.** The primary benefit is the vault's ~25% share of stETH yield (§2a); reserve
  tokens redeem through the *same* gambling-burn path every holder uses. No operator drain of
  player funds.

## 2. What the creator gets at deploy

### (a) The DegenerusVault — effectively the creator's private vault

The creator holds **100% of both vault share classes** (DGVE + DGVF) at deploy
(`DegenerusVault.sol:238-243`), so the two-token split is internal abstraction — functionally the
creator owns the vault. What it entitles the creator to:

- **Primary benefit — ~25% of the protocol's stETH yield.** Surplus (balance above obligations) is
  split ~23% four ways — sDGNRS backing, the vault, GNRUS charity, and a yield-accumulator buffer —
  via `quarterShare = yieldPool * 2300 / 10_000` (`modules/DegenerusGameJackpotModule.sol:664-698`).
  Once the ~8% remainder is accounted for, the vault's effective take is **≈25% of yield**. This is
  the creator's main economic upside.
- **An up-front, worse-than-retail deity pass.** At genesis the vault is given
  the deity activity-score boost (nerfed: no trait symbol or automatic gold entry, not counted as a deity-pass holder) plus a
  standing queue of **4 tickets per level** (`DegenerusGame.sol:210-233`, `initPerpetualTickets`).
  Economically this is a *nerfed deity pass* — the same kind of standing, up-front position a
  deity-pass buyer holds, except granted rather than purchased. Like any deity pass it earns jackpot
  entries and score; it is a fixed genesis grant, not a privileged withdrawal path against player
  ETH/stETH.
- **Claimable token mint reserves** — the uncirculating FLIP and WWXRP vault reserves (§5) are
  vault-mintable, i.e. creator-controllable.

(The same perpetual-ticket + score grant also goes to the `sDGNRS` reserve address — but that backs
*all* holders collectively, not the creator personally.)

### (b) Reserve-token stake — 20% of sDGNRS (200B), held as DGNRS

`CREATOR_BPS = 2000` → 20% of sDGNRS `INITIAL_SUPPLY` = 200B (`sDGNRS.sol:308,385`). **sDGNRS and
DGNRS are the same position, not two:** sDGNRS is the soulbound reserve token, DGNRS its transferable
1:1 wrapper. The sDGNRS constructor mints the creator's 20% **directly into the DGNRS wrapper
contract** (`sDGNRS.sol:383` — *"Mints creator allocation to DGNRS wrapper address"*), which issues
200B DGNRS against it (`DGNRS.sol:109-112`). Of that, 50B is liquid at deploy and the rest vests over
levels (§3). It is **not** 20% sDGNRS *plus* a separate 200B DGNRS.

For context, that 20% is one slice of the full sDGNRS `INITIAL_SUPPLY` — the other **80%** funds game
pools, not the creator (`sDGNRS.sol:311-315,385-395`):

| Pool | Share | Constant |
|---|---|---|
| Affiliate | 30% | `AFFILIATE_POOL_BPS = 3000` |
| Lootbox | 20% | `LOOTBOX_POOL_BPS = 2000` |
| Whale | 10% | `WHALE_POOL_BPS = 1000` |
| Reward | 10% | `REWARD_POOL_BPS = 1000` |
| Presale box | 10% | `PRESALE_BOX_POOL_BPS = 1000` |
| *(Creator)* | *20%* | *`CREATOR_BPS = 2000`* |

Sum = 10,000 bps (100%); any rounding dust is retained by the reserve (`sDGNRS.sol:395`).

### (c) Presale box — a bounded initial coin offering (≤40 ETH to the creator)

The presale box is a **primary sale at genesis**: buyers voluntarily exchange ETH for presale-box
credits (backed by the 10% presale-box sDGNRS pool, §2b). It is an initial offering of coin — **not a
rake**; no fee is taken from player gameplay. Total presale-box ETH is capped at **50 ETH**
(`PRESALE_BOX_ETH_CAP = 50 ether`, `storage/DegenerusGameStorage.sol:1136`); proceeds route **80% to
the vault (creator), 20% to sDGNRS** (`_creditBoxProceeds`, `modules/DegenerusGamePayoutUtils.sol:13-26`),
with `claimablePool` bumped by the full amount so solvency holds. The creator's proceeds are therefore
**bounded at ≤40 ETH** (80% of the 50-ETH cap).

Everything else is rake-free: the separate lootbox presale (200 ETH cap, `LOOTBOX_PRESALE_ETH_CAP`)
routes **100% to the prize pool** (`modules/DegenerusGameMintModule.sol:1519`), and all post-genesis
ticket/lootbox ETH goes to pools — no proceeds route to the creator.

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

## 5. FLIP + WWXRP mint reserves, and the WWXRP draw

Neither FLIP nor WWXRP is minted to the creator's balance at deploy (`totalSupply` starts at 0).
Both instead carry an **uncirculating, vault-mintable reserve** — supply the vault (creator-owned,
§2a) can bring into circulation on demand:

- **FLIP** exposes `supplyIncUncirculated() = totalSupply + vaultAllowance` (`FLIP.sol:284`); the
  vault's claimable FLIP mint allowance is the DGVF side of the vault split (`DegenerusVault.sol:145`).
  Separately, the **initial FLIP emission** stakes **200k FLIP/day for the first 20 days** each to the
  vault and sDGNRS (~4M FLIP each), delivered as Coinflip stakes that must survive a flip before
  minting (`FLIP.sol:16-17`) — the vault's share is another creator-side FLIP allocation, gated
  through the coinflip.
- **WWXRP** seeds a **1B** reserve: `INITIAL_VAULT_ALLOWANCE = 1_000_000_000e18` → `vaultAllowance`
  (`WWXRP.sol:223,226`), described in-code as the *"uncirculating reserve the vault can mint from,"*
  drawn only by the vault via `vaultMintTo` (`WWXRP.sol:441-451`) and surfaced by
  `supplyIncUncirculated()` (`WWXRP.sol:321-324`).

Because the vault is creator-owned, these reserves are **effectively creator-controllable supply** —
outside circulation until minted, not in the creator's balance. WWXRP is a deliberately meme/worthless
game token (RTP calibrated worthless by design — see [`KNOWN-ISSUES.md`](KNOWN-ISSUES.md)).

Its **daily burn draw**: burn ≥25 WWXRP (`MIN_BURN`) to enter the day's draw; 10 buckets, one weighted
winner. Prizes are **FLIP coinflip credit, not ETH**: `BIG_PRIZE = 100_000` FLIP at 1/365, else
  `SMALL_PRIZE = 10_000` FLIP at 1/30, paid via `coinflip.creditFlip` (`WWXRP.sol:259-268,563-564`).

## 6. What is negative-EV (honesty about the gamble)

- **Tickets are typically −EV** and provably fair — jackpots pay trait-matched holders by VRF.
  Under some conditions (pool size, level velocity, trait scarcity) a ticket can be +EV, but the
  baseline expectation is negative (README, "Tickets").
- **Lootboxes and passes are designed to be +EV** for their intended buyers — players active enough
  to earn the activity-score multiplier (positive-EV by design; see [`KNOWN-ISSUES.md`](KNOWN-ISSUES.md)
  and README). They fund prize pools up front and receive future-level tickets in return.
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
