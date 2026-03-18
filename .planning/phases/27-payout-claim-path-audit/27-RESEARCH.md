# Phase 27: Payout/Claim Path Audit - Research

**Researched:** 2026-03-17
**Domain:** Smart contract security audit -- normal-gameplay distribution systems, claim mechanisms, CEI ordering, pool accounting
**Confidence:** HIGH

## Summary

Phase 27 covers the audit of every normal-gameplay payout and claim path in the Degenerus protocol -- 19 requirements (PAY-01 through PAY-19) spanning 5 major distribution categories: jackpot draws, scatter/decimator events, ancillary payouts (coinflip, lootbox, quest, affiliate), token burn redemptions (sDGNRS/DGNRS), and ticket mechanics (conversion, futurepool, auto-rebuy). This is the largest single audit phase in the v3.0 milestone, touching approximately 15,000 lines of Solidity across 15 contracts and modules.

The GAMEOVER path (Phase 26) has already been fully audited with 8 PASS and 1 FINDING-MEDIUM. Phase 27 focuses exclusively on the normal-gameplay distribution paths that operate during active play. Many of these paths share common infrastructure: `_addClaimableEth` -> `_creditClaimable` -> `claimableWinnings[player]` -> `claimablePool` for ETH credits, and `coin.creditFlip()` / `coin.creditFlipBatch()` for BURNIE credits. The central claim function `claimWinnings()` in DegenerusGame.sol uses correct CEI pattern (sentinel -> claimablePool decrement -> external call), verified in Phase 26.

The primary risk surfaces for this phase are: (1) incorrect pool source/pairing in distribution formulas (e.g., drawing from wrong pool or overcounting), (2) claim paths that allow double-claiming or claim more than entitled, (3) auto-rebuy carry calculations that could amplify extraction, (4) sDGNRS/DGNRS burn redemption math that could drain more than proportional share, and (5) rounding/truncation errors that accumulate across many small payouts. The v1.1 economics reference documents (13 files, ~8,500 lines) provide the specification against which each distribution formula must be verified.

