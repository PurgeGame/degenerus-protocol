---
phase: 06-eth-inflows-and-pool-architecture
verified: 2026-03-12T15:00:00Z
status: passed
score: 8/8 must-haves verified
re_verification: false
---

# Phase 6: ETH Inflows and Pool Architecture Verification Report

**Phase Goal:** A game theory agent can trace every ETH wei from purchase entry to pool allocation with exact formulas
**Verified:** 2026-03-12
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Every ETH purchase type (ticket, lootbox, whale bundle, lazy pass, deity pass, degenerette) has its cost formula documented with exact Solidity expressions | VERIFIED | `audit/06-eth-inflows.md` Sections 1-5, 7. Each has a Solidity code block with formula and constant names. |
| 2 | BURNIE-to-ticket and BURNIE-lootbox paths are documented showing zero ETH pool contribution and the virtual ETH formula for RNG threshold | VERIFIED | `audit/06-eth-inflows.md` Section 6. States "Zero ETH enters any pool" and documents `virtualEth = (burnieAmount * priceWei) / PRICE_COIN_UNIT`. |
| 3 | Degenerette wager inflows are documented with min bets per currency and 100% future pool routing | VERIFIED | `audit/06-eth-inflows.md` Section 7. Documents `MIN_BET_ETH=0.005`, `MIN_BET_BURNIE=100`, `MIN_BET_WWXRP=1`, and 100% future routing in Solidity snippet. |
| 4 | Presale vs post-presale economic differences are enumerated with exact toggle conditions and feature-by-feature comparison | VERIFIED | `audit/06-eth-inflows.md` Section 8. Feature table covers 7 features; toggle condition is `lvl >= 3 || lootboxPresaleMintEth >= 200 ether` — verified against AdvanceModule.sol:275. |
| 5 | The complete pool lifecycle (future -> next -> current -> claimable) is diagrammed with every transition trigger identified by function name and condition | VERIFIED | `audit/06-pool-architecture.md` Sections 2 and 3. ASCII diagram present with labeled arrows; all 4 transitions (3a-3d) documented with exact function names and Solidity expressions. |
| 6 | Per-purchase-type pool split ratios are documented with exact BPS values matching contract constants | VERIFIED | `audit/06-pool-architecture.md` Section 4 (12-row table) and `audit/06-eth-inflows.md` Section 9 (14-row table). All BPS values cross-checked against contract source. |
| 7 | Freeze/unfreeze behavior during jackpot phase is documented showing how pending accumulators interact with packed storage | VERIFIED | `audit/06-pool-architecture.md` Section 5 (5a-5e). Covers `_swapAndFreeze`, `_unfreezePool`, multi-day jackpot accumulator growth, and currentPrizePool exclusion from freeze. |
| 8 | Purchase target calculation and level advancement ratchet system are documented with exact formulas | VERIFIED | `audit/06-pool-architecture.md` Section 6 (6a-6c). Covers BOOTSTRAP_PRIZE_POOL=50 ETH, normal snapshots, x00 special case (`futurePrizePool / 3`), target check expression, compressed jackpot flag, and execution order. |

**Score:** 8/8 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `audit/06-eth-inflows.md` | Complete ETH inflow documentation; must contain `PURCHASE_TO_FUTURE_BPS` | VERIFIED | File exists, 519 lines. Contains 9 sections, 14-row pool split table, 27-entry constant cross-reference table, and 5 pitfall callouts. `PURCHASE_TO_FUTURE_BPS` present. |
| `audit/06-pool-architecture.md` | Complete pool lifecycle documentation; must contain `prizePoolsPacked` | VERIFIED | File exists, 465 lines. Contains 7 sections plus appendix. `prizePoolsPacked` present throughout. |

---

### Key Link Verification

