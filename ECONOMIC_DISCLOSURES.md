# Economic Disclosures

For a gambling protocol, economic transparency matters as much as contract transparency.
**Every figure below cites the exact contract line that defines it.** Nothing here is
marketing math — verify each number against the frozen subject (`contracts/` tree
`39279e31`, tag `degenerus-c4a`).

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
  withdrawal path.** The vault has several ongoing inflows (stETH yield, default-referrer affiliate
  rewards, a daily lootbox subscription, a nerfed deity-pass position; §2a); reserve tokens redeem
  through the *same* RNG-gated gambling-burn path every holder uses (§6). No operator drain of player
  funds.

## 2. What the creator gets at deploy

### (a) The DegenerusVault — effectively the creator's private vault

The creator holds **100% of both vault share classes** (DGVE + DGVF) at deploy
(`DegenerusVault.sol:248-254`), so the two-token split is internal abstraction — functionally the
creator owns the vault. It has **several ongoing inflows, not just yield**:

- **stETH yield — the largest ongoing inflow.** Protocol surplus (balance above obligations) is split
  into four ~23% shares — sDGNRS backing, the vault, GNRUS charity, and a yield-accumulator — via
  `quarterShare = yieldPool * 2300 / 10_000` (`modules/DegenerusGameJackpotModule.sol:779-790`),
  leaving ~8% undistributed as the immediate solvency cushion. The vault's *immediate* share is ~23%;
  because that residual is redistributed on later rounds, each destination tends toward ~25% over
  time — but 25% is asymptotic, not guaranteed or immediate. The accumulator is not vault-bound
  either: half of it dumps into the players' future pool at every ×00 level
  (`modules/DegenerusGameAdvanceModule.sol:1212-1214`).