**Primary recommendation:** Organize the audit into 4-5 waves by distribution category. For each requirement, read the relevant contract code line-by-line, verify the formula against the v1.1 specification doc, trace every claimablePool/claimableWinnings mutation, verify CEI ordering, and check for double-claim guards. Deliver explicit PASS or FINDING verdicts with file:line references.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| PAY-01 | Daily jackpot (purchase phase) audited -- ETH distribution formula, winner selection, claim mechanism verified | JackpotModule:630-688, v1.1-purchase-phase-distribution.md. 1% futurePrizePool drip, 75%/25% lootbox/ETH split, 4 trait buckets at 20% each. |
| PAY-02 | Daily jackpot (jackpot phase) audited -- 5-day draw sequence, prize scaling, unclaimed handling verified | JackpotModule:336-627, v1.1-jackpot-phase-draws.md. 6-14% random BPS days 1-4, 100% day 5, compressed/turbo modes, 60/13/13/13 day-5 shares. |
| PAY-03 | BAF normal scatter payout audited -- trigger conditions, recipient selection, payout calculation verified | EndgameModule:138-400, DegenerusJackpots.sol, v1.1-transition-jackpots.md. 10% futurePool (20% at L50/x00), 7-category prize split, large/small winner classification. |
| PAY-04 | BAF century scatter payout audited -- century trigger, enhanced payout calculation, distribution verified | EndgameModule:175-184. x00 BAF uses 20% of baseFuturePool snapshot, different scatter sampling (4 rounds each at lvl+1/+2/+3, 38 rounds random past 99 levels). |
| PAY-05 | Decimator normal claims audited -- claimDecimatorJackpot path, round tracking, lastDecClaimRound logic verified | DecimatorModule:297-547, DegenerusGame:1293-1305. Pro-rata formula, 50/50 ETH/lootbox split, lastDecClaimRound overwrite expiry. |
| PAY-06 | Decimator x00 claims audited -- century decimator claim path, enhanced payout, eligibility verified | EndgameModule:175-184. 30% of baseFuturePool (vs 10% normal), uses same claim mechanism but separate resolution. |
| PAY-07 | Coinflip deposit/win/loss paths audited -- claimCoinflips, claimCoinflipsFromBurnie, auto-rebuy carry verified | BurnieCoinflip:231-627. Burn-and-mint model, 50/50 VRF outcome, variable multiplier (1.5x-2.5x), auto-rebuy carry with recycling bonus. |
| PAY-08 | Coinflip bounty system audited -- bounty trigger, DGNRS gating (50k bet, 20k pool), payout verified | BurnieCoinflip:634-693 (arming), 849-879 (resolution). Half of bounty to winner as flip stake, 1000 BURNIE/day accumulation. |
| PAY-09 | Lootbox rewards audited -- whale passes, lazy passes, deity passes, future tickets, BURNIE payouts verified | LootboxModule:1-1778, EndgameModule:405-488 (ticket tiers), PayoutUtils:77-93 (whale pass queue). |
| PAY-10 | Quest rewards and streak bonuses audited -- trigger conditions, reward calculations, streak mechanics verified | DegenerusQuests:1-1598. Slot 0 = 100 BURNIE, slot 1 = 200 BURNIE, streak up to 100 days contributing 10000 BPS to activity score. |
| PAY-11 | Affiliate commissions audited -- 3-tier system, taper schedule, ETH and DGNRS claim paths verified | DegenerusAffiliate:557-930, DegenerusGame:1458-1479. Weighted random lottery, 0.5 ETH cap per sender per level, lootbox taper 100%->25%. |
| PAY-12 | stETH yield distribution audited -- 50/25/25 split, accumulator milestone payouts verified | AdvanceModule (yield distribution), DegenerusGame:2138-2154 (yieldPoolView). 23% sDGNRS/23% vault/46% accumulator, x00 milestone 50% release. |
| PAY-13 | Accumulator milestone payouts audited -- milestone thresholds, payout triggers, distribution verified | AdvanceModule (x00 milestone logic). yieldAccumulator grows via 46% yield surplus + 1% insurance skim (INSURANCE_SKIM_BPS=100). At x00: 50% to futurePrizePool, 50% retained. |
| PAY-14 | sDGNRS burn() audited -- ETH/stETH/BURNIE proportional redemption math verified | StakedDegenerusStonk:373-462. totalMoney = ETH + stETH + claimable, proportional: (totalMoney * amount) / supplyBefore. ETH-preferred ordering. |
| PAY-15 | DGNRS wrapper burn() audited -- delegation to sDGNRS, unwrap mechanics verified | DegenerusStonk:164-223. Burns DGNRS, calls sDGNRS.burn(amount), forwards ETH/stETH/BURNIE. unwrapTo converts DGNRS to soulbound sDGNRS. |
| PAY-16 | Ticket conversion and futurepool mechanics audited -- conversion formula, futurepool allocation, rollover verified | JackpotModule:1096-1135 (_budgetToTicketUnits, _distributeLootboxAndTickets). 2x over-collateralization, priced at lvl+1. Pool transitions: futurePool->nextPool->currentPool->claimablePool. |
| PAY-17 | Advance bounty system audited -- trigger, payout calculation, claim mechanism verified | AdvanceModule:112-376. 0.01 ETH of BURNIE per advance call, 2x/3x multipliers on jackpot/transition days, credited via coin.creditFlip(). |
| PAY-18 | WWXRP consolation prizes audited -- distribution logic, value transfer paths verified | BurnieCoinflip:623 (1 WWXRP per loss day), WrappedWrappedXRP:384 (burnForGame). Also minted via LootboxModule deity rolls. |
| PAY-19 | Coinflip recycling and boons audited -- recycled BURNIE flow, boon mechanics verified | BurnieCoinflip:1042-1066 (recycling), 643-653 (boon application). Normal 1% capped at 1000 BURNIE, afKing 1.6% base + deity up to 3.1%. Boons single-use, 2-day expiry, 100k cap. |
</phase_requirements>

## Standard Stack

This is a security audit phase, not an implementation phase. The "stack" is the audit methodology and source contracts.

### Core: Contracts Under Audit (19 Requirements Mapped)