#### Plan 01 Links

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `audit/06-eth-inflows.md` | `contracts/DegenerusGame.sol` | Documented formulas reference exact function names and constants | VERIFIED | `PURCHASE_TO_FUTURE_BPS=1000` at DegenerusGame.sol:198 — confirmed. `recordMint`/`purchase` function names present. |
| `audit/06-eth-inflows.md` | `contracts/modules/DegenerusGameMintModule.sol` | Lootbox split BPS constants cross-referenced | VERIFIED | `LOOTBOX_SPLIT_FUTURE_BPS=9000` at MintModule:105, `LOOTBOX_SPLIT_NEXT_BPS=1000` at MintModule:106, presale variants at 109-111 — all confirmed. |
| `audit/06-eth-inflows.md` | `contracts/modules/DegenerusGameWhaleModule.sol` | Whale/lazy/deity pricing formulas cross-referenced | VERIFIED | `WHALE_BUNDLE_EARLY_PRICE=2.4 ether` at WhaleModule:127, `WHALE_BUNDLE_STANDARD_PRICE=4 ether` at WhaleModule:130, `LAZY_PASS_TO_FUTURE_BPS=1000` at WhaleModule:124, `DEITY_PASS_BASE=24 ether` at WhaleModule:154 — all confirmed. |

#### Plan 02 Links

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `audit/06-pool-architecture.md` | `contracts/storage/DegenerusGameStorage.sol` | Packed storage layout and helper functions | VERIFIED | `prizePoolsPacked`, `prizePoolPendingPacked`, `_getPrizePools`, `_setPrizePools`, `_getPendingPools`, `_setPendingPools`, `_swapAndFreeze` (line 740), `_unfreezePool` (line 750) — all confirmed. |
| `audit/06-pool-architecture.md` | `contracts/modules/DegenerusGameAdvanceModule.sol` | Transition triggers and purchase target | VERIFIED | `_drawDownFuturePrizePool` at line 929, `_applyTimeBasedFutureTake` at line 862, `lastPurchaseDay` usage at lines 240-244, `NEXT_TO_FUTURE_BPS_FAST=3000`, `NEXT_TO_FUTURE_BPS_MIN=1300` — all confirmed. |
| `audit/06-pool-architecture.md` | `contracts/modules/DegenerusGameJackpotModule.sol` | `consolidatePrizePools` documented | VERIFIED | `consolidatePrizePools` at line 884, `payDailyJackpot` at line 325, `DAILY_CURRENT_BPS_MIN=600`, `DAILY_CURRENT_BPS_MAX=1400`, `FUTURE_DUMP_ODDS=1e15` — all confirmed. |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| INFLOW-01 | Plan 01 | Document every ETH purchase path with exact cost formulas | SATISFIED | Sections 1-5 of 06-eth-inflows.md cover tickets, lootboxes, whale bundle, lazy pass, deity pass with exact Solidity formulas and constant line references. |
| INFLOW-02 | Plan 01 | Document BURNIE-to-ticket conversion path with virtual ETH formulas | SATISFIED | Section 6 of 06-eth-inflows.md: `coinCost = (quantity * (PRICE_COIN_UNIT / 4)) / TICKET_SCALE`, `virtualEth = (burnieAmount * priceWei) / PRICE_COIN_UNIT`, cutoff timing documented. |
| INFLOW-03 | Plan 01 | Document degenerette wager inflows with min bets and pool caps | SATISFIED | Section 7 of 06-eth-inflows.md: all three currency min bets, 100% future routing Solidity snippet, `ETH_WIN_CAP_BPS=1000` (10% of futurePool). |
| INFLOW-04 | Plan 01 | Document presale vs post-presale economic differences | SATISFIED | Section 8 of 06-eth-inflows.md: toggle storage variable, auto-end condition code, 7-row feature comparison table, one-way note confirmed. |
| POOL-01 | Plan 02 | Map complete pool lifecycle with transition triggers | SATISFIED | 06-pool-architecture.md Sections 2 and 3: ASCII lifecycle diagram, all 4 transition types (3a-3d) with function names and Solidity expressions. |
| POOL-02 | Plan 02 | Document per-purchase-type pool split ratios with exact BPS values | SATISFIED | 06-pool-architecture.md Section 4: 12-row table with source constant name and file for each row. All BPS values verified against contract source. |
| POOL-03 | Plan 02 | Document freeze/unfreeze mechanics and pending accumulator behavior | SATISFIED | 06-pool-architecture.md Section 5 (5a-5e): freeze activation, purchase behavior during freeze (exact conditional pattern), all 3 unfreeze scenarios, multi-day jackpot accumulator growth, currentPrizePool exclusion. |
| POOL-04 | Plan 02 | Document purchase target calculation and level advancement | SATISFIED | 06-pool-architecture.md Section 6 (6a-6c): ratchet system with BOOTSTRAP_PRIZE_POOL, target check expression, compressed jackpot flag, execution order of snapshot/skim/consolidation. |

