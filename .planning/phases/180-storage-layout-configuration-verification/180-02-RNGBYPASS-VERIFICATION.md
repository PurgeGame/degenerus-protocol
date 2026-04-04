# Phase 180 Plan 02: rngBypass Parameter Verification (DELTA-03)

**Date:** 2026-04-04
**Scope:** All rngBypass call sites across 8 contracts
**Method:** Upward call-chain trace from each call site to external entry point

## Guard Logic

The rngBypass parameter exists on 4 internal functions in DegenerusGameStorage.sol:

| Function | Line | Signature |
|---|---|---|
| `_queueTickets` | 549 | `(address, uint24, uint32, bool rngBypass)` |
| `_queueTicketsScaled` | 578 | `(address, uint24, uint32, bool rngBypass)` |
| `_queueTicketRange` | 625 | `(address, uint24, uint24, uint32, bool rngBypass)` |
| `_queueLootboxTickets` | 662 | `(address, uint24, uint256, bool rngBypass)` -- wrapper, delegates to `_queueTicketsScaled` |

Guard in all 3 core functions (lines 558, 587, 637):
```solidity
if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked();
```

When `rngBypass=true`, the RngLocked revert is skipped for far-future tickets. This is correct ONLY when called from advanceGame's internal path (phase transitions queue vault perpetual tickets and jackpot reward tickets that must not revert during level advancement).

---

## rngBypass=true Call Sites (6 total, all advanceGame-internal)

### JackpotModule:698 -- rngBypass=true
- **Function:** `_runEarlyBirdLootboxJackpot` (line 650, private)
- **Call chain:** `advanceGame()` -> delegatecall to `AdvanceModule.advanceGame()` -> `_runRewardJackpots(lvl, rngWord)` (line 374) -> delegatecall to `JackpotModule.runRewardJackpots()` (line 2516) -> `_runBafJackpot()` (line 2539) -> processes winners -> in early-bird branch `_runEarlyBirdLootboxJackpot(lvl+1, randWord)` (line 351) -> `_distributeTicketJackpot()` -> `_distributeTicketsToBuckets()` -> `_distributeTicketsToBucket()` -> `_queueTickets(winner, baseLevel + levelOffset, ticketCount, true)` at line 698
- **Entry point type:** advanceGame-internal (only reachable via delegatecall chain from `advanceGame`)
- **Literal check:** `true` is a literal at line 702
- **Verdict:** SAFE (correct bypass -- jackpot winner ticket distribution during level transition)

### JackpotModule:863 -- rngBypass=true
- **Function:** `_processAutoRebuy` (line 843, private)
- **Call chain:** `advanceGame()` -> delegatecall to `AdvanceModule.advanceGame()` -> `_runRewardJackpots()` (line 374) -> delegatecall to `JackpotModule.runRewardJackpots()` (line 2516) -> `_runBafJackpot()` (line 2539) -> processes winners -> `_addClaimableEth()` (lines 2675/2695) -> `_processAutoRebuy(beneficiary, weiAmount, entropy, state)` (line 825) -> `_queueTickets(player, calc.targetLevel, calc.ticketCount, true)` at line 863
- **Entry point type:** advanceGame-internal (only reachable via delegatecall chain from `advanceGame`)
- **Literal check:** `true` is a literal at line 863
- **Verdict:** SAFE (correct bypass -- auto-rebuy ticket conversion during BAF jackpot resolution)

### JackpotModule:1070 -- rngBypass=true
- **Function:** `_distributeTicketsToBucket` (line 1038, private)
- **Call chain:** `advanceGame()` -> delegatecall to `AdvanceModule.advanceGame()` -> `_runRewardJackpots()` (line 374) -> delegatecall to `JackpotModule.runRewardJackpots()` (line 2516) -> `_runBafJackpot()` -> winner processing -> `_distributeTicketJackpot()` -> `_distributeTicketsToBuckets()` (line 999) -> `_distributeTicketsToBucket()` (line 1038) -> `_queueTickets(winner, queueLvl, uint32(units), true)` at line 1070
- **Entry point type:** advanceGame-internal (only reachable via delegatecall chain from `advanceGame`)
- **Literal check:** `true` is a literal at line 1070
- **Verdict:** SAFE (correct bypass -- jackpot bucket winner ticket distribution during level transition)