| Contract | Location | Lines | PAY Requirements | Risk Level |
|----------|----------|-------|-----------------|------------|
| DegenerusGameJackpotModule.sol | contracts/modules/ | 2819 | PAY-01, PAY-02, PAY-16 | CRITICAL -- largest module, all jackpot distribution |
| DegenerusGameEndgameModule.sol | contracts/modules/ | 540 | PAY-03, PAY-04, PAY-09 (lootbox tiers) | HIGH -- BAF scatter, whale pass claim |
| DegenerusGameDecimatorModule.sol | contracts/modules/ | 1027 | PAY-05, PAY-06 | HIGH -- decimator claims, round tracking |
| BurnieCoinflip.sol | contracts/ | 1154 | PAY-07, PAY-08, PAY-18, PAY-19 | HIGH -- coinflip economy, bounty, recycling |
| DegenerusAffiliate.sol | contracts/ | 847 | PAY-11 | MEDIUM -- affiliate commissions, weighted lottery |
| DegenerusGame.sol | contracts/ | 2856 | PAY-01-19 (claim dispatch) | HIGH -- claimWinnings, claimDecimatorJackpot, claimAffiliateDgnrs, claimWhalePass dispatch |
| DegenerusGameAdvanceModule.sol | contracts/modules/ | 1383 | PAY-12, PAY-13, PAY-17 | MEDIUM -- yield distribution, accumulator, advance bounty |
| DegenerusGameLootboxModule.sol | contracts/modules/ | 1778 | PAY-09 | MEDIUM -- lootbox reward resolution, deity boon drops |
| StakedDegenerusStonk.sol | contracts/ | 514 | PAY-14 | MEDIUM -- sDGNRS burn-for-backing, pool management |
| DegenerusStonk.sol | contracts/ | 223 | PAY-15 | LOW -- thin DGNRS wrapper delegating to sDGNRS |
| DegenerusQuests.sol | contracts/ | 1598 | PAY-10 | MEDIUM -- quest reward creditFlip, streak mechanics |
| DegenerusGamePayoutUtils.sol | contracts/modules/ | 94 | PAY-01-09 (shared) | CRITICAL -- _creditClaimable, auto-rebuy, whale pass queue |
| BurnieCoin.sol | contracts/ | ~860 | PAY-07, PAY-10, PAY-11, PAY-17 | MEDIUM -- creditFlip routing, burnForCoinflip |
| WrappedWrappedXRP.sol | contracts/ | 389 | PAY-18 | LOW -- WWXRP mint/burn for consolation |
| DegenerusJackpots.sol | contracts/ | varies | PAY-03, PAY-04 | MEDIUM -- BAF jackpot winner selection |

### Supporting: Audit Reference Documents

| Document | Location | Purpose | PAY Coverage |
|----------|----------|---------|-------------|
| v1.1-purchase-phase-distribution.md | audit/ | Daily drip + BURNIE jackpot spec | PAY-01 |
| v1.1-jackpot-phase-draws.md | audit/ | 5-day draw sequence spec | PAY-02 |
| v1.1-transition-jackpots.md | audit/ | BAF + Decimator spec | PAY-03, PAY-04, PAY-05, PAY-06 |
| v1.1-burnie-coinflip.md | audit/ | Coinflip mechanics spec | PAY-07, PAY-08, PAY-19 |
| v1.1-affiliate-system.md | audit/ | Affiliate commission spec | PAY-11 |
| v1.1-steth-yield.md | audit/ | stETH yield distribution spec | PAY-12, PAY-13 |
| v1.1-quest-rewards.md | audit/ | Quest reward spec | PAY-10 |
| v1.1-dgnrs-tokenomics.md | audit/ | sDGNRS/DGNRS burn mechanics | PAY-14, PAY-15 |
| v1.1-level-progression.md | audit/ | Ticket pricing, pool targets | PAY-16 |
| v1.1-parameter-reference.md | audit/ | All constant cross-reference | PAY-01-19 |
| Economics Primer | audit/v1.1-ECONOMICS-PRIMER.md | Overview of all economic flows | PAY-01-19 |

## Architecture Patterns

### Payout Infrastructure: The Two Credit Paths

All normal-gameplay payouts ultimately credit value through exactly two paths:

**Path 1: ETH Credits (claimableWinnings + claimablePool)**
```
Distribution event -> _addClaimableEth(player, amount, rngWord)
  -> If auto-rebuy enabled: convert to tickets, credit remainder
  -> _creditClaimable(player, weiAmount)
    -> claimableWinnings[player] += weiAmount  (unchecked)
    -> emit PlayerCredited
  -> Caller tracks claimablePool += delta  (liability delta returned)

Player claims -> claimWinnings(player)
  -> claimableWinnings[player] = 1  (sentinel)
  -> payout = amount - 1
  -> claimablePool -= payout  (CEI: state update before call)
  -> _payoutWithStethFallback(player, payout)  (ETH -> stETH -> ETH retry)
```

**Path 2: BURNIE Credits (coinflip stakes)**
```
Distribution event -> coin.creditFlip(player, amount) or coin.creditFlipBatch(players, amounts)
  -> BurnieCoin routes to BurnieCoinflip.creditFlip/creditFlipBatch
  -> Credited as next-day coinflip wager (NOT direct token transfer)
  -> Player must claim via claimCoinflips() after resolution

Player claims -> claimCoinflips(player, amount)
  -> Process win/loss for each day in claim window
  -> Win: mint BURNIE (payout = stake * (1 + rewardPercent/100))
  -> Loss: principal permanently destroyed, mint 1 WWXRP consolation
  -> Auto-rebuy: carry forward to next day's wager
```

### claimablePool Mutation Sites (Normal Gameplay)