**No orphaned requirements.** REQUIREMENTS.md traceability table maps all 8 IDs to Phase 6 and marks them Complete.

---

### Anti-Patterns Found

No anti-patterns detected. Both output files are substantive documentation with no placeholder sections, TODO markers, or stub content. Grep for `TODO|FIXME|placeholder|coming soon` returns no matches in either audit file.

---

### Human Verification Required

None. This is a documentation-only phase. All claims are verifiable against contract source via text search and code inspection, which has been done above. No visual, UI, or runtime behavior is involved.

---

### Formula and Constant Accuracy Summary

The following spot-checks were performed directly against contract source. All values matched the documentation exactly:

**06-eth-inflows.md constants — all CONFIRMED:**

| Constant | Documented Value | Contract Line | Match |
|----------|----------------|---------------|-------|
| `PURCHASE_TO_FUTURE_BPS` | 1000 | DegenerusGame.sol:198 | EXACT |
| `TICKET_SCALE` | 100 | DegenerusGameStorage.sol:129 | EXACT |
| `TICKET_MIN_BUYIN_WEI` | 0.0025 ether | MintModule.sol:94 | EXACT |
| `PRICE_COIN_UNIT` | 1000 ether | DegenerusGameStorage.sol:125 | EXACT |
| `LOOTBOX_MIN` | 0.01 ether | MintModule.sol:90 | EXACT |
| `BURNIE_LOOTBOX_MIN` | 1000 ether | MintModule.sol:92 | EXACT |
| `LOOTBOX_SPLIT_FUTURE_BPS` | 9000 | MintModule.sol:105 | EXACT |
| `LOOTBOX_SPLIT_NEXT_BPS` | 1000 | MintModule.sol:106 | EXACT |
| `LOOTBOX_PRESALE_SPLIT_FUTURE_BPS` | 4000 | MintModule.sol:109 | EXACT |
| `LOOTBOX_PRESALE_SPLIT_NEXT_BPS` | 4000 | MintModule.sol:110 | EXACT |
| `LOOTBOX_PRESALE_SPLIT_VAULT_BPS` | 2000 | MintModule.sol:111 | EXACT |
| `WHALE_BUNDLE_EARLY_PRICE` | 2.4 ether | WhaleModule.sol:127 | EXACT |
| `WHALE_BUNDLE_STANDARD_PRICE` | 4 ether | WhaleModule.sol:130 | EXACT |
| `WHALE_LOOTBOX_PRESALE_BPS` | 2000 | WhaleModule.sol:142 | EXACT |
| `WHALE_LOOTBOX_POST_BPS` | 1000 | WhaleModule.sol:145 | EXACT |
| `LAZY_PASS_TO_FUTURE_BPS` | 1000 | WhaleModule.sol:124 | EXACT |
| `LAZY_PASS_BOON_DEFAULT_DISCOUNT_BPS` | 1000 | WhaleModule.sol:121 | EXACT |
| `LAZY_PASS_LOOTBOX_PRESALE_BPS` | 2000 | WhaleModule.sol:115 | EXACT |
| `LAZY_PASS_LOOTBOX_POST_BPS` | 1000 | WhaleModule.sol:118 | EXACT |
| `DEITY_PASS_BASE` | 24 ether | WhaleModule.sol:154 | EXACT |
| `DEITY_LOOTBOX_PRESALE_BPS` | 2000 | WhaleModule.sol:148 | EXACT |
| `DEITY_LOOTBOX_POST_BPS` | 1000 | WhaleModule.sol:151 | EXACT |
| `MIN_BET_ETH` | 0.005 ether | DegeneretteModule.sol:242 | EXACT |
| `MIN_BET_BURNIE` | 100 ether | DegeneretteModule.sol:245 | EXACT |
| `MIN_BET_WWXRP` | 1 ether | DegeneretteModule.sol:248 | EXACT |
| `ETH_WIN_CAP_BPS` | 1000 | DegeneretteModule.sol:223 | EXACT |
| `LOOTBOX_PRESALE_ETH_CAP` | 200 ether | AdvanceModule.sol:110 | EXACT |