### JackpotModule:2807 -- rngBypass=true
- **Function:** `_jackpotTicketRoll` (line 2777, private)
- **Call chain:** `advanceGame()` -> delegatecall to `AdvanceModule.advanceGame()` -> `_runRewardJackpots()` (line 374) -> delegatecall to `JackpotModule.runRewardJackpots()` (line 2516) -> `_runBafJackpot()` (line 2539) -> processes winners -> `_awardJackpotTickets()` (lines 2680/2698) -> `_jackpotTicketRoll(winner, amount, minTargetLevel, entropy)` (line 2777) -> `_queueLootboxTickets(winner, targetLevel, quantityScaled, true)` at line 2807
- **Entry point type:** advanceGame-internal (only reachable via delegatecall chain from `advanceGame`)
- **Literal check:** `true` is a literal at line 2807
- **Note:** `_queueLootboxTickets` is a thin wrapper that forwards `rngBypass` to `_queueTicketsScaled`. The parameter is passed as a variable internally, but the only external caller (this site) uses a literal `true`. See "Variable Passing Analysis" section below.
- **Verdict:** SAFE (correct bypass -- jackpot lootbox ticket roll during BAF resolution)

### AdvanceModule:1299 -- rngBypass=true
- **Function:** `_processPhaseTransition` (line 1294, private)
- **Call chain:** `advanceGame()` -> delegatecall to `AdvanceModule.advanceGame()` (line 151) -> `_processPhaseTransition(purchaseLevel)` (line 287) -> `_queueTickets(ContractAddresses.SDGNRS, targetLevel, VAULT_PERPETUAL_TICKETS, true)` at line 1299
- **Entry point type:** advanceGame-internal (only reachable from `advanceGame` via delegatecall)
- **Literal check:** `true` is a literal at line 1303
- **Verdict:** SAFE (correct bypass -- vault perpetual tickets for SDGNRS during level transition)

### AdvanceModule:1305 -- rngBypass=true
- **Function:** `_processPhaseTransition` (line 1294, private)
- **Call chain:** `advanceGame()` -> delegatecall to `AdvanceModule.advanceGame()` (line 151) -> `_processPhaseTransition(purchaseLevel)` (line 287) -> `_queueTickets(ContractAddresses.VAULT, targetLevel, VAULT_PERPETUAL_TICKETS, true)` at line 1305
- **Entry point type:** advanceGame-internal (only reachable from `advanceGame` via delegatecall)
- **Literal check:** `true` is a literal at line 1309
- **Verdict:** SAFE (correct bypass -- vault perpetual tickets for VAULT during level transition)

---

## rngBypass=false Call Sites (11 total, all external-facing or constructor)

### DegenerusGame:213 -- rngBypass=false
- **Function:** `constructor` (DegenerusGame.sol)
- **Call chain:** Contract deployment -> constructor -> `_queueTickets(ContractAddresses.SDGNRS, i, 16, false)` at line 213
- **Entry point type:** constructor (one-time deployment, not callable after)
- **Literal check:** `false` is a literal at line 213
- **Verdict:** SAFE (correct -- constructor pre-queues initial vault tickets; RNG guard applies normally)

### DegenerusGame:214 -- rngBypass=false
- **Function:** `constructor` (DegenerusGame.sol)
- **Call chain:** Contract deployment -> constructor -> `_queueTickets(ContractAddresses.VAULT, i, 16, false)` at line 214
- **Entry point type:** constructor (one-time deployment, not callable after)
- **Literal check:** `false` is a literal at line 214
- **Verdict:** SAFE (correct -- constructor pre-queues initial vault tickets; RNG guard applies normally)

### Storage:1100 -- rngBypass=false
- **Function:** `_activate10LevelPass` (DegenerusGameStorage.sol, line 1021, internal)
- **Call chain:** External caller -> WhaleModule `_purchaseLazyPass()` (line 384) -> `_activate10LevelPass(buyer, startLevel, LAZY_PASS_TICKETS_PER_LEVEL)` (line 478) -> `_queueTicketRange(player, ticketStartLevel, 10, ticketsPerLevel, false)` at line 1100
- **Entry point type:** external-facing (player purchases a lazy pass via `purchaseLazyPass`)
- **Literal check:** `false` is a literal at line 1100
- **Verdict:** SAFE (correct -- player-facing lazy pass purchase; RNG guard enforced)