The following are the non-GAMEOVER sites where claimablePool is incremented during normal play. Every PAY requirement must trace its claimablePool mutations:

| Module | Function | Direction | PAY Reqs |
|--------|----------|-----------|----------|
| PayoutUtils:30 | `_creditClaimable` | UP | PAY-01 through PAY-06 (via _addClaimableEth) |
| PayoutUtils:90 | `_queueWhalePassClaimCore` (remainder) | UP | PAY-03, PAY-05 (large winner whale pass remainder) |
| DegenerusGame:1440 | `_claimWinningsInternal` | DOWN | All PAY (player withdrawal) |
| JackpotModule:1504 | `_distributeJackpotEth` (daily/carryover) | UP (via delta) | PAY-01, PAY-02 |
| EndgameModule:371/391 | BAF winner credit | UP (via delta) | PAY-03, PAY-04 |
| DecimatorModule:478/490/519 | Decimator claim credit | UP | PAY-05, PAY-06 |
| DegeneretteModule:704 | Degenerette ETH payout | UP | (not in PAY scope) |

### Distribution Category Map

The 19 requirements organize naturally into 5 audit waves:

**Wave 1: Jackpot Distribution (PAY-01, PAY-02, PAY-16)**
- Purchase-phase daily drip (1% futurePrizePool, 75/25 lootbox/ETH)
- Jackpot-phase 5-day draws (6-14% random, compressed/turbo modes)
- Ticket conversion and futurepool mechanics
- Shared infrastructure: _executeJackpot, _distributeLootboxAndTickets, _budgetToTicketUnits

**Wave 2: Scatter and Decimator (PAY-03, PAY-04, PAY-05, PAY-06)**
- BAF normal (10% futurePool) and century (20% baseFuturePool)
- Decimator normal (10% futurePoolLocal) and x00 (30% baseFuturePool)
- Claim validation, round tracking, expiry mechanics
- Pool source distinction: baseFuturePool vs futurePoolLocal

**Wave 3: Coinflip Economy (PAY-07, PAY-08, PAY-18, PAY-19)**
- Deposit/resolution/claim lifecycle
- Bounty system (arming, accumulation, resolution)
- WWXRP consolation prizes
- Recycling bonuses and boon mechanics
- Auto-rebuy carry calculations

**Wave 4: Ancillary Payouts (PAY-09, PAY-10, PAY-11, PAY-12, PAY-13, PAY-17)**
- Lootbox rewards (whale/lazy/deity passes, future tickets, BURNIE)
- Quest rewards and streak bonuses
- Affiliate commissions (3-tier, taper, DGNRS claim)
- stETH yield distribution and accumulator milestones
- Advance bounty system

**Wave 5: Token Burns and Verification (PAY-14, PAY-15)**
- sDGNRS burn() proportional redemption (ETH + stETH + BURNIE)
- DGNRS wrapper burn() delegation
- Cross-wave verification of claimablePool invariant

### Key State Variables for Claim Path Auditing

| Variable | Type | Purpose | Mutation Risk |
|----------|------|---------|---------------|
| `claimablePool` | uint256 | Total ETH reserved for all claims | CRITICAL -- must equal sum of all claimableWinnings minus sentinels |
| `claimableWinnings[player]` | mapping(address => uint256) | Per-player ETH credit | Uses 1 wei sentinel; unchecked increment |
| `lastDecClaimRound` | struct | Most recent decimator snapshot | Overwrites on each resolution -- old claims expire |
| `whalePassClaims[player]` | mapping(address => uint256) | Deferred whale pass half-passes | No expiry; must verify no double-claim |
| `affiliateDgnrsClaimedBy[lvl][player]` | mapping(uint24 => mapping(address => bool)) | Per-level DGNRS claim guard | One claim per level per player |
| `decBurn[lvl][player]` | DecEntry struct | Decimator burn tracking | `claimed` flag prevents double-claim |
| `prizePoolFrozen` | bool | Blocks decimator claims during jackpot phase | Prevents futurePool corruption |
| `gameOver` | bool | GAMEOVER state -- disables auto-rebuy, changes decimator claim to 100% ETH | Phase 26 verified |

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Audit methodology | Custom checklist | C4A warden methodology: PASS/FINDING verdicts with file:line references | Industry standard, matches audit target |
| Formula verification | Mental math | Side-by-side code-vs-spec comparison using v1.1 reference docs | 13 specification docs exist specifically for this |
| claimablePool invariant tracking | Spot checks | Exhaustive mutation trace per requirement | Phase 26 demonstrated this methodology at all 6 GAMEOVER sites |
| Double-claim analysis | Ad-hoc scanning | Systematic guard verification for each claim path | Every claim path has a distinct guard mechanism |
| Auto-rebuy extraction analysis | Theoretical reasoning | Step-by-step trace with specific numerical examples | Rounding/truncation effects need concrete walkthrough |