- **Default-referrer affiliate rewards.** The vault is the terminal referrer for every player with no
  valid referral code (`DegenerusAffiliate.sol:374` — *"referral chains always terminate at the
  VAULT"*), so it collects affiliate rewards on all unreferred spend at **25% / 20% / 5%** of reward
  basis (fresh L1-3 / fresh L4+ / recycled; `DegenerusAffiliate.sol:411-413`). No-referrer deity purchases
  additionally route an affiliate whale pass and DGNRS rewards to the vault
  (`modules/DegenerusGameWhaleModule.sol:712`).
- **Perpetual daily lootbox subscription.** At genesis the vault self-subscribes to a claimable-first
  daily lootbox (quantity 1, no FLIP rebuy) — a protocol-owned position (`DegenerusVault.sol:470-478`).
- **An up-front, worse-than-retail deity pass.** The vault is given the deity activity-score boost
  (nerfed: no trait symbol or automatic gold entry, not counted as a deity-pass holder) plus a
  standing queue of **4 tickets per level** (`DegenerusGame.sol:233`, `initPerpetualTickets`).
  Economically this is a *nerfed deity pass* — the same kind of standing, up-front position a
  deity-pass buyer holds, except granted rather than purchased. It earns jackpot entries and score; it
  is a fixed genesis grant, not a privileged withdrawal path against player ETH/stETH.
- **The WWXRP mint reserve** (§5) is vault-mintable, i.e. creator-controllable. (FLIP has no such
  reserve — it starts fully zero; see §5.)

(The perpetual-ticket + score grant also goes to the `sDGNRS` reserve address — but that backs *all*
holders collectively, not the creator personally.)

### (b) Reserve-token stake — 20% of sDGNRS (200B), held as DGNRS

`CREATOR_BPS = 2000` → 20% of sDGNRS `INITIAL_SUPPLY` = 200B (`sDGNRS.sol:303,398`). **sDGNRS and
DGNRS are the same position, not two:** sDGNRS is the soulbound reserve token, DGNRS its transferable
1:1 wrapper. The sDGNRS constructor mints the creator's 20% **directly into the DGNRS wrapper
contract** (`sDGNRS.sol:398` — *"Mints creator allocation to DGNRS wrapper address"*), which issues
200B DGNRS against it (`DGNRS.sol:109-118`). Of that, 50B is liquid at deploy and the rest vests over
levels (§3). It is **not** 20% sDGNRS *plus* a separate 200B DGNRS.

For context, that 20% is one slice of the full sDGNRS `INITIAL_SUPPLY` — the other **80%** funds game
pools, not the creator (`sDGNRS.sol:303-310,381-399`):

| Pool | Share | Constant |
|---|---|---|
| Affiliate | 30% | `AFFILIATE_POOL_BPS = 3000` |
| Lootbox | 20% | `LOOTBOX_POOL_BPS = 2000` |
| Whale | 10% | `WHALE_POOL_BPS = 1000` |
| Reward | 10% | `REWARD_POOL_BPS = 1000` |
| Presale box | 10% | `PRESALE_BOX_POOL_BPS = 1000` |
| *(Creator)* | *20%* | *`CREATOR_BPS = 2000`* |

Sum = 10,000 bps (100%); any rounding dust is retained by the reserve (`sDGNRS.sol:387-399`).

### (c) Presale box — a bounded initial coin offering (≤40 ETH to the creator)

The presale box is a **primary sale at genesis**: buyers voluntarily exchange ETH for presale-box
credits (backed by the 10% presale-box sDGNRS pool, §2b). It is an initial offering of coin — **not a
rake**; no fee is taken from player gameplay. Total presale-box ETH is capped at **50 ETH**
(`PRESALE_BOX_ETH_CAP = 50 ether`, `storage/DegenerusGameStorage.sol:1477`); proceeds route **80% to
the vault (creator), 20% to sDGNRS** (`_creditBoxProceeds`, `modules/DegenerusGamePayoutUtils.sol:20-26`),
with `claimablePool` bumped by the full amount so solvency holds. The creator's proceeds are therefore
**bounded at ≈40 ETH** (80% of the 50-ETH cap; the integer-division remainder — at most a few
thousand wei — rounds to the vault).

On top of the ETH proceeds, presale boxes distribute DGNRS to buyers from the 10% presale-box pool on a
tiered curve (`_presaleBoxDgnrsReward`, `modules/DegenerusGameLootboxModule.sol:807,841`). The vault's
default-referrer position (§2a) captures the affiliate share of DGNRS on unreferred presale spend — the
builder estimates this at ~20% of the distributed DGNRS, roughly **2 ETH-equivalent** — so the full
presale-side creator take is ≈40 ETH plus ~2 ETH of DGNRS.

Everything else is rake-free: all lootbox and post-genesis ticket ETH routes **100% to the prize
pools** (`modules/DegenerusGameMintModule.sol:117-118`) — none to the creator. Presale-box eligibility
is **earned by playing** during the presale window (`presaleBoxCredit` accrues as 25% of spend),
not bought.

## 3. Creator DGNRS vesting

Level-gated, defined in `DGNRS.sol:95-97,211-222`:

```
vested = CREATOR_INITIAL + level × VEST_PER_LEVEL,  capped at CREATOR_TOTAL
       = 50B          + level × 5B,                capped at 200B
```

- `CREATOR_INITIAL = 50_000_000_000e18` — released at deploy.
- `VEST_PER_LEVEL  = 5_000_000_000e18` — one increment per game level advanced.
- `CREATOR_TOTAL   = 200_000_000_000e18` — hard cap; `claimVested()` reverts once reached.

The creator cannot claim ahead of level progression — vesting tracks the game actually
advancing, which requires real player activity. Only the 50B is minted to `CREATOR` at deploy; the
vesting increments are paid to **whoever holds the DGVE majority** at claim time (`claimVested` gates
on `isVaultOwner`, `DGNRS.sol:211-212`), so the unvested ~150B follows vault ownership rather than the
original creator irrevocably. Throughout this document, "the creator" means the initial DGVE majority
holder; that authority — and these claims — move with the DGVE token.

## 4. Governance / who controls what

- **Admin authority follows >50.1% of DGVE.** Because the creator holds 100% of DGVE at deploy
  (§2), the creator is the **initial admin**. DGVE is an ERC-20 share class; authority moves
  with the token.
- **Admin powers are narrowly scoped** and cannot touch player funds: ETH→stETH liquidity conversion
  the lootbox RNG threshold, and recovery sweeps of foreign assets mistakenly sent to the vault (stETH excluded). LINK donors accrue mid-day lootbox-RNG request credit, billed at the redemption-time LINK price, that waives the threshold's pending-value gates for requests they trigger — an operational perk that moves no player value. The VRF-coordinator and LINK price-feed swaps are **gated proposals,
  not free configuration** — the admin path requires the feed/VRF to be unhealthy/stalled for a delay
  (2d+ for the feed, longer for VRF), and there is a parallel sDGNRS-voting community path
  (`DegenerusAdmin.sol:727`). Full matrix and bounds: [`SECURITY.md`](SECURITY.md).
- **Community path:** 0.5%+ voting sDGNRS can propose a VRF-coordinator swap after a 7-day VRF stall,
  or a feed swap after 7 days of an unhealthy feed.
- **The one admin power that reaches player pricing: thanos-level declaration.**
  `DegenerusGame.setThanosLevel(targetLevel, shift)` (`DegenerusGame.sol:653-677`) declares that every
  ticket entry drained for `targetLevel` onward divides by `2^shift` — i.e. it raises the effective
  entry price, and the foil-pack price, from that level on. On the plain ticket the raise is
  EV-neutral (price fixed, entries divided, the division cancelling in the pot-share fraction); on
  the foil pack it is a real value cut, because no foil payout scales with the exponent — a
  declaration deliberately makes that SKU bad value while in force. Disclosed here because it is economic, not
  merely operational. It moves **no ETH**, credits nothing to the vault, and cannot touch
  `claimablePool` or any player balance; it is bounded to a *prospective* change: `targetLevel >=
  level + 6` (which lands it strictly before the target level's first materialization, so one level's
  entries always share one exponent and the uniform division cancels in the pot-share fraction —
  a raw entry's replacement cost and expected pot share are both unchanged), `shift <= 8`, immutable
  once its 6-level window opens, and undeclarable non-zero until the target level's projected entries
  exceed 40,000,000 after division. Full bounds: [`SECURITY.md`](SECURITY.md) role 2.

## 5. WWXRP reserve, the initial FLIP program, and the WWXRP draw

Neither FLIP nor WWXRP is minted to the creator's balance at deploy.

- **Only WWXRP has a deploy-time reserve.** `INITIAL_VAULT_ALLOWANCE = 1_000_000_000e18` seeds
  `vaultAllowance` (`WWXRP.sol:271,275`) — an *"uncirculating reserve the vault can mint from"* via
  `vaultMintTo` (vault-only, `WWXRP.sol:587-597`). Since the vault is creator-owned (§2a), that 1B is
  effectively creator-controllable supply.
- **FLIP starts fully zero.** Both `totalSupply` and `vaultAllowance` are 0 at deploy (`FLIP.sol:175-185`,
  *"Starts fully zero"*) — there is **no** deploy-time FLIP reserve. The vault's FLIP mint allowance
  accrues later from vault operations (the DGVF claim leg — `DegenerusVault.sol:155,785-798`, where the vault's redeemable FLIP is read as mint allowance + balance + claimable coinflips), not a premine.
- **Initial FLIP program (first 20 days).** The Coinflip contract stakes **200k FLIP/day** each to the
  vault and sDGNRS (~4M gross each), but these are **coinflip stakes contingent on the flip outcome**,
  not a guaranteed allocation (`FLIP.sol:16-17`, `Coinflip.sol:154`).

WWXRP is a deliberately meme/worthless game token. Its **daily burn draw**: burn ≥25 WWXRP (`MIN_BURN`)
to enter. Each day carries a **global** 1/365 chance of being a big-prize day and, failing that, 1/30
of a small-prize day (`BIG_GATE`/`SMALL_GATE` — day-level gates, *not* per-entrant odds). On a prize day
one of 10 buckets and one activity-weighted entrant is selected (an empty selected bucket yields no
prize); the winner receives `BIG_PRIZE = 100_000` / `SMALL_PRIZE = 10_000` FLIP as coinflip credit via
`coinflip.creditFlip` (`WWXRP.sol:314-324,722-723`).

**The century BAF incinerator is the one WWXRP burn utility that pays ETH.** A daily-draw burn made
during a level ×99 additionally records a burn-weighted entry betting that the upcoming ×00 BAF
*skips* (its flip loses). If it does, 25% of the would-be BAF pool — 25% of 20% of the future pool, so
5% of it — pays one entrant drawn over the burn-weighted intervals; the rest rolls forward in
`futurePool` exactly as on any other skip, and an empty bracket leaves the full pool
(`WWXRP.resolveIncinerator` at `WWXRP.sol:955-991`, paid game-side at
`modules/DegenerusGameAdvanceModule.sol:1248-1256`). This is a **player-to-player transfer inside the
prize pool**, not a new inflow and not a creator take: the ETH was already players' future-pool ETH and
5% of it is redirected to a burner instead of rolling forward. Entries close when the level increments
off ×99 — the same transaction that requests the VRF word whose bit 0 decides the flip — so no entry
can be placed after the deciding word could exist. On a *fired* (won) BAF the bracket is simply never
resolved: the burn was the losing side of the hedge, and the daily-draw entry it rode on still settles
normally.

## 6. EV and redemption (honesty about the gamble)

- **Tickets are typically −EV** and provably fair — jackpots pay trait-matched holders by VRF.
  Under some conditions (pool size, level velocity, trait scarcity) a ticket can be +EV, but the
  baseline expectation is negative (README, "Tickets").
- **The golden-ticket grand is the single largest one-shot payout, and it is a redistribution.**
  One winner takes **25% of `futurePrizePool` in ETH** plus a headline spanning the three prize pools
  and the yield accumulator, paid 75% in half whale passes and 25% as flip credit
  (`_payGoldenTicket`, `modules/DegenerusGameJackpotModule.sol:1500,1534-1543`). Two routes reach the
  same body of code, so the amounts cannot drift: the **board route**, when an armed golden ticket
  resolves against a main board that rolled four golds with the armed quadrant repeating its armed
  symbol (`_resolveGoldenTicket:1173`, driven from `payDailyJackpot:377`); and the **foil route**,
  when a foil pack's sixteen quadrants come out holding two or more all-gold tickets, pushed by the
  foil drain (`payGoldenTicketGrand:1224` ← `_pushFoilGrand`,
  `modules/DegenerusGameFoilPackModule.sol:1157`). Like the century BAF incinerator, this is a
  **player-to-player transfer inside the prize pool** — the ETH was already players' future-pool ETH
  and no part of it reaches the creator or the vault. Both routes are decided by a sealed VRF word
  before either can be claimed, and the foil route is ~1 pack in 7.1 billion, so it prices as a
  lottery rather than a subsidy. Below it the foil pack pays a fixed FLIP ladder on its total gold
  count (20k/80k/250k/750k/2.5M/7.5M for 3 through 8+ golds, plus 25,000 when exactly one whole
  ticket comes out all gold) — free-minted coin, not pool ETH.
- **Lootboxes and passes are designed to be +EV for engaged buyers.** The mechanism is an
  activity-score multiplier that raises the reward basis for players active enough to earn it (capped
  per-account per-level). This is a design goal realized through sustained play — not a guaranteed
  per-open ETH profit for a casual buyer. They fund prize pools up front and receive future-level
  tickets in return.
- **The growth parimutuel is pure redistribution.** `DegenerusParimutuel` books one fixed
  1,000-FLIP stake per address per round on whether the next level's pool growth beats the
  current level's (exact cross-multiplied comparison; a push resolves UNDER). Stakes are burned
  at placement and winners are re-minted at most what the round burned, so the market can never
  inflate FLIP — a round whose winning side is empty leaves the losing side burned. The
  attached participation quest (150/75/37/18 FLIP by jackpot-phase day, once per level per
  address, gated on level-quest eligibility or an active AFKing run) is an emission — the
  incentive to participate — capped at 150 FLIP against the 1,000-FLIP stake it requires.
- **Redemption is not simple proportional during the live game.** Burning sDGNRS/DGNRS enters an
  RNG-gated redemption that rolls **25%–175%** of the proportional share, with daily caps, a **50/50
  direct-ETH / lootbox split**, forfeiture of sub-minimum lootbox legs, and contingent FLIP
  settlement (`sDGNRS.sol:310-312,326-332,845`). It becomes deterministic proportional **only after game
  over**.
- **The FLIP side of that backing is staked, not held.** FLIP routed to sDGNRS (both transfers and
  mints — e.g. a box-spin win on its own self-subscription) never enters `totalSupply`; it is placed on
  the *next* day's coinflip via `Coinflip.creditSdgnrsBacking`, day-keyed like any other deposit. So
  sDGNRS's redeemable FLIP backing is its genesis seed reserve (`claimableStored`, which redemption
  burns drain first) plus the rolling 0-take-profit auto-rebuy carry, and it moves with coinflip
  outcomes rather than sitting still. FLIP is the game's own coin and no ETH/stETH solvency term
  depends on this — the ETH half of a redemption is segregated out of the game at submit and is
  unaffected.
- Coinflip and Degenerette are calibrated games; their by-design dispositions (not a full RTP model)
  are documented in [`KNOWN-ISSUES.md`](KNOWN-ISSUES.md).

## 7. Terminal value (game over)

On a liveness-guard game-over (`modules/DegenerusGameGameOverModule.sol`):

1. Deity-pass refunds — purchase-price-capped (≤20 ETH), FIFO, budget-limited, if the game ends before
   level 10.
2. Decimator death-bet holders receive a 10% budget; the refunded remainder returns to the ticket
   cohort.
3. **30-day final sweep** (`handleFinalSweep`, `GameOverModule:220-261`): each sink (vault, sDGNRS,
   GNRUS) is first paid the claimable it earned in-game; **all other unclaimed player balances are then
   forfeited**; the remainder is split ~1/3 each (GNRUS absorbs dust). The same sweep **shuts down the
   VRF subscription and sends remaining LINK to the vault**.

Additional creator-side (vault) terminal inflows:

- **1 year post-gameover:** remaining DGNRS backing is swept **50/50 to GNRUS and VAULT** (`yearSweep`,
  `DGNRS.sol:312-330`).
- **3 years after the final sweep:** residual GNRUS backing can route to the VAULT (`GameOverModule`
  GNRUS recovery gates).

## 8. No passive insider allocations

There are **no VC, KOL, advisor, market-maker, private-round, or discounted third-party token
allocations.** The only privileged economic positions are the builder/vault allocations disclosed
above (§2, §5, §7) — every one traceable to a contract constant. Affiliate rewards are an on-chain
gameplay role open to every player under identical rules: an affiliate code confers no discounted
purchase and no preallocated tokens. The vault's default-referrer role (§2a) does not sell anything at
a discount — it simply routes the referral rewards of players who chose no referrer. Any bootstrap
affiliate codes or referral mappings set at deployment are referral *configuration*, not token
allocations, and will be recorded in the deployment manifest.

---

### What is deliberately *not* stated here

- **No ETH return projections.** sDGNRS/DGNRS are game tokens redeemable via an RNG-gated
  gambling-burn (§6), deterministic only after game over — not ETH-pegged instruments. Any ETH figure
  depends on player
  activity that does not exist pre-deploy.
- **No production deployment manifest / bytecode hashes.** Those are added at mainnet launch
  (see README, "Deployment"); the committed addresses are the deterministic test set.