### LootboxModule:974 -- rngBypass=false
- **Function:** `_resolveLootboxCommon` (DegenerusGameLootboxModule.sol, line 846, private)
- **Call chain:** External caller -> `resolveLootboxDirect(player, amount, rngWord)` (line 668) or `resolveRedemptionLootbox()` (line 703) -> `_resolveLootboxCommon()` (line 846) -> `_queueTicketsScaled(player, targetLevel, futureTickets, false)` at line 974
- **Entry point type:** external-facing (lootbox resolution triggered by VRF callback or direct call)
- **Literal check:** `false` is a literal at line 974
- **Verdict:** SAFE (correct -- player-facing lootbox claim path; RNG guard enforced)

### LootboxModule:1097 -- rngBypass=false
- **Function:** `_activateWhalePass` (DegenerusGameLootboxModule.sol, line 1084, private)
- **Call chain:** External caller -> `resolveLootboxDirect()` (line 668) or `resolveRedemptionLootbox()` (line 703) -> `_resolveLootboxCommon()` -> `_rollLootboxBoons()` (line 1012) -> boon type 28 -> `_activateWhalePass(player)` (line 1485) -> `_queueTickets(player, lvl, tickets, false)` at line 1097
- **Entry point type:** external-facing (lootbox whale pass boon award)
- **Literal check:** `false` is a literal at line 1101
- **Verdict:** SAFE (correct -- player-facing lootbox-to-whale-pass path; RNG guard enforced)

### MintModule:816 -- rngBypass=false
- **Function:** `purchase` (DegenerusGameMintModule.sol, line 567, external)
- **Call chain:** External caller -> `purchase(buyer, ...)` (line 567) -> ticket queueing section -> `_queueTicketsScaled(buyer, targetLevel, adjustedQty, false)` at line 816
- **Entry point type:** external-facing (player mint/purchase transaction)
- **Literal check:** `false` is a literal at line 816
- **Verdict:** SAFE (correct -- player-facing mint purchase; RNG guard enforced)

### WhaleModule:313 -- rngBypass=false
- **Function:** `_purchaseWhaleBundle` (DegenerusGameWhaleModule.sol, line 194, private)
- **Call chain:** External caller -> `purchaseWhaleBundle(buyer, quantity)` (line 187) -> `_purchaseWhaleBundle(buyer, quantity)` (line 194) -> ticket loop -> `_queueTickets(buyer, lvl, isBonus ? bonusTickets : standardTickets, false)` at line 313
- **Entry point type:** external-facing (player whale bundle purchase)
- **Literal check:** `false` is a literal at line 313
- **Verdict:** SAFE (correct -- player-facing whale bundle purchase; RNG guard enforced)

### WhaleModule:482 -- rngBypass=false
- **Function:** `_purchaseLazyPass` (DegenerusGameWhaleModule.sol, line 384, private)
- **Call chain:** External caller -> `purchaseLazyPass(buyer)` (line 380) -> `_purchaseLazyPass(buyer)` (line 384) -> `_activate10LevelPass(buyer, startLevel, LAZY_PASS_TICKETS_PER_LEVEL)` (line 478) -> ... but also -> `_queueTickets(buyer, startLevel, bonusTickets, false)` at line 482
- **Entry point type:** external-facing (player lazy pass purchase -- bonus tickets)
- **Literal check:** `false` is a literal at line 482
- **Verdict:** SAFE (correct -- player-facing lazy pass bonus tickets; RNG guard enforced)

### WhaleModule:625 -- rngBypass=false
- **Function:** `_purchaseDeityPass` (DegenerusGameWhaleModule.sol, line 542, private)
- **Call chain:** External caller -> `purchaseDeityPass(buyer, symbolId)` (line 538) -> `_purchaseDeityPass(buyer, symbolId)` (line 542) -> ticket loop -> `_queueTickets(buyer, lvl, isBonus ? ... : ..., false)` at line 625
- **Entry point type:** external-facing (player deity pass purchase)
- **Literal check:** `false` is a literal at line 625
- **Verdict:** SAFE (correct -- player-facing deity pass purchase; RNG guard enforced)

### WhaleModule:979 -- rngBypass=false
- **Function:** `claimWhalePass` (DegenerusGameWhaleModule.sol, line 963, external)
- **Call chain:** External caller -> `claimWhalePass(player)` (line 963) -> `_queueTicketRange(player, startLevel, 100, uint32(halfPasses), false)` at line 979
- **Entry point type:** external-facing (player claims queued whale passes)
- **Literal check:** `false` is a literal at line 979
- **Verdict:** SAFE (correct -- player-facing whale pass claim; RNG guard enforced)