## Common Pitfalls

### Pitfall 1: Pool Source Confusion (CP-01)
**What goes wrong:** BAF/Decimator pool percentages are applied to the wrong source variable
**Why it happens:** Three similar variables exist: `baseFuturePool` (snapshot at entry), `futurePoolLocal` (running total after BAF deduction), and `futurePrizePool` (storage). x00 Decimator uses `baseFuturePool` (before deduction), normal Decimator uses `futurePoolLocal` (after BAF deduction).
**How to avoid:** Always verify which pool variable each distribution reads from. Cross-reference with v1.1-transition-jackpots.md Section 1 "Execution Order."
**Warning signs:** A distribution formula reading `_getFuturePrizePool()` when it should use a local snapshot variable.

### Pitfall 2: Decimator Claim Expiry as Feature (CP-02)
**What goes wrong:** Auditor flags claim expiry as a vulnerability when it's by-design
**Why it happens:** `lastDecClaimRound` overwrites on each resolution, permanently expiring prior claims. This seems like it could brick funds, but it's intentional -- the economics docs explicitly state this.
**How to avoid:** Verify the expiry is documented in v1.1-transition-jackpots.md Section 8 ("Claims expire when the next decimator resolves"). Flag as INFO if undocumented in natspec, not as a vulnerability.
**Warning signs:** Finding that says "unclaimed decimator funds are lost" without checking design intent.

### Pitfall 3: Auto-Rebuy Extraction via Rounding (CP-03)
**What goes wrong:** Auto-rebuy calculations create more ticket value than the ETH credited
**Why it happens:** Auto-rebuy includes a bonus (130% for normal, 145% for afKing), and ticket price rounding could amplify this
**How to avoid:** Trace `_calcAutoRebuy` in PayoutUtils:38-74. Verify `ethSpent = baseTickets * ticketPrice` is deducted from the credit, and bonus tickets are genuinely free (funded by protocol incentive, not accounting error).
**Warning signs:** `ticketCount` calculation that multiplies by bonusBps WITHOUT subtracting from the ETH credit.

### Pitfall 4: sDGNRS Burn Proportionality with Pending Claims (CP-04)
**What goes wrong:** sDGNRS burn() includes `claimableWinnings` from the game contract in `totalMoney`, but these winnings haven't been withdrawn yet, so the burn payout could exceed available balance
**Why it happens:** `totalMoney = ethBal + stethBal + claimableEth`. If multiple burns happen before `claimWinnings` is called, each burn computes share based on the full claimable amount.
**How to avoid:** Verify that sDGNRS.burn() calls `game.claimWinnings()` to pull pending winnings before computing proportional share. Check StakedDegenerusStonk:373-462 for the claim-then-compute ordering.
**Warning signs:** `_claimableWinnings()` returning a non-zero value that's included in totalMoney but not yet converted to actual balance.

### Pitfall 5: Coinflip Claim Window Asymmetry (CP-05)
**What goes wrong:** First-time claimants lose winnings after 30 days; returning claimants have 90 days
**Why it happens:** `COIN_CLAIM_FIRST_DAYS = 30` vs `COIN_CLAIM_DAYS = 90`. First-time players may not realize the shorter window.
**How to avoid:** Verify this is by-design (documented in v1.1-burnie-coinflip.md Section 7). Classify as INFO if not documented in contract natspec.
**Warning signs:** Player claiming after 31 days with no prior activity losing all accumulated winnings.

### Pitfall 6: Affiliate DGNRS Sequential Depletion (CP-06)
**What goes wrong:** Early claimants per level get more DGNRS than late claimants because the pool shrinks with each claim
**Why it happens:** `levelShare = (poolBalance * 500) / 10_000` is recomputed on each claim; early claims reduce `poolBalance`.
**How to avoid:** NOTE: The actual contract code at DegenerusGame:1458-1479 uses `levelDgnrsAllocation[currLevel]` and `totalAffiliateScore[currLevel]` as a fixed denominator, which eliminates first-mover advantage. The v1.1 doc describes the old mechanism. Verify which version is live in the current code.
**Warning signs:** Discrepancy between v1.1 doc description and actual contract implementation.

### Pitfall 7: Whale Pass Claim Has No Expiry (CP-07)
**What goes wrong:** Whale pass claims (`whalePassClaims[player]`) accumulate without expiry
**Why it happens:** Unlike decimator claims (expire on next resolution), whale pass claims persist indefinitely
**How to avoid:** Verify this is intentional. Check if `claimWhalePass` has any time-based restrictions. Review EndgameModule:515 for guard conditions.
**Warning signs:** None -- permanent claimability is likely intentional for large winners.

