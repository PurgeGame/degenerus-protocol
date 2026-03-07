# Cross-Protocol Gas Flags Aggregation

**Scope:** All 22 deployable contracts + 10 modules + 5 libraries
**Date:** 2026-03-07
**Source:** Phases 50-56 gas flag data + fresh source scan

---

## 1. Impossible Condition Checks (GAS-01)

Scan of ALL source contracts for conditions that can NEVER be true at the point they are checked.

| # | Contract | Function | Line(s) | Condition | Why Impossible | Impact (gas) | Intentional? |
|---|----------|----------|---------|-----------|----------------|-------------|-------------|
| 1 | BurnieCoin | `_mint` | 469 | `to == address(0)` | All callers pass non-zero addresses (game contract, coinflip claims, quest rewards). The only mint paths are `mintForCoinflip` (player from coinflip), `creditLinkReward` (player from admin), and `_recordMintDataModule` return path. All validate upstream. | ~22 gas (JUMPI) | Yes -- defensive ERC20 standard pattern |
| 2 | BurnieCoin | `_burn` | 489 | `from == address(0)` | All callers pass msg.sender or validated player addresses. Zero address cannot hold tokens. | ~22 gas | Yes -- defensive ERC20 standard pattern |
| 3 | BurnieCoin | `_transfer` | 443 | `from == address(0) \|\| to == address(0)` | Standard ERC20 defense; `transfer()` uses msg.sender (never zero), `transferFrom()` checks allowance (zero address has no allowance). | ~44 gas | Yes -- defensive ERC20 standard pattern |
| 4 | DegenerusVaultShare | `vaultMint` | 257 | `to == address(0)` | Only called from vault `burnCoin`/`burnEth` refill path with `msg.sender` (never zero) or vault owner. | ~22 gas | Yes -- defensive |
| 5 | DegenerusVaultShare | `_transfer` | 289 | `to == address(0)` | Standard ERC20 transfer target check. Users would lose tokens. | ~22 gas | Yes -- defensive ERC20 |
| 6 | WrappedWrappedXRP | `_mint` | (internal) | `to == address(0)` | All mint paths validate recipient upstream (game rewards, vault mints). | ~22 gas | Yes -- defensive ERC20 |
| 7 | WrappedWrappedXRP | `_transfer` | (internal) | `to == address(0)` | Standard ERC20 defense. | ~22 gas | Yes -- defensive ERC20 |
| 8 | DegenerusGame | `recordMint` | 397 | `msg.sender != address(this)` | Only called via delegatecall from mint module which executes in game context, so msg.sender IS address(this). This check is a critical safety net preventing external calls. | ~22 gas | Yes -- critical access control |
| 9 | DegenerusGame | `runDecimatorJackpot` | 1222 | `msg.sender != address(this)` | Only called from advance module delegatecall context. Same pattern as recordMint. | ~22 gas | Yes -- critical access control |
| 10 | DegenerusGame | `runTerminalJackpot` | 1250 | `msg.sender != address(this)` | Only called from jackpot module delegatecall context. | ~22 gas | Yes -- critical access control |
| 11 | DegenerusGame | `consumeDecClaim` | 1272 | `msg.sender != address(this)` | Only called from decimator module delegatecall context. | ~22 gas | Yes -- critical access control |
| 12 | DegenerusGame | `consumePurchaseBoost` | 907 | `msg.sender != address(this)` | Only called from mint module delegatecall context. | ~22 gas | Yes -- critical access control |
| 13 | DegenerusGame | `setOperatorApproval` | 477 | `operator == address(0)` | Caller would be setting approval for zero address, which is meaningless but technically possible. | ~22 gas | Yes -- defensive |
| 14 | DegenerusGame | `recordMint` | 404 | `prizeContribution != 0` | With DirectEth, prizeContribution = amount which is always > 0 (validated by `msg.value < amount` check). With Claimable, prizeContribution = amount > 0. With Combined, prizeContribution = msg.value + claimableUsed >= amount > 0. The check is only false if amount=0, but amount=costWei which is always > 0 for valid mints. | ~22 gas | Yes -- defensive for edge cases |
| 15 | DegenerusGame | `recordMint` | 407 | `futureShare != 0` after `(prizeContribution * 1000) / 10000` | futureShare is 10% of prizeContribution. Only zero if prizeContribution < 10 wei, which is impossible given minimum ticket prices (~0.001 ETH). | ~22 gas | Yes -- defensive |
| 16 | DegenerusGame | `_revertDelegate` | 1081 | `reason.length == 0` | Failed delegatecalls to valid module addresses always include revert data. Only empty if delegatecall to EOA (impossible with constant module addresses). | ~22 gas | Yes -- defensive fallback |
| 17 | DegenerusStonk | `constructor` | 349 | `totalAllocated < INITIAL_SUPPLY` | BPS sum is 2000+1143+3428+1143+1143+1143 = 10000 = 100%. With integer division rounding, totalAllocated could be slightly less than INITIAL_SUPPLY. The dust redistribution handles this correctly. | Dust only | Yes -- defensive rounding handler |
| 18 | DegenerusAdmin | `emergencyRecover` | 481 | `subscriptionId == 0` | subscriptionId is set in constructor and only cleared by shutdown (which is gameover-gated). Emergency recovery requires !gameOver, so subscriptionId is always non-zero. | ~22 gas | Yes -- defensive |
| 19 | JackpotBucketLib | `_calcShares` | (lib) | Defensive cap in share calculation | Cap mechanism verified to never trigger with current constants (max 4 buckets, each gets >= floor share). | ~22 gas | Yes -- defensive against future constant changes |