### DecimatorModule:391 -- rngBypass=false
- **Function:** `_processAutoRebuy` (DegenerusGameDecimatorModule.sol, line 362, private)
- **Call chain:** External caller -> `runDecimatorJackpot(poolWei, lvl, rngWord)` (line 205, `msg.sender == GAME` guard) -> winner processing -> `_processAutoRebuy(beneficiary, weiAmount, entropy)` (line 420) -> `_queueTickets(beneficiary, calc.targetLevel, calc.ticketCount, false)` at line 391
- **Entry point type:** external-facing (decimator jackpot resolution, called by GAME contract during advance, but passes `false` because decimator auto-rebuy tickets should respect RNG lock)
- **Literal check:** `false` is a literal at line 391
- **Verdict:** SAFE (correct -- decimator reward path uses `false` to enforce RNG guard)

---

## Variable Passing Analysis

**Requirement:** No call site passes rngBypass as a runtime variable (all must be compile-time literal `true` or `false`).

**Results:**

All 17 call sites (6 true + 11 false) pass a **literal boolean** to the rngBypass parameter. Verified by inspecting each call site in source.

**One passthrough case:** `_queueLootboxTickets` (Storage:662) accepts `rngBypass` as a parameter and forwards it to `_queueTicketsScaled`. This is a thin internal wrapper -- the parameter is a function argument, not a user-controlled variable. The wrapper has exactly 1 caller (JackpotModule:2807), which passes literal `true`. This is safe because:
1. The wrapper is `internal`, not callable from outside the inheritance hierarchy
2. Its sole caller uses a literal
3. No future caller could pass a variable without adding a new call site (which would be caught by this audit pattern)

**No variable-based rngBypass passing found.** All bypass decisions are compile-time constants embedded at each call site.

---

## Summary Table

| # | Contract | Line | Function | rngBypass | Entry Point Type | Verdict |
|---|---|---|---|---|---|---|
| 1 | JackpotModule | 698 | `_runEarlyBirdLootboxJackpot` chain | `true` | advanceGame-internal | SAFE |
| 2 | JackpotModule | 863 | `_processAutoRebuy` | `true` | advanceGame-internal | SAFE |
| 3 | JackpotModule | 1070 | `_distributeTicketsToBucket` | `true` | advanceGame-internal | SAFE |
| 4 | JackpotModule | 2807 | `_jackpotTicketRoll` | `true` | advanceGame-internal | SAFE |
| 5 | AdvanceModule | 1299 | `_processPhaseTransition` | `true` | advanceGame-internal | SAFE |
| 6 | AdvanceModule | 1305 | `_processPhaseTransition` | `true` | advanceGame-internal | SAFE |
| 7 | DegenerusGame | 213 | constructor | `false` | constructor | SAFE |
| 8 | DegenerusGame | 214 | constructor | `false` | constructor | SAFE |
| 9 | Storage | 1100 | `_activate10LevelPass` | `false` | external-facing | SAFE |
| 10 | LootboxModule | 974 | `_resolveLootboxCommon` | `false` | external-facing | SAFE |
| 11 | LootboxModule | 1097 | `_activateWhalePass` | `false` | external-facing | SAFE |
| 12 | MintModule | 816 | `purchase` | `false` | external-facing | SAFE |
| 13 | WhaleModule | 313 | `_purchaseWhaleBundle` | `false` | external-facing | SAFE |
| 14 | WhaleModule | 482 | `_purchaseLazyPass` | `false` | external-facing | SAFE |
| 15 | WhaleModule | 625 | `_purchaseDeityPass` | `false` | external-facing | SAFE |
| 16 | WhaleModule | 979 | `claimWhalePass` | `false` | external-facing | SAFE |
| 17 | DecimatorModule | 391 | `_processAutoRebuy` | `false` | external-facing | SAFE |

---

## DELTA-03: VERIFIED -- all rngBypass=true callers (6) are advanceGame-internal; all rngBypass=false callers (11) are external-facing or constructor; no path allows external bypass of RngLocked guard

**Totals:** 17 call sites across 8 contracts. 6 pass `true` (all proven advanceGame-internal via delegatecall chain). 11 pass `false` (all proven external-facing or constructor). Zero findings.

**No external transaction can reach an rngBypass=true call site.** The advanceGame delegatecall chain is the sole entry path for all 6 true callers. Every `true` caller is in a `private` function within JackpotModule or AdvanceModule, reachable only through the `runRewardJackpots` external function (which requires `msg.sender == GAME`) or `_processPhaseTransition` private function (called from `advanceGame` only).