### Pitfall 8: WWXRP Mint Authority (CP-08)
**What goes wrong:** WWXRP minted by coinflip losses could be extracted if mintPrize is callable by unauthorized addresses
**Why it happens:** `wwxrp.mintPrize` is called from BurnieCoinflip
**How to avoid:** Verify WrappedWrappedXRP:384 restricts `burnForGame`/`mintPrize` to authorized callers only. Check access control.
**Warning signs:** Missing access control on mint functions.

## Code Examples

### Example 1: Central Claim Path (DegenerusGame.sol:1431-1447)

```solidity
function _claimWinningsInternal(address player, bool stethFirst) private {
    if (finalSwept) revert E();
    uint256 amount = claimableWinnings[player];
    if (amount <= 1) revert E();
    uint256 payout;
    unchecked {
        claimableWinnings[player] = 1; // Leave sentinel -- CEI: effects
        payout = amount - 1;
    }
    claimablePool -= payout; // CEI: effects (global state)
    emit WinningsClaimed(player, msg.sender, payout);
    if (stethFirst) {
        _payoutWithEthFallback(player, payout);    // CEI: interaction
    } else {
        _payoutWithStethFallback(player, payout);  // CEI: interaction
    }
}
```

**Audit checklist for this function:**
- Sentinel pattern (1 wei) prevents re-entrancy and zero-claim
- `claimablePool -= payout` before external call (correct CEI)
- `finalSwept` guard prevents claims after GAMEOVER final sweep
- `_resolvePlayer` in caller resolves address(0) to msg.sender

### Example 2: _creditClaimable (PayoutUtils.sol:30-36)

```solidity
function _creditClaimable(address beneficiary, uint256 weiAmount) internal {
    if (weiAmount == 0) return;
    unchecked {
        claimableWinnings[beneficiary] += weiAmount;
    }
    emit PlayerCredited(beneficiary, beneficiary, weiAmount);
}
```

**Audit checklist:**
- Uses unchecked addition -- verify that total claimable per player cannot overflow uint256
- No claimablePool increment here -- caller must track delta
- Zero-amount guard prevents spurious events

### Example 3: Decimator Pro-Rata Claim (DecimatorModule:411-427)

```solidity
function claimDecimatorJackpot(uint24 lvl) external {
    // ... validation ...
    if (prizePoolFrozen) revert E();  // Blocked during jackpot phase

    if (gameOver) {
        _addClaimableEth(msg.sender, amountWei, lastDecClaimRound.rngWord);
        return;  // 100% ETH during GAMEOVER
    }

    // Normal play: 50/50 ETH/lootbox split
    _creditDecJackpotClaimCore(msg.sender, amountWei, lastDecClaimRound.rngWord);
}
```

**Audit checklist:**
- `prizePoolFrozen` prevents claims during active jackpot phase (futurePool corruption)
- GAMEOVER mode gives 100% ETH (no lootbox conversion)
- `_consumeDecClaim` sets `e.claimed = 1` to prevent double-claim
- `lastDecClaimRound.lvl == lvl` check ensures only latest round is claimable

### Example 4: Advance Bounty (AdvanceModule:112-376)

```solidity
uint256 private constant ADVANCE_BOUNTY_ETH = 0.01 ether;
// ...
uint256 advanceBounty = (ADVANCE_BOUNTY_ETH * PRICE_COIN_UNIT) / price;
// ... at various advanceGame triggers:
coin.creditFlip(caller, advanceBounty);  // 1x normal
advanceBounty *= 2;  // 2x on jackpot phase days
advanceBounty *= 3;  // 3x on transition days
```

**Audit checklist:**
- 0.01 ETH equivalent in BURNIE credited per advance call
- Multipliers applied at specific triggers (jackpot day, transition)
- Verify `price` is not zero (would cause division by zero)
- Verify this cannot be called repeatedly in same transaction

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| DGNRS single token | sDGNRS (soulbound) + DGNRS (transferable wrapper) | v2.0 | Burn-for-backing now goes through sDGNRS; DGNRS.burn() delegates |
| claimAffiliateDgnrs using sequential pool depletion | Fixed allocation per level with score-proportional distribution | Recent code update | Eliminates first-mover advantage (v1.1 doc describes old mechanism) |
| Single decimator claim round | Normal + terminal decimator claim rounds | v3.0 (Phase 26) | Two separate claim structs; terminal decimator already audited |
| No auto-rebuy | Auto-rebuy with take-profit and afKing mode | v1.0 | Adds complexity to every _addClaimableEth call site |

## Open Questions