**Summary:** All 19 impossible conditions found are **intentional defensive programming patterns**. None represent true gas waste -- they are safety nets that cost ~22 gas each (a single JUMPI). Removing any of them would save negligible gas while reducing defense-in-depth.

---

## 2. Redundant Storage Reads (GAS-02)

Scan for storage variables read multiple times in the same function where value cannot have changed between reads.

| # | Contract | Function | Line(s) | Variable | Times Read | Could Cache? | Est. Gas Save |
|---|----------|----------|---------|----------|------------|-------------|--------------|
| 1 | BurnieCoinflip | `_claimCoinflipsInternal` | 434,436 | `degenerusGame` (immutable) | 2+ | N/A (immutable, no SLOAD) | 0 -- compiler inlines immutable |
| 2 | BurnieCoinflip | `_depositCoinflip` | 274,290-302 | `degenerusGame` (immutable) | 3 | N/A (immutable) | 0 |
| 3 | BurnieCoinflip | `claimCoinflips` / `claimCoinflipsTakeProfit` / `claimCoinflipsFromBurnie` / `consumeCoinflipsForBurn` | 334,354,364 | `degenerusGame.rngLocked()` | 1 per function | N/A (single read per function) | 0 |
| 4 | DegenerusGame | `claimAffiliateDgnrs` | 1446-1465 | `level` (storage) | 1 | Already cached in local `currLevel` | 0 -- already optimized |
| 5 | DegenerusGame | `recordMint` | 399-416 | `prizeContribution` (local) | N/A (already local var) | N/A | 0 |
| 6 | DegenerusStonk | `lockForLevel` | 438-439 | `game.level()` | 1 | Already cached in local `currentLevel` | 0 -- already optimized |
| 7 | DegenerusStonk | `gamePurchase` | 497-498 | `game.mintPrice()` | 1 | Single read | 0 |
| 8 | DegenerusVault | `_isVaultOwner` | 411-413 | `ethShare.totalSupply()` + `ethShare.balanceOf()` | 2 external calls | Could batch but different calls | ~200 gas (warm STATICCALL overhead) |
| 9 | LootboxModule | `_resolveLootboxCommon` via `_deityBoonForSlot` | (module) | `rngWordByDay[day]` | Up to 3 (once per slot in loop) | Yes -- cache daily seed before loop | ~200 gas (2 warm SLOADs saved) |
| 10 | DegenerusStonk | `_checkAndRecordEthSpend` / `_lockedClaimableValues` | multiple | `game.level()` | Called from multiple functions per tx | Each function caches separately, but cross-function calls may re-read | ~2100 gas (cold) or ~100 gas (warm) per extra read |
| 11 | BurnieCoin | `balanceOfWithClaimable` | 284-290 | `_supply.vaultAllowance` | 1 (only for VAULT) | Single read | 0 |
| 12 | DegenerusAdmin | `onTokenTransfer` | (admin) | `this._linkAmountToEth(amount)` via external self-call | 1 | Necessary for try/catch pattern | 0 -- pattern required |

**Summary:** The codebase is extremely well-optimized for storage reads. Only 2 items have any practical optimization potential:

1. **LootboxModule `rngWordByDay[day]` in boon loop** (Item 9): Could save ~200 gas by caching the daily seed before the 3-iteration boon slot loop. The optimizer may already handle this.
2. **DegenerusStonk cross-function `game.level()` reads** (Item 10): Multiple spend-check functions may redundantly read `game.level()` within the same transaction. Savings depend on call patterns.

All other storage reads are either already cached in local variables, use immutable references (no SLOAD), or are single reads per function.

---

