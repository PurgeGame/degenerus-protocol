# Phase 30: Payout Specification Document - Research

**Researched:** 2026-03-18
**Domain:** HTML document generation, smart contract payout systems synthesis, SVG flow diagrams
**Confidence:** HIGH

## Summary

Phase 30 synthesizes all audit findings from Phases 26-29 into a single self-contained HTML document (`audit/PAYOUT-SPECIFICATION.html`) covering all distribution systems in the Degenerus Protocol. The research catalogues all 19 distribution systems (grouped into 17+ logical categories per the requirements), maps each to its source audit reports and contract file:line references, documents formulas with exact variable names, and identifies edge cases per system.

The primary technical challenge is creating a professional, self-contained HTML document with inline SVG flow diagrams -- no external dependencies (no CDN links, no external CSS, no images). All styling must be inline `<style>` tags, all diagrams must be inline `<svg>` elements. The document must be viewable by opening the file directly in any modern browser.

The content challenge is synthesis: extracting the right details from ~400KB of audit reports and presenting them in a consistent, navigable format per distribution system. Each system needs: trigger condition, source pool, calculation formula (with exact contract variable names), recipients, claim mechanism, currency, flow diagram, and edge cases.

**Primary recommendation:** Build the HTML document with a clean CSS design system (variables for colors, consistent card layout per distribution system), use inline SVG for flow diagrams with a reusable visual language (rectangles for pools/contracts, arrows for fund flows, diamonds for decision points), and organize systems into the 5 logical categories established by the Phase 27 consolidated report.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| SPEC-01 | Payout specification HTML document created at `audit/PAYOUT-SPECIFICATION.html` | HTML single-file best practices, inline CSS/SVG patterns documented in Architecture Patterns |
| SPEC-02 | All 17+ distribution systems covered with trigger, source, calculation, recipients, claim mechanism, currency | Complete catalog of all 19 distribution systems with source reports and details in Distribution Systems Catalog |
| SPEC-03 | Flow diagrams for every distribution system showing money path | SVG flow diagram approach documented in Architecture Patterns; visual language defined |
| SPEC-04 | Edge cases documented per system (empty pools, single player, max values) | Edge cases catalogued per system from Phase 26-28 audit findings in Edge Cases Catalog |
| SPEC-05 | Contract file:line references for every relevant code path | Complete file:line reference map in Distribution Systems Catalog; commit 3fa32f51 as baseline |
| SPEC-06 | All formulas use variable names matching contract code exactly | Formula catalog with exact variable names in Formulas Catalog |
</phase_requirements>

## Standard Stack

### Core
| Technology | Purpose | Why Standard |
|------------|---------|--------------|
| HTML5 | Document structure | Universal browser support, self-contained file format |
| Inline CSS (in `<style>` tag) | Styling and layout | No external dependencies, works offline |
| Inline SVG | Flow diagrams | Vector graphics rendered natively in all browsers, no external libs |
| CSS Custom Properties | Design system consistency | Variables for colors, spacing enable consistent theming |
| CSS Grid / Flexbox | Layout | Responsive, clean card-based layout for distribution systems |

### No External Dependencies
| Explicitly Avoid | Reason |
|------------------|--------|
| Any CDN-hosted CSS/JS | Must work offline, single-file requirement |
| Mermaid.js or similar | Requires external JS library |
| Web fonts | Requires external network request |
| Images (PNG/JPG) | Cannot inline without base64, adds complexity |
| JavaScript frameworks | Static document, no interactivity needed |

**Note:** Minimal vanilla JavaScript may be used for quality-of-life features like a collapsible table of contents or smooth scroll navigation, but the document must be fully readable with JS disabled.

## Architecture Patterns

### Document Structure
```
PAYOUT-SPECIFICATION.html
├── <head>
│   ├── <meta charset="UTF-8">
│   ├── <meta name="viewport" ...>
│   ├── <title>Degenerus Protocol Payout Specification</title>
│   └── <style> /* All CSS here */ </style>
├── <body>
│   ├── Header (title, commit ref, date, summary stats)
│   ├── Table of Contents (linked to sections)
│   ├── Pool Architecture Overview (SVG diagram)
│   ├── Category: Jackpot Distribution (PAY-01, PAY-02, PAY-16)
│   │   ├── System Card: Purchase-Phase Daily Jackpot
│   │   ├── System Card: Jackpot-Phase 5-Day Draws
│   │   └── System Card: Ticket Conversion / Futurepool
│   ├── Category: Scatter / Decimator (PAY-03..06)
│   ├── Category: Coinflip Economy (PAY-07, PAY-08, PAY-18, PAY-19)
│   ├── Category: Ancillary Payouts (PAY-09..13, PAY-17)
│   ├── Category: Token Burns (PAY-14, PAY-15)
│   ├── Category: GAMEOVER Terminal (GO-01, GO-02, GO-07, GO-08)
│   ├── Cross-System: claimablePool Invariant
│   ├── Cross-System: Known Issues Summary
│   └── Footer (audit metadata, commit hash)
│
└── </body>
```

### Per-System Card Pattern
Each distribution system card follows a consistent template:

```html
<section class="system-card" id="pay-XX">
  <h3>System Name</h3>
  <div class="system-meta">
    <span class="badge currency-eth">ETH</span>
    <span class="badge">PAY-XX</span>
  </div>
  <table class="info-table">
    <tr><th>Trigger</th><td>...</td></tr>
    <tr><th>Source Pool</th><td>...</td></tr>
    <tr><th>Calculation</th><td><code>formula with exact var names</code></td></tr>
    <tr><th>Recipients</th><td>...</td></tr>
    <tr><th>Claim Mechanism</th><td>...</td></tr>
    <tr><th>Currency</th><td>...</td></tr>
  </table>
  <div class="formula-block">
    <h4>Formula</h4>
    <pre><code>exact formula with contract variable names</code></pre>
    <p class="file-ref">File:Line references</p>
  </div>
  <div class="flow-diagram">
    <svg><!-- inline SVG flow diagram --></svg>
  </div>
  <div class="edge-cases">
    <h4>Edge Cases</h4>
    <ul>...</ul>
  </div>
</section>
```

### SVG Flow Diagram Visual Language

Use a consistent visual vocabulary for all flow diagrams:

| Shape | Meaning | SVG Element | Fill Color |
|-------|---------|-------------|------------|
| Rounded rectangle | Pool / fund source | `<rect rx="8">` | Light blue (#e3f2fd) |
| Rectangle | Contract / function | `<rect>` | Light gray (#f5f5f5) |
| Diamond | Decision point | `<polygon>` | Light yellow (#fff9c4) |
| Rounded pill | Player/recipient | `<rect rx="20">` | Light green (#e8f5e9) |
| Arrow with label | Fund flow | `<line>` + `<polygon>` marker + `<text>` | Dark gray stroke |
| Dashed arrow | Optional/conditional flow | `<line stroke-dasharray="5,5">` | Gray stroke |

Each SVG should be approximately 700-900px wide, 300-500px tall, with `viewBox` for responsive scaling:
```html
<svg viewBox="0 0 800 400" class="flow-svg">
  <!-- diagram elements -->
</svg>
```

### CSS Design System

```css
:root {
  --color-bg: #ffffff;
  --color-text: #1a1a1a;
  --color-heading: #0d47a1;
  --color-border: #e0e0e0;
  --color-card-bg: #fafafa;
  --color-code-bg: #f5f5f5;
  --color-eth: #627eea;
  --color-burnie: #ff6b35;
  --color-dgnrs: #4caf50;
  --color-steth: #00bcd4;
  --color-pool-bg: #e3f2fd;
  --color-warning: #fff3e0;
  --font-mono: 'Courier New', Courier, monospace;
  --font-sans: system-ui, -apple-system, sans-serif;
}
```

### Anti-Patterns to Avoid
- **External dependencies of any kind:** No CDN links, fonts, images, scripts
- **JavaScript-dependent content:** All content must render without JS
- **Overly complex SVG:** Keep diagrams clean, readable -- favor clarity over artistry
- **Inconsistent terminology:** Always use exact contract variable names, never paraphrase
- **Missing file:line references:** Every formula, every code path must cite the contract source

## Distribution Systems Catalog

### Complete System Inventory (19 systems, 6 categories)

Based on exhaustive review of Phase 26-29 audit reports:

#### Category 1: Jackpot Distribution

| # | System | Req ID | Source Pool | Currency | Key Files | Source Report |
|---|--------|--------|-------------|----------|-----------|---------------|
| 1 | Purchase-Phase Daily Jackpot | PAY-01 | futurePrizePool (1% daily drip) | ETH | JackpotModule:619-673, PayoutUtils:30-74 | v3.0-payout-jackpot-distribution.md |
| 2 | Jackpot-Phase 5-Day Draws | PAY-02 | currentPrizePool (6-14% daily, 100% day 5) | ETH | JackpotModule:336-613, 2723-2736 | v3.0-payout-jackpot-distribution.md |
| 3 | Ticket Conversion / Futurepool | PAY-16 | futurePrizePool/currentPrizePool transition | ETH (pool lifecycle) | JackpotModule:1078-1118, 886-924 | v3.0-payout-jackpot-distribution.md |

#### Category 2: Scatter / Decimator

| # | System | Req ID | Source Pool | Currency | Key Files | Source Report |
|---|--------|--------|-------------|----------|-----------|---------------|
| 4 | BAF Normal Scatter | PAY-03 | baseFuturePool (10%, 20% at L50) | ETH + lootbox tickets | EndgameModule:138-408, DegenerusJackpots:229-530 | v3.0-payout-scatter-decimator.md |
| 5 | BAF Century Scatter | PAY-04 | baseFuturePool (20% at x00) | ETH + lootbox tickets | EndgameModule:138-408, DegenerusJackpots:229-530 | v3.0-payout-scatter-decimator.md |
| 6 | Decimator Normal Claims | PAY-05 | futurePoolLocal (10%) | ETH (50%) + lootbox (50%) | DecimatorModule:297-547, DegenerusGame:1293-1305 | v3.0-payout-scatter-decimator.md |
| 7 | Decimator x00 Claims | PAY-06 | baseFuturePool (30% at x00) | ETH (50%) + lootbox (50%) | EndgameModule:175-210, DecimatorModule:297-547 | v3.0-payout-scatter-decimator.md |

#### Category 3: Coinflip Economy

| # | System | Req ID | Source Pool | Currency | Key Files | Source Report |
|---|--------|--------|-------------|----------|-----------|---------------|
| 8 | Coinflip Deposit/Win/Loss | PAY-07 | N/A (BURNIE burn-and-mint) | BURNIE | BurnieCoinflip:224-627, BurnieCoin:518-529 | v3.0-payout-coinflip-economy.md |
| 9 | Coinflip Bounty | PAY-08 | Virtual BURNIE bounty pool | BURNIE | BurnieCoinflip:634-692, 843-882, DegenerusGame:444-467 | v3.0-payout-coinflip-economy.md |
| 10 | WWXRP Consolation Prizes | PAY-18 | N/A (minted) | WWXRP | BurnieCoinflip:621-623, WrappedWrappedXRP:342-354 | v3.0-payout-coinflip-economy.md |
| 11 | Coinflip Recycling and Boons | PAY-19 | Deposit amount (recycling %) | BURNIE | BurnieCoinflip:1040-1065, 642-653 | v3.0-payout-coinflip-economy.md |

#### Category 4: Ancillary Payouts

| # | System | Req ID | Source Pool | Currency | Key Files | Source Report |
|---|--------|--------|-------------|----------|-----------|---------------|
| 12 | Lootbox Rewards | PAY-09 | Pre-funded lootbox ETH + token mints | ETH (whale pass remainder) + DGNRS + WWXRP + BURNIE + boons | LootboxModule:1-1778, EndgameModule:515-534, PayoutUtils:77-93 | v3.0-payout-lootbox-quest-affiliate.md |
| 13 | Quest Rewards + Streak | PAY-10 | N/A (BURNIE via creditFlip) | BURNIE | DegenerusQuests:1-1598, BurnieCoin:556-558 | v3.0-payout-lootbox-quest-affiliate.md |
| 14 | Affiliate Commissions | PAY-11 | N/A (BURNIE via creditFlip) + sDGNRS Affiliate pool | BURNIE + DGNRS | DegenerusAffiliate:386-623, DegenerusGame:1458-1501 | v3.0-payout-lootbox-quest-affiliate.md |
| 15 | stETH Yield Distribution | PAY-12 | stETH yield surplus (23%/23%/46%) | ETH (via claimable) | JackpotModule:928-958, AdvanceModule:980-986 | v3.0-payout-yield-burns.md |
| 16 | Accumulator Milestone Payouts | PAY-13 | yieldAccumulator (50% at x00) | ETH (to futurePrizePool) | JackpotModule:886-924, AdvanceModule:105 | v3.0-payout-yield-burns.md |
| 17 | Advance Bounty | PAY-17 | N/A (BURNIE via creditFlip) | BURNIE | AdvanceModule:112-376 | v3.0-payout-yield-burns.md |

#### Category 5: Token Burns

| # | System | Req ID | Source Pool | Currency | Key Files | Source Report |
|---|--------|--------|-------------|----------|-----------|---------------|
| 18 | sDGNRS Burn Redemption | PAY-14 | ETH + stETH + claimable (proportional) | ETH + stETH + BURNIE | StakedDegenerusStonk:373-435 | v3.0-payout-yield-burns.md |
| 19 | DGNRS Wrapper Burn | PAY-15 | Delegated to sDGNRS (PAY-14) | ETH + stETH + BURNIE | DegenerusStonk:164-181 | v3.0-payout-yield-burns.md |

#### Category 6: GAMEOVER Terminal Distribution

| # | System | Req ID | Source Pool | Currency | Key Files | Source Report |
|---|--------|--------|-------------|----------|-----------|---------------|
| 20 | Terminal Jackpot | GO-01 | 90% of remaining (after deity refunds + dec allocation) | ETH | GameOverModule:68-164, JackpotModule:288-324, 1537-1576 | v3.0-gameover-core-distribution.md |
| 21 | Terminal Decimator | GO-08 | 10% of remaining (after deity refunds) | ETH | DecimatorModule:749-1027 | v3.0-gameover-core-distribution.md |
| 22 | Deity Pass Refunds | GO-07 | budget = totalFunds - claimablePool | ETH | GameOverModule:68-107 | v3.0-gameover-ancillary-paths.md |
| 23 | Final Sweep (30-day expiry) | GO-02 | All remaining balance | ETH + stETH | GameOverModule:171-189 | v3.0-gameover-ancillary-paths.md |

**Total: 23 distinct distribution mechanisms across 6 categories.** The requirements reference "17+ distribution systems" -- the 19 PAY requirements plus 4 GAMEOVER distribution paths yield 23 total. Some are closely related (PAY-14/15 are the same burn path, PAY-03/04 share BAF code) so the logical grouping may present as ~17-20 distinct "systems" in the final document depending on how closely related systems are combined.

## Formulas Catalog

### Exact Variable Names from Contracts

**PAY-01: Purchase-Phase Daily Jackpot**
```solidity
// JackpotModule:635-639
uint256 poolBps = 100; // 1% daily drip
ethDaySlice = (_getFuturePrizePool() * poolBps) / 10_000;
_setFuturePrizePool(_getFuturePrizePool() - ethDaySlice);

// Split: JackpotModule:644-651
lootboxBudget = (ethPool * PURCHASE_REWARD_JACKPOT_LOOTBOX_BPS) / 10_000; // 7500 = 75%
// Remaining ethPool = 25% to ETH winners
```

**PAY-02: Jackpot-Phase 5-Day Draws**
```solidity
// JackpotModule:336-613 -- daily draw percentage
// Days 1-4: random BPS in [600, 1400] range (6-14%)
// Day 5: 100% of currentPrizePool
// Share split: JACKPOT_SHARES_PACKED = 60/13/13/13 weighted (6000/1300/1300/1300/100 BPS)
dailyBudget = (currentPrizePool * randomBps) / BPS_DENOMINATOR;
```

**PAY-03/04: BAF Scatter**
```solidity
// EndgameModule:168-172
uint256 bafPct = prevMod100 == 0 ? 20 : (lvl == 50 ? 20 : 10);
uint256 bafPoolWei = (baseFuturePool * bafPct) / 100;
futurePoolLocal -= bafPoolWei;

// 7-category split in DegenerusJackpots:229-530
// A: 10%, A2: 5%, B: 5%, D: 5%, D2: 5%, E1: 45%, E2: 25%
```

**PAY-05: Decimator Normal Claims**
```solidity
// DecimatorModule:297-547
// Pool: EndgameModule:210
uint256 decPoolWei = (futurePoolLocal * 10) / 100; // 10% of futurePoolLocal

// Claim formula:
payout = (poolWei * playerBurn) / totalBurn; // Pro-rata
ethPortion = payout / 2;                      // 50% ETH
lootboxPortion = payout - ethPortion;         // 50% lootbox
```

**PAY-06: Decimator x00 Claims**
```solidity
// EndgameModule:194
uint256 decPoolWei = (baseFuturePool * 30) / 100; // 30% of baseFuturePool
// Same claim formula as PAY-05
```

**PAY-07: Coinflip**
```solidity
// BurnieCoinflip:835
bool win = (rngWord & 1) == 1; // 50/50

// BurnieCoinflip:813-825 -- variable multiplier
roll = seedWord % 20;
// roll==0: rewardPercent = 50  (1.5x payout)
// roll==1: rewardPercent = 150 (2.5x payout)
// roll 2-19: rewardPercent = seedWord % 38 + 78 (1.78x-2.15x)

// Payout:
uint256 payout = stake + (stake * uint256(rewardPercent)) / 100;
```

**PAY-08: Coinflip Bounty**
```solidity
// BurnieCoinflip:634-692
// Accumulates 1000 BURNIE per day (COINFLIP_BOUNTY_DAILY = 1000e18)
// Armed when: new all-time record daily volume
// DGNRS gating: bet >= 50000 BURNIE (COINFLIP_BOUNTY_MIN_BET)
//               pool >= 20000 BURNIE (COINFLIP_BOUNTY_MIN_POOL)
// Payout: half of bountyPool via creditFlip
```

**PAY-09: Lootbox Rewards**
```solidity
// LootboxModule:1551 -- reward type selection
roll = nextEntropy % 20;
// 0-10 (55%): future tickets
// 11-12 (10%): DGNRS from sDGNRS pool
// 13-14 (10%): 1 WWXRP
// 15-19 (25%): BURNIE via creditFlip
```

**PAY-10: Quest Rewards**
```solidity
// DegenerusQuests -- reward amounts
// Slot 0: 100 BURNIE (100e18)
// Slot 1: 200 BURNIE (200e18)
// Delivered via coin.creditFlip(player, amount)
// Streak: up to 100 consecutive days = 10000 BPS activity contribution
```

**PAY-11: Affiliate Commissions**
```solidity
// DegenerusAffiliate:386-623
// 3-tier: direct 20%, tier-2 4%, tier-3 via weighted random lottery
// DGNRS: levelDgnrsAllocation[currLevel] (fixed at level transition)
// Per-player share: (affiliateScore * levelDgnrsAllocation) / totalAffiliateScore
// ETH cap: 0.5 ETH per sender per level (AFFILIATE_ETH_CAP)
```

**PAY-12: stETH Yield Distribution**
```solidity
// JackpotModule:928-958
yieldSurplus = (address(this).balance + steth.balanceOf(address(this)))
             - (currentPrizePool + _getNextPrizePool() + claimablePool
                + _getFuturePrizePool() + yieldAccumulator);

stakeholderShare = (yieldPool * 2300) / 10_000; // 23% each to Vault and sDGNRS
accumulatorShare = (yieldPool * 4600) / 10_000; // 46% to yieldAccumulator
// ~8% retained as unextracted buffer
```

**PAY-13: Accumulator Milestone**
```solidity
// JackpotModule:886-924
// At x00 levels: release 50% of yieldAccumulator to futurePrizePool
// Then keep-roll for remaining 50%
halfAccumulator = yieldAccumulator / 2;
_setFuturePrizePool(_getFuturePrizePool() + halfAccumulator);
yieldAccumulator -= halfAccumulator; // rounding favors retention
```

**PAY-14: sDGNRS Burn**
```solidity
// StakedDegenerusStonk:373-435
totalMoney = ethBal + stethBal + claimableEth; // includes pending claimable
share = (amount * totalMoney) / supplyBefore;  // proportional formula
// ETH preferred: pays from ETH first, then stETH, then claims lazily
```

**PAY-15: DGNRS Wrapper Burn**
```solidity
// DegenerusStonk:164-181
_burn(msg.sender, amount);           // burn DGNRS
dgnrs.wrapperBurnTo(msg.sender, amount); // delegate to sDGNRS.burn()
// Forwards ETH + stETH + BURNIE to caller
```

**PAY-17: Advance Bounty**
```solidity
// AdvanceModule:112-376
// Base: 0.01 ETH equivalent in BURNIE via creditFlip
// Time escalation: 1x (< 1h), 2x (1-2h), 3x (> 2h elapsed)
bountyAmount = ADVANCE_BOUNTY_BASE * multiplier; // 0.01 ETH * 1x/2x/3x
// Converted to BURNIE via creditFlip
```

**GAMEOVER: handleGameOverDrain**
```solidity
// GameOverModule:68-164
totalFunds = address(this).balance + steth.balanceOf(address(this));
budget = totalFunds - claimablePool; // available for distribution
// [1] Deity refunds: 20 ETH per pass, FIFO, budget-capped
// [2] remaining = totalFunds - claimablePool - totalRefunded
// [3] decPool = remaining / 10  (10% to terminal decimator)
// [4] Terminal jackpot gets remaining - decPool + decRefund (90%+)
// [5] Vault sweep: undistributed terminal jackpot ETH
```

## Edge Cases Catalog

### Per-System Edge Cases (from Phases 26-28)

**PAY-01/02 (Jackpot):**
- Empty pool: If `futurePrizePool == 0`, `ethDaySlice = 0`, no distribution occurs
- No winners at trait bucket: Unfilled slots refund to yield surplus (not returned to pool)
- Auto-rebuy dust: Unconverted remainder dropped; max loss = `ticketPrice - 1` wei per payout

**PAY-03/04 (BAF Scatter):**
- No ticket holders at target level: Prize returns to `futurePoolLocal` via `toReturn` (Jackpots:259, 290)
- Single player with large win: 50/50 ETH/lootbox split; whale pass queueing if > 5 ETH
- Level 50 gets 20% instead of 10% (special case)

**PAY-05/06 (Decimator):**
- `totalBurn == 0`: No winners, full pool returned as `decRefund`
- `lastDecClaimRound` overwrite: By-design (EDGE-04); previous round's unclaimed funds recycled
- Player claimed already: `claimed[player]` flag prevents double-claim within a round
- `prizePoolFrozen` guard: Blocks claims during jackpot phase days 1-4

**PAY-07 (Coinflip):**
- Zero stake: `coinflipBalance` cleared to 0 on first processing; no double-payout
- RNG locked: `rngLockedFlag` blocks claims during VRF resolution
- Claim window: 30 days first-time, 90 days returning (asymmetry is by-design; PAY-07-I01)
- Auto-rebuy carry zeroed on loss

**PAY-08 (Coinflip Bounty):**
- Bounty not armed: Requires new all-time record daily volume
- DGNRS gating fails: If bet < 50k BURNIE or pool < 20k BURNIE, bounty not awarded

**PAY-09 (Lootbox):**
- Empty lootbox: `lootboxEth[index][player]` zeroed at resolution; no re-claim
- Whale pass after GAMEOVER: `if (gameOver) revert E()` blocks claim
- No DGNRS in pool: `transferFromPool` would revert (bounded by pool balance)

**PAY-10 (Quest):**
- Streak broken: Activity score contribution resets; max 100 consecutive days
- Version-gated: Quest progress reset on version change (prevents re-trigger)

**PAY-11 (Affiliate):**
- Self-referral: Blocked at `DegenerusAffiliate.sol:426`
- ETH cap: 0.5 ETH per sender per level
- No affiliate activity at level: `totalAffiliateScore == 0` prevents division-by-zero

**PAY-12 (stETH Yield):**
- `totalBal <= obligations`: Returns early, no distribution
- Rate-independent: Works regardless of when check occurs
- Fires exactly once per level transition (`poolConsolidationDone` flag)

**PAY-13 (Accumulator):**
- Non-x00 level: Milestone payout does not fire
- Rounding: `yieldAccumulator / 2` truncates; rounding favors retention

**PAY-14/15 (Token Burns):**
- Single sDGNRS holder burning 100%: Gets proportional share of totalMoney
- Lazy-claim CP-04 defense: `claimableEth` included in `totalMoney`, claimed on-demand when ETH balance insufficient
- `supplyBefore` ensures sequential burns are correctly proportional

**PAY-17 (Advance Bounty):**
- Division-by-zero impossible: Price initialized to 0.01 ETH, only mutated to non-zero tiers
- Mint-gate: Caller must be eligible (e.g., holding enough tokens)

**GAMEOVER Terminal:**
- Level 0: `lvl` aliased to 1; safety valve skipped; deity refunds consume budget
- Level 0 with deity passes: Budget may be fully consumed by refunds, leaving `remaining == 0`
- Single player: All distribution paths handle N=1 correctly (EDGE-02)
- No terminal decimator burns: `totalWinnerBurn == 0`; full pool returned as `decRefund` to terminal jackpot
- `_sendToVault` hard revert: GO-05-F01 MEDIUM -- if vault/sDGNRS cannot receive, distribution blocked
- 30-day claim window: After expiry, `claimablePool = 0`; all remaining swept to vault/sDGNRS 50/50
- Dead VRF: 3-day fallback timer; historical VRF words + prevrandao used

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Flow diagrams | Canvas/JS drawing lib | Inline SVG with viewBox | Native browser rendering, no dependencies, scales cleanly |
| CSS framework | Custom grid system | CSS Grid + Flexbox + custom properties | Standard, no external deps |
| Collapsible sections | Custom JS accordion | HTML `<details>/<summary>` | Native browser support, works without JS |
| Syntax highlighting | JS-based highlighter | `<code>` + CSS styling on `code` elements | Simple, no dependencies needed for Solidity snippets |
| Print styling | Separate print CSS | `@media print` block in same `<style>` | Single file, proper print layout |
| Navigation | JS-based scrollspy | Anchor links + CSS scroll-behavior: smooth | Works without JS |

## Common Pitfalls

### Pitfall 1: Inconsistent Variable Names
**What goes wrong:** Using approximate or paraphrased variable names instead of exact contract names
**Why it happens:** Working from audit report summaries rather than contract code
**How to avoid:** SPEC-06 requires exact variable names. Cross-reference every formula against the source report's code snippets. Use exact names like `baseFuturePool`, `futurePoolLocal`, `claimablePool`, `ethDaySlice`, not approximations.
**Warning signs:** Any formula that uses words like "pool" without specifying WHICH pool variable

### Pitfall 2: Missing Pool Source Distinction
**What goes wrong:** Conflating `baseFuturePool` (snapshot) with `futurePoolLocal` (running total)
**Why it happens:** Both represent the future prize pool but at different points in the level transition
**How to avoid:** Document the distinction explicitly. BAF uses `baseFuturePool`, normal decimator uses `futurePoolLocal` (post-BAF value). This is critical for accuracy.
**Warning signs:** Scatter/decimator section not clearly distinguishing pool sources

### Pitfall 3: Forgetting GAMEOVER Terminal Systems
**What goes wrong:** Document covers only the 19 PAY requirements, missing the 4 GAMEOVER distribution paths
**Why it happens:** Requirements say "17+ distribution systems" which could be interpreted as PAY-only
**How to avoid:** Include GAMEOVER terminal systems as a separate category. The terminal jackpot, terminal decimator, deity refunds, and final sweep are all distinct distribution mechanisms.
**Warning signs:** No GAMEOVER section in the document

### Pitfall 4: SVG Diagrams Without viewBox
**What goes wrong:** SVG diagrams have fixed pixel sizes, don't scale with viewport
**Why it happens:** Forgetting `viewBox` attribute on `<svg>` element
**How to avoid:** Always use `viewBox="0 0 W H"` with CSS `width: 100%; max-width: Xpx;` for responsive scaling
**Warning signs:** Diagrams overflow on smaller screens or look tiny on large ones

### Pitfall 5: Stale File:Line References
**What goes wrong:** Line numbers drift if code changes between research and document creation
**Why it happens:** Line numbers are from audit reports which were created against a specific commit
**How to avoid:** Pin all references to commit `3fa32f51` (current HEAD). Include the commit hash prominently in the document header. All file:line references in the audit reports are current as of this commit.
**Warning signs:** Any line reference that doesn't match when checked against the codebase

### Pitfall 6: Missing the Auto-Rebuy Interaction
**What goes wrong:** Flow diagrams show direct ETH -> claimablePool but miss the auto-rebuy branch
**Why it happens:** Auto-rebuy is an intermediate step in `_addClaimableEth` that diverts ETH to tickets
**How to avoid:** Include auto-rebuy as a decision point in every ETH distribution flow diagram where `_addClaimableEth` is involved (PAY-01, PAY-02, PAY-03/04, PAY-05/06, PAY-12)
**Warning signs:** Flow diagram for an ETH payout path without an auto-rebuy branch

### Pitfall 7: Document Too Large for Browser
**What goes wrong:** Single HTML file with many inline SVGs becomes multi-MB, slow to load
**Why it happens:** Complex SVG paths, unoptimized coordinates, redundant elements
**How to avoid:** Keep SVGs simple (rectangles, lines, text). Use `<defs>` for reusable shapes/markers. Target ~3-5KB per diagram. Aim for total document size under 500KB.
**Warning signs:** Individual SVG diagrams exceeding 10KB

## Code Examples

### Example: Self-Contained HTML with Inline SVG Flow Diagram

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Payout Specification</title>
<style>
  :root {
    --pool-bg: #e3f2fd;
    --contract-bg: #f5f5f5;
    --recipient-bg: #e8f5e9;
    --arrow-color: #424242;
  }
  .flow-svg {
    width: 100%;
    max-width: 800px;
    height: auto;
    display: block;
    margin: 1rem auto;
  }
  .flow-svg text {
    font-family: system-ui, sans-serif;
    font-size: 12px;
    fill: #1a1a1a;
  }
  .flow-svg .pool { fill: var(--pool-bg); stroke: #1565c0; stroke-width: 1.5; }
  .flow-svg .contract { fill: var(--contract-bg); stroke: #616161; stroke-width: 1; }
  .flow-svg .recipient { fill: var(--recipient-bg); stroke: #2e7d32; stroke-width: 1.5; }
</style>
</head>
<body>
<svg viewBox="0 0 800 300" class="flow-svg">
  <defs>
    <marker id="arrow" markerWidth="10" markerHeight="7" refX="10" refY="3.5" orient="auto">
      <polygon points="0 0, 10 3.5, 0 7" fill="#424242"/>
    </marker>
  </defs>
  <!-- Pool -->
  <rect x="10" y="120" width="160" height="60" rx="8" class="pool"/>
  <text x="90" y="155" text-anchor="middle">futurePrizePool</text>
  <!-- Arrow -->
  <line x1="170" y1="150" x2="290" y2="150" stroke="#424242" stroke-width="1.5" marker-end="url(#arrow)"/>
  <text x="230" y="140" text-anchor="middle" font-size="10">1% daily drip</text>
  <!-- Contract -->
  <rect x="300" y="120" width="180" height="60" class="contract"/>
  <text x="390" y="145" text-anchor="middle">_distributeJackpotEth</text>
  <text x="390" y="160" text-anchor="middle" font-size="10">JackpotModule:619</text>
  <!-- Arrow to winners -->
  <line x1="480" y1="150" x2="600" y2="150" stroke="#424242" stroke-width="1.5" marker-end="url(#arrow)"/>
  <text x="540" y="140" text-anchor="middle" font-size="10">25% ETH</text>
  <!-- Recipient -->
  <rect x="610" y="120" width="160" height="60" rx="20" class="recipient"/>
  <text x="690" y="155" text-anchor="middle">Winners (VRF)</text>
</svg>
</body>
</html>
```

### Example: Collapsible Section with details/summary

```html
<details class="system-details" open>
  <summary>
    <h3>PAY-01: Purchase-Phase Daily Jackpot</h3>
    <span class="badge">ETH</span>
  </summary>
  <table class="info-table">
    <tr><th>Trigger</th><td>Daily, during purchase phase (daysSince > 0 && lvl > 1)</td></tr>
    <tr><th>Source Pool</th><td><code>futurePrizePool</code> (1% daily drip)</td></tr>
    <tr><th>Formula</th><td><code>ethDaySlice = (_getFuturePrizePool() * 100) / 10_000</code></td></tr>
    <tr><th>Recipients</th><td>VRF-selected ticket holders (4 trait buckets)</td></tr>
    <tr><th>Claim</th><td><code>claimWinnings()</code> via <code>claimableWinnings[player]</code></td></tr>
    <tr><th>Currency</th><td>75% lootbox tickets, 25% ETH</td></tr>
  </table>
  <p class="file-ref">
    <strong>Code:</strong> JackpotModule.sol:619-673, PayoutUtils.sol:30-74<br>
    <strong>Commit:</strong> 3fa32f51
  </p>
</details>
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Markdown audit reports | Self-contained HTML specification | Phase 30 (new) | Browser-viewable, includes diagrams |
| Text-only pool descriptions | SVG flow diagrams showing money paths | Phase 30 (new) | Visual clarity for reviewers |
| Scattered findings across reports | Single consolidated reference | Phase 30 (new) | One-stop reference for C4A wardens |

## Key Source Documents

All content for the payout specification must be sourced from these verified audit artifacts:

| Document | Path | Content | Size |
|----------|------|---------|------|
| GAMEOVER Core Distribution | audit/v3.0-gameover-core-distribution.md | GO-01, GO-08 details | 35KB |
| GAMEOVER Safety Properties | audit/v3.0-gameover-safety-properties.md | GO-05, GO-06, GO-09 details | 38KB |
| GAMEOVER Ancillary Paths | audit/v3.0-gameover-ancillary-paths.md | GO-02, GO-03, GO-04, GO-07 details | 35KB |
| GAMEOVER Consolidated | audit/v3.0-gameover-audit-consolidated.md | Phase 26 summary | 31KB |
| Payout Jackpot Distribution | audit/v3.0-payout-jackpot-distribution.md | PAY-01, PAY-02, PAY-16 | 43KB |
| Payout Scatter/Decimator | audit/v3.0-payout-scatter-decimator.md | PAY-03, PAY-04, PAY-05, PAY-06 | 46KB |
| Payout Coinflip Economy | audit/v3.0-payout-coinflip-economy.md | PAY-07, PAY-08, PAY-18, PAY-19 | 35KB |
| Payout Lootbox/Quest/Affiliate | audit/v3.0-payout-lootbox-quest-affiliate.md | PAY-09, PAY-10, PAY-11 | 31KB |
| Payout Yield/Burns | audit/v3.0-payout-yield-burns.md | PAY-12, PAY-13, PAY-17, PAY-14, PAY-15 | 34KB |
| Payout Consolidated | audit/v3.0-payout-audit-consolidated.md | Phase 27 summary | 28KB |
| Cross-Cutting Consolidated | audit/v3.0-cross-cutting-consolidated.md | Phase 28 summary | 20KB |
| Cross-Cutting Edge Cases | audit/v3.0-cross-cutting-edge-cases.md | EDGE-01 through EDGE-07 | 42KB |
| Cross-Cutting Invariants (Pool) | audit/v3.0-cross-cutting-invariants-pool.md | INV-01, INV-02 | 47KB |
| Doc Verification | audit/v3.0-doc-verification.md | Phase 29 summary | 11KB |
| Known Issues | audit/KNOWN-ISSUES.md | All known findings | 13KB |
| Final Findings | audit/FINAL-FINDINGS-REPORT.md | Executive summary | 70KB |
| Parameter Reference | audit/v1.1-parameter-reference.md | All constants | 69KB |
| Economics Primer | audit/v1.1-ECONOMICS-PRIMER.md | Protocol overview | 17KB |

## claimablePool Mutation Sites Reference

The document should include a consolidated view of all 15 claimablePool mutation sites (verified across Phases 26-28):

### GAMEOVER Path (6 sites)
| Site | Location | Mutation | Direction |
|------|----------|----------|-----------|
| G1 | GameOverModule:105 | `claimablePool += totalRefunded` | UP |
| G2 | GameOverModule:143 | `claimablePool += decSpend` | UP |
| G3 | JackpotModule:1573 | `claimablePool += ctx.liabilityDelta` | UP |
| G4 | GameOverModule:177 | `claimablePool = 0` | ZERO |
| G5 | DecimatorModule:936 | via `_addClaimableEth` -> `_creditClaimable` | UP (individual) |
| G6 | DegenerusGame:1440 | `claimablePool -= payout` | DOWN |

### Normal Gameplay (8 sites)
| Site | Location | Mutation | Direction |
|------|----------|----------|-----------|
| N1 | JackpotModule:1572-1573 | `claimablePool += ctx.liabilityDelta` | UP |
| N2 | JackpotModule:1529-1531 | `claimablePool += liabilityDelta` | UP |
| N3 | PayoutUtils:90 | `claimablePool += remainder` | UP |
| N4 | EndgameModule:226 | `claimablePool += claimableDelta` | UP |
| N5 | EndgameModule:275 | `claimablePool += calc.reserved` | UP |
| N6 | DecimatorModule:478/490/519 | claimablePool via decimator claim | UP |
| N7 | JackpotModule:940-958 | `claimablePool += claimableDelta` (yield) | UP |
| N8 | DegenerusGame:1440 | `claimablePool -= payout` | DOWN |

### Additional (1 site)
| Site | Location | Mutation | Direction |
|------|----------|----------|-----------|
| D1 | DegeneretteModule:1158 | via `_addClaimableEth` | UP |

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Manual browser verification (no automated test framework for HTML documents) |
| Config file | N/A |
| Quick run command | `open audit/PAYOUT-SPECIFICATION.html` (browser) |
| Full suite command | Manual review: all 6 SPEC requirements checked |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SPEC-01 | HTML file exists at correct path | smoke | `test -f audit/PAYOUT-SPECIFICATION.html && echo PASS` | Wave 0 |
| SPEC-02 | All 17+ systems covered with required fields | manual | Visual inspection of all system cards | N/A |
| SPEC-03 | Flow diagrams present for every system | manual | Search for `<svg` tags matching system count | N/A |
| SPEC-04 | Edge cases documented per system | manual | Visual inspection of edge-case sections | N/A |
| SPEC-05 | File:line references present | manual | Search for `:` pattern in code references | N/A |
| SPEC-06 | Formulas use exact variable names | manual | Cross-reference against audit reports | N/A |

### Sampling Rate
- **Per task commit:** `test -f audit/PAYOUT-SPECIFICATION.html && echo EXISTS`
- **Per wave merge:** Open in browser, verify structure
- **Phase gate:** All 6 SPEC requirements manually verified

### Wave 0 Gaps
- [ ] `audit/PAYOUT-SPECIFICATION.html` -- the deliverable itself
- No test infrastructure needed -- this is a documentation deliverable

## Open Questions

1. **Grouping of closely-related systems**
   - What we know: PAY-03/PAY-04 share BAF code; PAY-05/PAY-06 share decimator code; PAY-14/PAY-15 are one burn path; GAMEOVER systems are separate
   - What's unclear: Whether to present 23 individual system cards or group related ones (e.g., one card for "BAF Scatter" covering both normal and century)
   - Recommendation: Group related systems into combined cards with sub-sections where the code path is shared (e.g., one "BAF Scatter" card with normal/century variants). This yields ~17-18 logical system cards, matching the "17+" in requirements. Each combined card still documents both variants with their distinct parameters.

2. **Depth of flow diagrams for simple systems**
   - What we know: Some systems like PAY-10 (quest rewards) and PAY-17 (advance bounty) are straightforward creditFlip calls
   - What's unclear: Whether every system needs an elaborate SVG diagram
   - Recommendation: Simple systems get simple diagrams (3-4 nodes: trigger -> function -> creditFlip -> recipient). Complex systems (GAMEOVER, BAF scatter, jackpot draws) get detailed multi-path diagrams. Quality over uniformity.

3. **Print layout considerations**
   - What we know: Self-contained HTML is primarily for browser viewing
   - What's unclear: Whether print support is needed
   - Recommendation: Include basic `@media print` CSS for reasonable print output (hide TOC navigation, reduce colors, ensure page breaks before category sections). Low effort, good insurance.

## Sources

### Primary (HIGH confidence)
- Phase 26 GAMEOVER audit reports (4 files) -- line-by-line code review with verdicts
- Phase 27 Payout audit reports (6 files) -- all 19 PAY requirements with code references
- Phase 28 Cross-cutting reports (5 files) -- invariant proofs, edge cases, vulnerability ranking
- Phase 29 Documentation verification (6 files) -- NatSpec accuracy confirmed
- audit/v3.0-payout-audit-consolidated.md -- Phase 27 synthesis with unified mutation trace table
- audit/v3.0-gameover-audit-consolidated.md -- Phase 26 synthesis with GAMEOVER flow diagram
- audit/v3.0-cross-cutting-consolidated.md -- Phase 28 synthesis with cross-phase consistency checks

### Secondary (MEDIUM confidence)
- [MDN SVG Documentation](https://developer.mozilla.org/en-US/docs/Web/SVG) -- SVG inline HTML standard practices
- [SVG in HTML introduction](https://developer.mozilla.org/en-US/docs/Web/SVG/Tutorial/SVG_In_HTML_Introduction) -- embedding patterns
- [Including vector graphics in HTML](https://developer.mozilla.org/en-US/docs/Learn_web_development/Core/Structuring_content/Including_vector_graphics_in_HTML) -- best practices

### Tertiary (LOW confidence)
- [SVG flowchart patterns](https://codepen.io/BillKroger/pen/NdGybP) -- community examples of SVG flowcharts

## Metadata

**Confidence breakdown:**
- Distribution systems catalog: HIGH -- sourced entirely from Phase 26-29 verified audit reports with explicit PASS verdicts
- Formulas and variable names: HIGH -- copied directly from audit report code snippets which cite contract source
- File:line references: HIGH -- verified against current commit 3fa32f51
- Edge cases: HIGH -- sourced from Phase 28 EDGE-01 through EDGE-07 analysis and per-system audit verdicts
- HTML/SVG patterns: HIGH -- standard web technologies with well-known best practices
- Document structure: MEDIUM -- proposed structure based on requirements; planner should validate against SPEC-01 through SPEC-06

**Research date:** 2026-03-18
**Valid until:** 2026-04-18 (stable -- contract code is immutable; audit reports are complete)