1. **claimAffiliateDgnrs Implementation vs v1.1 Doc**
   - What we know: v1.1-affiliate-system.md describes sequential pool depletion (`poolBalance * 500 / 10000`). The actual code at DegenerusGame:1458-1479 uses `levelDgnrsAllocation[currLevel]` and `totalAffiliateScore[currLevel]` as fixed denominators.
   - What's unclear: When was this mechanism changed? Does the new mechanism have any first-mover advantage?
   - Recommendation: Audit the actual code, not the v1.1 doc. Document any discrepancy as INFO (stale documentation, not a bug).

2. **_addClaimableEth Auto-Rebuy Variants**
   - What we know: Multiple modules have their own `_addClaimableEth` implementations (JackpotModule:973, EndgameModule:241, DecimatorModule:510, DegeneretteModule:1153) that handle auto-rebuy differently.
   - What's unclear: Are all implementations consistent? Could one variant create more ticket value than intended?
   - Recommendation: Compare all 4 implementations side-by-side. Verify each uses the same `_calcAutoRebuy` from PayoutUtils and that the rebuy bonus BPS constants are consistent.

3. **Lootbox Module Complexity**
   - What we know: LootboxModule is 1778 lines covering multiple reward types (whale passes, lazy passes, deity passes, future tickets, BURNIE payouts).
   - What's unclear: Full mapping of all lootbox reward paths and their interaction with pool accounting.
   - Recommendation: Audit lootbox as a sub-wave within PAY-09, focusing on ETH flow paths (where do lootbox ETH contributions go? Is the 2x over-collateralization correctly applied everywhere?).

4. **Coinflip claimCoinflipsFromBurnie vs claimCoinflips**
   - What we know: Two separate claim paths exist (BurnieCoinflip:325 and 346). `claimCoinflipsFromBurnie` is called from BurnieCoin contract.
   - What's unclear: Whether both paths have identical claim logic or if one has different protections.
   - Recommendation: Verify both paths route to the same `_claimCoinflipsInternal` and differ only in caller restrictions.

5. **Yield Distribution Trigger Timing**
   - What we know: `_distributeYieldSurplus` fires at level transitions. stETH rebasing is continuous.
   - What's unclear: Can a large stETH rebase between two rapid level transitions cause an unexpectedly large yield surplus distribution?
   - Recommendation: Verify the yield surplus formula is rate-independent (surplus = total assets - total obligations, regardless of when checked).

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Hardhat + Chai (JavaScript), Foundry for fuzz |
| Config file | hardhat.config.ts |
| Quick run command | `npx hardhat test` (specific test files per requirement) |
| Full suite command | `npm test` |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PAY-01 | Purchase-phase daily jackpot distribution | manual audit | N/A (code review) | N/A |
| PAY-02 | Jackpot-phase 5-day draw sequence | manual audit | N/A (code review) | N/A |
| PAY-03 | BAF normal scatter payout | manual audit | N/A (code review) | N/A |
| PAY-04 | BAF century scatter payout | manual audit | N/A (code review) | N/A |
| PAY-05 | Decimator normal claims | manual audit | N/A (code review) | N/A |
| PAY-06 | Decimator x00 claims | manual audit | N/A (code review) | N/A |
| PAY-07 | Coinflip deposit/win/loss paths | manual audit | N/A (code review) | N/A |
| PAY-08 | Coinflip bounty system | manual audit | N/A (code review) | N/A |
| PAY-09 | Lootbox rewards | manual audit | N/A (code review) | N/A |
| PAY-10 | Quest rewards and streak bonuses | manual audit | N/A (code review) | N/A |
| PAY-11 | Affiliate commissions | manual audit | N/A (code review) | N/A |
| PAY-12 | stETH yield distribution | manual audit | N/A (code review) | N/A |
| PAY-13 | Accumulator milestone payouts | manual audit | N/A (code review) | N/A |
| PAY-14 | sDGNRS burn() redemption math | manual audit | N/A (code review) | N/A |
| PAY-15 | DGNRS wrapper burn() delegation | manual audit | N/A (code review) | N/A |
| PAY-16 | Ticket conversion and futurepool | manual audit | N/A (code review) | N/A |
| PAY-17 | Advance bounty system | manual audit | N/A (code review) | N/A |
| PAY-18 | WWXRP consolation prizes | manual audit | N/A (code review) | N/A |
| PAY-19 | Coinflip recycling and boons | manual audit | N/A (code review) | N/A |

### Sampling Rate
- **Per task commit:** Verify audit verdicts are internally consistent (no contradictions with prior findings)
- **Per wave merge:** Cross-reference claimablePool mutations across all requirements in the wave
- **Phase gate:** All 19 requirements have PASS/FINDING verdicts; claimablePool invariant verified across all normal-gameplay mutation sites