**06-pool-architecture.md constants and functions — all CONFIRMED:**

| Item | Documented Value/Location | Contract | Match |
|------|--------------------------|----------|-------|
| `BOOTSTRAP_PRIZE_POOL` | 50 ether, DegenerusGame.sol:258 | DegenerusGameStorage.sol:137-139 (definition); DegenerusGame.sol:258 (assignment to `levelPrizePool[0]`) | EXACT |
| `NEXT_TO_FUTURE_BPS_FAST` | 3000 | AdvanceModule.sol:101 | EXACT |
| `NEXT_TO_FUTURE_BPS_MIN` | 1300 | AdvanceModule.sol:102 | EXACT |
| `NEXT_TO_FUTURE_BPS_WEEK_STEP` | 100 | AdvanceModule.sol:103 | EXACT |
| `NEXT_TO_FUTURE_BPS_X9_BONUS` | 200 | AdvanceModule.sol:104 | EXACT |
| `JACKPOT_LEVEL_CAP` | 5 | AdvanceModule.sol:93, JackpotModule.sol:105 | EXACT |
| `DAILY_CURRENT_BPS_MIN` | 600 | JackpotModule.sol:143 | EXACT |
| `DAILY_CURRENT_BPS_MAX` | 1400 | JackpotModule.sol:144 | EXACT |
| `FUTURE_DUMP_ODDS` | 1e15 | JackpotModule.sol:153 | EXACT |
| `DISTRESS_MODE_HOURS` | 6 | DegenerusGameStorage.sol:161 | EXACT |
| `_DEPLOY_IDLE_TIMEOUT_DAYS` | 365 | DegenerusGameStorage.sol:164 | EXACT |
| `_swapAndFreeze` function | DegenerusGameStorage.sol:740 | line 740 | EXACT |
| `_unfreezePool` function | DegenerusGameStorage.sol:750 | line 750 | EXACT |
| `_drawDownFuturePrizePool` | AdvanceModule.sol:929 | line 929 | EXACT |
| `_applyTimeBasedFutureTake` | AdvanceModule.sol:862 | line 862 | EXACT |
| `consolidatePrizePools` | JackpotModule.sol:884 | line 884 | EXACT |
| `payDailyJackpot` | JackpotModule.sol:325 | line 325 | EXACT |
| `_isDistressMode` | DegenerusGameStorage.sol:169 | line 169 | EXACT |
| `_futureKeepBps` dice mechanic | 5 dice, 0-3 each, max=15 | JackpotModule.sol:1291 — uses `% 4` (range 0-3) over 5 iterations, divisor 15 | EXACT |
| `_distributeYieldSurplus` | JackpotModule.sol:923, 20%/20%/40% | line 923; `(yieldPool * 2000) / 10_000` (×2) + `(yieldPool * 4000) / 10_000` | EXACT |
| Presale toggle `lootboxPresaleActive = true` | DegenerusGameStorage.sol:800 | line 800 | EXACT |
| Presale auto-end `lvl >= 3 \|\| lootboxPresaleMintEth >= 200 ether` | AdvanceModule.sol:275 | line 275 (verbatim) | EXACT |
| Whale bundle pool split (level 0: 3000/10000 next) | WhaleModule.sol:291 | `nextShare = (totalPrice * 3000) / 10_000` | EXACT |
| Whale bundle pool split (level >0: 500/10000 next) | WhaleModule.sol:293 | `nextShare = (totalPrice * 500) / 10_000` | EXACT |

**Deity pass triangular pricing formula:**
Doc: `basePrice = 24 ether + (k * (k + 1) * 1 ether) / 2`
Contract (WhaleModule.sol:475): `uint256 basePrice = DEITY_PASS_BASE + (k * (k + 1) * 1 ether) / 2` — EXACT.

---

### Gaps Summary

No gaps. All 8 must-have truths are verified. All 27 documented constants match their contract source values exactly. All 6 function line numbers cited in the constant cross-reference are accurate. All key links between documentation and source contracts are confirmed. Phase goal is achieved: a game theory agent can trace every ETH wei from purchase entry to pool allocation using only these two documents.

---

_Verified: 2026-03-12T15:00:00Z_
_Verifier: Claude (gsd-verifier)_