### Wave 0 Gaps
This is an audit phase, not a code implementation phase. No new automated tests are required as deliverables. Findings may recommend new tests.

## Audit-Specific Methodology

### Approach Per Requirement

**PAY-01 through PAY-19 each require:**
1. Read the relevant code section line by line (source contract, not comments)
2. Cross-reference the formula against the corresponding v1.1 specification document
3. Trace all claimablePool/claimableWinnings mutations for this path
4. Verify CEI ordering on every claim/payout function
5. Check for double-claim guards and their correctness
6. Verify the pool source is correct (which pool does the ETH come from?)
7. Check auto-rebuy interaction (does auto-rebuy change the accounting?)
8. Deliver explicit PASS or FINDING verdict with file:line references

### Audit Output Format

Each requirement should produce a verdict:
```
### PAY-XX: [Title]
**Verdict:** PASS | FINDING-[severity]
**Files:** [file:line-range]
**Summary:** [1-2 sentences]
**Pool Source:** [which pool(s) fund this distribution]
**claimablePool Impact:** [how this path affects claimablePool]
**CEI Status:** [correct/violation with details]
**Double-Claim Guard:** [mechanism and verification]
**Recommendation:** [fix if FINDING, or "None" if PASS]
```

### Suggested Wave Organization

**Wave 1 (PAY-01, PAY-02, PAY-16): Jackpot Distribution Core**
- ~3,000 lines (JackpotModule primary)
- High complexity: bucket system, compressed/turbo modes, over-collateralization
- Priority: HIGH (most complex distribution path)

**Wave 2 (PAY-03, PAY-04, PAY-05, PAY-06): Scatter and Decimator**
- ~1,600 lines (EndgameModule + DecimatorModule)
- Critical pool accounting: baseFuturePool vs futurePoolLocal distinction
- Priority: HIGH (pool source confusion is the primary risk)

**Wave 3 (PAY-07, PAY-08, PAY-18, PAY-19): Coinflip Economy**
- ~1,200 lines (BurnieCoinflip primary)
- Burn-and-mint model: supply inflation/deflation tracking
- Priority: MEDIUM (isolated from ETH pool accounting)

**Wave 4 (PAY-09, PAY-10, PAY-11, PAY-12, PAY-13, PAY-17): Ancillary Payouts**
- ~4,600 lines across multiple contracts
- Diverse mechanisms: lootbox, quests, affiliate, stETH yield, advance bounty
- Priority: MEDIUM (each system is relatively self-contained)

**Wave 5 (PAY-14, PAY-15): Token Burns + Cross-Wave Verification**
- ~740 lines (StakedDegenerusStonk + DegenerusStonk)
- Final claimablePool invariant verification across all waves
- Priority: MEDIUM (sDGNRS burn is well-isolated)

### Priority Ordering Within Waves

Within each wave, prioritize by:
1. **Highest ETH movement** -- paths that move the most ETH first
2. **Newest code** -- less test coverage = higher finding probability
3. **Shared infrastructure** -- patterns that affect multiple requirements
4. **Interaction complexity** -- paths with auto-rebuy, pool transitions, or cross-contract calls

## Sources

### Primary (HIGH confidence)
- All 15 contract source files listed in Standard Stack -- read from contracts/ directory (source of truth)
- 13 v1.1 economics reference documents -- specification against which code is verified
- Phase 26 research and findings -- GAMEOVER context, claimablePool mutation sites already verified
- FINAL-FINDINGS-REPORT.md -- cumulative audit history (91 plans, 99 requirements, 16 phases)
- KNOWN-ISSUES.md -- existing known issues (3 Medium, 4 Low, 13+ Info)

### Secondary (MEDIUM confidence)
- v1.1-ECONOMICS-PRIMER.md -- high-level overview for cross-referencing
- Phase 26 summaries (26-01 through 26-04) -- GAMEOVER context decisions

## Metadata

**Confidence breakdown:**
- Contract code understanding: HIGH -- all 15 source files identified with line counts, key functions mapped
- Specification coverage: HIGH -- every PAY requirement has a corresponding v1.1 reference document
- Audit methodology: HIGH -- extending proven Phase 26 methodology to normal-gameplay paths
- Architecture patterns: HIGH -- both credit paths (ETH via claimablePool, BURNIE via creditFlip) fully understood
- Pitfall identification: HIGH -- 8 pitfalls identified from cross-referencing code, docs, and prior audit

**Research date:** 2026-03-17
**Valid until:** 2026-04-17 (30 days -- contracts are stable, no major changes expected during v3.0 audit)
